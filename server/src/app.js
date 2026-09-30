import { createServer } from 'node:http';
import { makeAuthenticator } from './auth.js';
import { circleRoutes } from './circles.js';
import { ACCOUNT_SCHEMA, accountRoutes, makeAccountAuthenticator } from './accounts.js';
import { dailyRoutes, ensureDailySchema } from './daily.js';
import { makeSender, NOTIFY_SCHEMA, notifyRoutes, startTelegramLinker } from './notify.js';
import { startDailyReminders } from './dailyReminders.js';
import { openDatabase } from './db.js';
import { galleryRoutes } from './gallery.js';
import { clientIp, HttpError, notFound, readJson, send, sendError, sendHtml } from './http.js';
import { memberRoutes } from './members.js';
import { RateLimiter } from './ratelimit.js';
import { compileRoutes, matchRoute } from './router.js';
import { pruneStats, statsRoutes } from './stats.js';

const DEFAULT_BODY_LIMIT = 16 * 1024;
const HAS_BODY = new Set(['POST', 'PUT', 'PATCH']);

function healthRoute() {
  return {
    method: 'GET',
    path: '/health',
    auth: 'none',
    exempt: true,
    async handler({ ctx }) {
      ctx.db.prepare('SELECT 1').get();
      return { status: 200, body: { ok: true } };
    },
  };
}

/**
 * Builds the service without listening, so tests can start it on a random
 * port with their own clock and data directory.
 */
export function createApp({ config, now = Date.now, log = console, fetchImpl = fetch }) {
  const db = openDatabase(config.dataDir);
  db.exec(ACCOUNT_SCHEMA);
  ensureDailySchema(db);
  db.exec(NOTIFY_SCHEMA);
  const authenticate = makeAuthenticator(db);
  const authenticateAccount = makeAccountAuthenticator(db, now);
  // Routes that accept either an account or a website token check it
  // themselves, so the authenticators travel in the context.
  const ctx = { db, config, now, log, authenticate, authenticateAccount, sendNotification: makeSender(config, fetchImpl) };
  const r = config.rate;
  const limiters = {
    ip: RateLimiter.perMinute(r.ipCapacity, r.ipPerMinute, now),
    member: RateLimiter.perMinute(r.memberCapacity, r.memberPerMinute, now),
    signup: RateLimiter.perHour(r.signupCapacity, r.signupPerHour, now),
    join: RateLimiter.perHour(r.joinCapacity, r.joinPerHour, now),
    gallery: RateLimiter.perHour(r.galleryCapacity, r.galleryPerHour, now),
    auth: RateLimiter.perHour(r.authCapacity, r.authPerHour, now),
  };
  const routes = compileRoutes([
    healthRoute(),
    ...memberRoutes(),
    ...circleRoutes(),
    ...statsRoutes(),
    ...galleryRoutes(),
    ...dailyRoutes(),
    ...accountRoutes({ config, fetchImpl }),
    ...notifyRoutes({ fetchImpl }),
  ]);

  function limit(limiter, key) {
    const wait = limiter.take(key);
    if (wait > 0) {
      throw new HttpError(429, 'rate_limited', 'Too many requests, slow down', { 'Retry-After': String(wait) });
    }
  }

  async function handle(req, res) {
    try {
      const url = new URL(req.url ?? '/', 'http://localhost');
      let path = url.pathname;
      const base = config.basePath;
      if (base) {
        if (path !== base && !path.startsWith(base + '/')) throw notFound();
        path = path.slice(base.length) || '/';
      }
      if (path.length > 1 && path.endsWith('/')) path = path.slice(0, -1);

      const hit = matchRoute(routes, req.method ?? 'GET', path);
      if (!hit) throw notFound();
      if (!hit.route) {
        throw new HttpError(405, 'method_not_allowed', 'Method not allowed', { Allow: hit.allowed.join(', ') });
      }
      const { route, params } = hit;
      const ip = clientIp(req, config.trustProxy);

      if (!route.exempt) limit(limiters.ip, ip);
      let member = null;
      let account = null;
      if (route.auth === 'member') {
        member = authenticate(req);
        limit(limiters.member, member.id);
      }
      if (route.auth === 'account') {
        account = authenticateAccount(req);
        limit(limiters.member, `a:${account.id}`);
      }
      if (route.bucket === 'auth') limit(limiters.auth, ip);
      if (route.bucket === 'signup') limit(limiters.signup, ip);
      if (route.bucket === 'gallery') limit(limiters.gallery, ip);
      if (route.bucket === 'join') {
        // Both keys: one member cannot guess from many addresses, and one
        // address cannot guess with many fresh members.
        limit(limiters.join, `m:${member.id}`);
        limit(limiters.join, `ip:${ip}`);
      }

      let body;
      if (HAS_BODY.has(req.method)) {
        body = await readJson(req, route.bodyLimit ?? DEFAULT_BODY_LIMIT);
      } else {
        req.resume();
      }

      const result = await route.handler({ ctx, req, params, body, member, account, query: url.searchParams });
      if (result.html !== undefined) sendHtml(res, result.status, result.html);
      else send(res, result.status, result.body);
    } catch (err) {
      if (!(err instanceof HttpError)) log.error?.('[friends] unhandled error:', err);
      sendError(res, err);
      // Stop reading a body we refused; keep-alive would otherwise stall.
      if (!req.complete) req.resume();
    }
  }

  const server = createServer((req, res) => {
    handle(req, res);
  });
  server.headersTimeout = 10_000;
  server.requestTimeout = 15_000;
  server.keepAliveTimeout = 5_000;

  const sweep = () => {
    for (const l of Object.values(limiters)) l.sweep();
  };
  const prune = () => {
    try {
      pruneStats(db, now(), config.statsRetentionDays);
    } catch (err) {
      log.error?.('[friends] prune failed:', err);
    }
  };
  prune();
  const timers = [setInterval(sweep, 5 * 60_000), setInterval(prune, 6 * 3_600_000)];
  for (const t of timers) t.unref();
  const reminders = startDailyReminders({ ctx, env: config.reminderEnv ?? process.env, log, fetchImpl });
  const telegram = config.startBots === false ? { stop() {} } : startTelegramLinker({ ctx, log, fetchImpl });

  let closed = false;
  async function close() {
    if (closed) return;
    closed = true;
    for (const t of timers) clearInterval(t);
    reminders.stop();
    telegram.stop();
    await new Promise((resolve) => {
      if (!server.listening) return resolve();
      server.close(() => resolve());
      server.closeIdleConnections?.();
    });
    db.close();
  }

  return { server, db, ctx, limiters, close };
}

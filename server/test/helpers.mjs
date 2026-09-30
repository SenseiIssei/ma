import { randomBytes, randomUUID } from 'node:crypto';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';

// Shared test harness: an in-memory database, a clock the test controls and
// a fetch wrapper that speaks the API's auth scheme.

export const ADMIN = 'test-admin-token';
// Wednesday 30 Sep 2026, 12:00 UTC. Its week runs Mon 28 Sep to Sun 4 Oct.
export const NOON = Date.UTC(2026, 8, 30, 12, 0, 0);
export const DAY = 86_400_000;

export async function startServer(env = {}) {
  const clock = { t: NOON };
  const config = loadConfig({
    DATA_DIR: ':memory:',
    ADMIN_TOKEN: ADMIN,
    RATE_IP_CAPACITY: '10000',
    RATE_IP_PER_MINUTE: '10000',
    RATE_MEMBER_CAPACITY: '10000',
    RATE_MEMBER_PER_MINUTE: '10000',
    RATE_SIGNUP_CAPACITY: '10000',
    RATE_SIGNUP_PER_HOUR: '10000',
    RATE_JOIN_CAPACITY: '10000',
    RATE_JOIN_PER_HOUR: '10000',
    RATE_GALLERY_CAPACITY: '10000',
    RATE_GALLERY_PER_HOUR: '10000',
    RATE_AUTH_CAPACITY: '10000',
    RATE_AUTH_PER_HOUR: '10000',
    ...env,
  });
  // No bot polling in tests; network calls go through the stub below.
  config.startBots = false;
  const fetchStub = { handler: null, calls: [] };
  const fetchImpl = async (url, options = {}) => {
    fetchStub.calls.push({ url: String(url), options });
    if (!fetchStub.handler) throw new Error(`unexpected fetch ${url}`);
    return fetchStub.handler(String(url), options);
  };
  const app = createApp({ config, now: () => clock.t, log: { error() {} }, fetchImpl });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${app.server.address().port}`;
  const prefix = config.basePath;

  async function request(method, path, { token, body, raw, headers = {}, ip } = {}) {
    const h = { ...headers };
    if (token) h.Authorization = `Bearer ${token}`;
    if (ip) h['X-Real-IP'] = ip;
    let payload;
    if (raw !== undefined) {
      payload = raw;
      h['Content-Type'] = 'application/json';
    } else if (body !== undefined) {
      payload = JSON.stringify(body);
      h['Content-Type'] = 'application/json';
    }
    const res = await fetch(origin + prefix + path, { method, headers: h, body: payload });
    const text = await res.text();
    let json = null;
    if (text) json = JSON.parse(text);
    return { status: res.status, body: json, headers: res.headers };
  }

  async function newMember(nickname = 'Kai', extra = {}) {
    const id = randomUUID();
    const secret = randomBytes(32).toString('hex');
    const res = await request('POST', '/members', { body: { id, secret, nickname, ...extra } });
    if (res.status !== 201) throw new Error(`member create failed: ${res.status} ${JSON.stringify(res.body)}`);
    return { id, secret, token: `${id}.${secret}`, nickname };
  }

  /** An account, confirmed unless told otherwise; returns email and session. */
  async function newAccount(email, { verified = true, password = 'correct horse battery' } = {}) {
    const res = await request('POST', '/auth/register', { body: { email, password } });
    if (res.status !== 201) throw new Error(`register failed: ${res.status} ${JSON.stringify(res.body)}`);
    if (verified) app.db.prepare('UPDATE accounts SET email_verified_at = ? WHERE email = ?').run(clock.t, email.toLowerCase());
    return { email, password, session: res.body.session, id: res.body.account.id };
  }

  async function newCircle(owner, name = 'Morning crew') {
    const res = await request('POST', '/circles', { token: owner.token, body: { name } });
    if (res.status !== 201) throw new Error(`circle create failed: ${res.status} ${JSON.stringify(res.body)}`);
    return res.body;
  }

  return {
    app,
    fetchStub,
    clock,
    origin,
    prefix,
    request,
    newMember,
    newAccount,
    newCircle,
    close: () => app.close(),
  };
}

export function stats(overrides = {}) {
  return { streakDays: 3, focusMinutes: 50, pomodoros: 2, resisted: 4, correctAnswers: 12, habitsDone: 3, ...overrides };
}

export function day(offsetDays = 0) {
  return new Date(NOON + offsetDays * DAY).toISOString().slice(0, 10);
}

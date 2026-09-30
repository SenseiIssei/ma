import { randomBytes } from 'node:crypto';
import { featuresOf, page } from './accounts.js';
import { HttpError, notFound } from './http.js';
import { object } from './validate.js';

// Personal reminder channels for an account with the "reminders" feature.
// Linking is one tap in Ma: Telegram opens the bot with a one-time code
// (t.me/<bot>?start=<code>), Discord signs in with "identify" and returns
// here. Each account keeps its own targets and its own reminder time.

export const NOTIFY_SCHEMA = `
CREATE TABLE IF NOT EXISTS notify_targets (
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  channel    TEXT NOT NULL CHECK (channel IN ('telegram', 'discord')),
  target     TEXT NOT NULL,
  label      TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (account_id, channel)
);
CREATE TABLE IF NOT EXISTS notify_codes (
  code       TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  channel    TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS notify_settings (
  account_id    TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  minute_of_day INTEGER NOT NULL
);
`;

const CODE_LIFETIME_MS = 15 * 60_000;
const CODE_PATTERN = /^[A-Za-z0-9_-]{16,64}$/;
const DEFAULT_MINUTE = 9 * 60;
const FETCH_TIMEOUT_MS = 10_000;

async function fetchJson(fetchImpl, url, options = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), options.timeout ?? FETCH_TIMEOUT_MS);
  try {
    const response = await fetchImpl(url, { ...options, signal: options.signal ?? controller.signal });
    const body = await response.json().catch(() => null);
    if (!response.ok) throw new Error(`${new URL(url).host} answered ${response.status}`);
    return body;
  } finally {
    clearTimeout(timer);
  }
}

export function channelsAvailable(config) {
  return {
    telegram: Boolean(config.telegram.botToken && config.telegram.botName),
    discord: Boolean(config.discord.botToken && config.discord.clientId && config.discord.clientSecret),
  };
}

export function reminderMinute(db, accountId) {
  return db.prepare('SELECT minute_of_day FROM notify_settings WHERE account_id = ?').get(accountId)?.minute_of_day ?? DEFAULT_MINUTE;
}

function requireReminders(ctx, account) {
  if (!featuresOf(account, ctx.config).includes('reminders')) {
    throw new HttpError(403, 'forbidden', 'This account has no personal reminders');
  }
}

function newCode(db, accountId, channel, now) {
  db.prepare('DELETE FROM notify_codes WHERE expires_at <= ? OR (account_id = ? AND channel = ?)').run(now, accountId, channel);
  const code = randomBytes(18).toString('base64url');
  db.prepare('INSERT INTO notify_codes (code, account_id, channel, expires_at) VALUES (?, ?, ?, ?)').run(code, accountId, channel, now + CODE_LIFETIME_MS);
  return code;
}

function takeCode(db, code, channel, now) {
  if (typeof code !== 'string' || !CODE_PATTERN.test(code)) return null;
  const row = db.prepare('SELECT account_id, expires_at FROM notify_codes WHERE code = ? AND channel = ?').get(code, channel);
  if (!row || row.expires_at <= now) return null;
  db.prepare('DELETE FROM notify_codes WHERE code = ?').run(code);
  return row.account_id;
}

function saveTarget(db, accountId, channel, target, label, now) {
  db.prepare(
    `INSERT INTO notify_targets (account_id, channel, target, label, created_at) VALUES (?, ?, ?, ?, ?)
     ON CONFLICT (account_id, channel) DO UPDATE SET target = excluded.target, label = excluded.label, created_at = excluded.created_at`,
  ).run(accountId, channel, String(target), String(label).slice(0, 80), now);
}

/** Sends one text to every linked channel of an account; returns failures. */
export function makeSender(config, fetchImpl = fetch) {
  async function telegram(chatId, text) {
    await fetchJson(fetchImpl, `https://api.telegram.org/bot${config.telegram.botToken}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: chatId, text: text.slice(0, 4000) }),
    });
  }
  async function discord(userId, text) {
    const headers = { Authorization: `Bot ${config.discord.botToken}`, 'Content-Type': 'application/json' };
    const channel = await fetchJson(fetchImpl, 'https://discord.com/api/v10/users/@me/channels', {
      method: 'POST',
      headers,
      body: JSON.stringify({ recipient_id: userId }),
    });
    await fetchJson(fetchImpl, `https://discord.com/api/v10/channels/${channel.id}/messages`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ content: text.slice(0, 1900) }),
    });
  }
  return async function send(db, accountId, text) {
    const targets = db.prepare('SELECT channel, target FROM notify_targets WHERE account_id = ?').all(accountId);
    const results = await Promise.allSettled(
      targets.map((target) => (target.channel === 'telegram' ? telegram(target.target, text) : discord(target.target, text))),
    );
    return results
      .map((result, index) => (result.status === 'rejected' ? `${targets[index].channel}: ${result.reason?.message ?? result.reason}` : null))
      .filter(Boolean);
  };
}

export function notifyRoutes({ fetchImpl = fetch } = {}) {
  return [
    {
      method: 'GET',
      path: '/notify',
      auth: 'account',
      async handler({ ctx, account }) {
        requireReminders(ctx, account);
        const available = channelsAvailable(ctx.config);
        const targets = ctx.db.prepare('SELECT channel, label, created_at FROM notify_targets WHERE account_id = ?').all(account.id);
        const byChannel = Object.fromEntries(targets.map((target) => [target.channel, target]));
        const minute = reminderMinute(ctx.db, account.id);
        const channel = (name) => ({ available: available[name], connected: Boolean(byChannel[name]), label: byChannel[name]?.label ?? null });
        return {
          status: 200,
          body: {
            telegram: channel('telegram'),
            discord: channel('discord'),
            time: `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`,
          },
        };
      },
    },
    {
      method: 'POST',
      path: '/notify/:channel/link',
      auth: 'account',
      async handler({ ctx, account, params }) {
        requireReminders(ctx, account);
        const { channel } = params;
        const available = channelsAvailable(ctx.config);
        if (channel !== 'telegram' && channel !== 'discord') throw notFound();
        if (!available[channel]) throw new HttpError(409, 'not_configured', `${channel} is not set up on the server yet`);
        const code = newCode(ctx.db, account.id, channel, ctx.now());
        if (channel === 'telegram') {
          return { status: 201, body: { url: `https://t.me/${ctx.config.telegram.botName}?start=${code}` } };
        }
        const redirect = `${ctx.config.publicOrigin}${ctx.config.basePath}/notify/discord/callback`;
        const url = new URL('https://discord.com/oauth2/authorize');
        url.searchParams.set('client_id', ctx.config.discord.clientId);
        url.searchParams.set('response_type', 'code');
        url.searchParams.set('redirect_uri', redirect);
        url.searchParams.set('scope', 'identify');
        url.searchParams.set('state', code);
        url.searchParams.set('prompt', 'none');
        return { status: 201, body: { url: url.toString() } };
      },
    },
    {
      method: 'GET',
      path: '/notify/discord/callback',
      auth: 'none',
      bucket: 'auth',
      async handler({ ctx, query }) {
        const failed = (message) => ({ status: 400, html: page('Discord', message) });
        const accountId = takeCode(ctx.db, query.get('state'), 'discord', ctx.now());
        const code = query.get('code');
        if (!accountId || !code) return failed('This link has expired. Tap "Connect Discord" in Ma again.');
        const { discord } = ctx.config;
        try {
          const token = await fetchJson(fetchImpl, 'https://discord.com/api/v10/oauth2/token', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({
              client_id: discord.clientId,
              client_secret: discord.clientSecret,
              grant_type: 'authorization_code',
              code,
              redirect_uri: `${ctx.config.publicOrigin}${ctx.config.basePath}/notify/discord/callback`,
            }),
          });
          const user = await fetchJson(fetchImpl, 'https://discord.com/api/v10/users/@me', {
            headers: { Authorization: `Bearer ${token.access_token}` },
          });
          saveTarget(ctx.db, accountId, 'discord', user.id, user.global_name || user.username || 'Discord', ctx.now());
        } catch (error) {
          ctx.log?.error?.('[notify] discord link failed:', error?.message ?? error);
          return failed('Discord did not answer as expected. Try again in a moment.');
        }
        return {
          status: 200,
          html: page('Discord verbunden', 'Ma schickt dir die Erinnerung ab jetzt als Direktnachricht. Du kannst zur App zurück.', {
            lang: 'de',
            extra: '<a class="button" href="ma://notify/linked">Ma öffnen</a>',
          }),
        };
      },
    },
    {
      method: 'DELETE',
      path: '/notify/:channel',
      auth: 'account',
      async handler({ ctx, account, params }) {
        requireReminders(ctx, account);
        ctx.db.prepare('DELETE FROM notify_targets WHERE account_id = ? AND channel = ?').run(account.id, params.channel);
        return { status: 204 };
      },
    },
    {
      method: 'PUT',
      path: '/notify/time',
      auth: 'account',
      async handler({ ctx, account, body }) {
        requireReminders(ctx, account);
        object(body, ['time']);
        const match = /^(\d{1,2}):(\d{2})$/.exec(typeof body.time === 'string' ? body.time : '');
        if (!match || Number(match[1]) > 23 || Number(match[2]) > 59) throw new HttpError(400, 'bad_request', 'time must look like 09:00');
        const minute = Number(match[1]) * 60 + Number(match[2]);
        ctx.db
          .prepare('INSERT INTO notify_settings (account_id, minute_of_day) VALUES (?, ?) ON CONFLICT (account_id) DO UPDATE SET minute_of_day = excluded.minute_of_day')
          .run(account.id, minute);
        return { status: 204 };
      },
    },
    {
      method: 'POST',
      path: '/notify/test',
      auth: 'account',
      bucket: 'auth',
      async handler({ ctx, account }) {
        requireReminders(ctx, account);
        const failures = await ctx.sendNotification(ctx.db, account.id, 'Ma: Test. So sieht deine tägliche Erinnerung aus.');
        return { status: 200, body: { failures } };
      },
    },
  ];
}

/**
 * Long polling for the Telegram bot: "/start <code>" links the chat to the
 * account that asked for the code. Runs only when a bot token is set.
 */
export function startTelegramLinker({ ctx, fetchImpl = fetch, log = console }) {
  const { botToken } = ctx.config.telegram;
  if (!botToken) return { stop() {} };
  let stopped = false;
  let offset = 0;
  const controller = new AbortController();
  const api = (method, body) =>
    fetchJson(fetchImpl, `https://api.telegram.org/bot${botToken}/${method}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      timeout: 40_000,
      signal: controller.signal,
    });

  async function loop() {
    while (!stopped) {
      try {
        const answer = await api('getUpdates', { offset, timeout: 25, allowed_updates: ['message'] });
        for (const update of answer?.result ?? []) {
          offset = update.update_id + 1;
          const message = update.message;
          if (!message?.text || !message.chat) continue;
          const [command, code] = message.text.trim().split(/\s+/);
          if (command !== '/start') continue;
          const accountId = takeCode(ctx.db, code, 'telegram', ctx.now());
          const name = [message.from?.first_name, message.from?.username ? `@${message.from.username}` : null].filter(Boolean).join(' ');
          if (accountId) {
            saveTarget(ctx.db, accountId, 'telegram', message.chat.id, name || 'Telegram', ctx.now());
            await api('sendMessage', { chat_id: message.chat.id, text: 'Verbunden mit Ma. Hier kommt ab jetzt deine tägliche Erinnerung.' });
          } else {
            await api('sendMessage', { chat_id: message.chat.id, text: 'Dieser Link ist abgelaufen. Tippe in Ma noch einmal auf "Telegram verbinden".' });
          }
        }
      } catch (error) {
        if (stopped) return;
        log.error?.('[notify] telegram polling:', error?.message ?? error);
        await new Promise((resolve) => setTimeout(resolve, 15_000).unref?.());
      }
    }
  }
  loop();
  return {
    stop() {
      stopped = true;
      controller.abort();
    },
  };
}

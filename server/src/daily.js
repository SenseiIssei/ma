import { createHash, randomBytes, randomInt, timingSafeEqual } from 'node:crypto';
import { transaction } from './db.js';
import { badRequest, HttpError, isoTime } from './http.js';
import { object } from './validate.js';
import {
  addDays,
  berlinDayKey,
  clampXpReward,
  isDayKey,
  replayEntries,
  summarize,
} from './dailyStreak.js';

// The daily programming lesson from senseiissei.dev. The website shows the
// lesson; this service keeps the record, so the Ma app can count the lessons
// as experience next to workouts. The public console is open to everyone, so
// only a browser linked to a Ma member may write: the app asks for a short
// one-time code, the console trades it for a token that can do nothing but
// record lessons.

export const DAILY_SCHEMA = `
CREATE TABLE IF NOT EXISTS daily_link_codes (
  code       TEXT PRIMARY KEY,
  member_id  TEXT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS daily_links (
  token_hash   TEXT PRIMARY KEY,
  member_id    TEXT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  created_at   INTEGER NOT NULL,
  last_used_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS daily_links_by_member ON daily_links(member_id);
CREATE TABLE IF NOT EXISTS daily_entries (
  member_id    TEXT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  day_key      TEXT NOT NULL,
  unit_id      TEXT NOT NULL,
  status       TEXT NOT NULL CHECK (status IN ('done', 'skipped')),
  base_xp      INTEGER NOT NULL,
  recorded_at  INTEGER NOT NULL,
  PRIMARY KEY (member_id, day_key)
);
CREATE TABLE IF NOT EXISTS daily_reminders_sent (
  day_key TEXT PRIMARY KEY,
  sent_at INTEGER NOT NULL
);
`;

export const LINK_CODE_LIFETIME_MS = 10 * 60_000;
/** How far back a buffered completion may still be recorded. */
export const BACKFILL_DAYS = 14;

// No 0/O, 1/I/L: the code is read off a phone and typed on a keyboard.
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_PATTERN = /^[A-HJ-NP-Z2-9]{6}$/;
const TOKEN_PATTERN = /^daily_[0-9a-f]{64}$/;
const UNIT_ID_PATTERN = /^[a-z0-9][a-z0-9-]{0,63}$/;

function sha256(text) {
  return createHash('sha256').update(text, 'utf8').digest('hex');
}

function newLinkCode() {
  let code = '';
  for (let index = 0; index < 6; index++) code += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return code;
}

const unauthorized = () =>
  new HttpError(401, 'unauthorized', 'Link this browser first: daily link <code>', { 'WWW-Authenticate': 'Bearer' });

/** Resolves the daily token in the Authorization header to a member id. */
function linkedMember(ctx, req) {
  const header = req.headers.authorization;
  const token = typeof header === 'string' && header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (!TOKEN_PATTERN.test(token)) throw unauthorized();
  const hash = sha256(token);
  const row = ctx.db.prepare('SELECT token_hash, member_id FROM daily_links WHERE token_hash = ?').get(hash);
  if (!row || !timingSafeEqual(Buffer.from(row.token_hash, 'hex'), Buffer.from(hash, 'hex'))) throw unauthorized();
  ctx.db.prepare('UPDATE daily_links SET last_used_at = ? WHERE token_hash = ?').run(ctx.now(), hash);
  return row.member_id;
}

/** Either the website token or the app's own member credentials. */
function readerMember(ctx, req) {
  const header = req.headers.authorization ?? '';
  if (typeof header === 'string' && header.startsWith('Bearer daily_')) return linkedMember(ctx, req);
  return ctx.authenticate(req).id;
}

function entriesOf(db, memberId) {
  return db
    .prepare('SELECT day_key, unit_id, status, base_xp, recorded_at FROM daily_entries WHERE member_id = ? ORDER BY day_key')
    .all(memberId)
    .map((row) => ({
      dayKey: row.day_key,
      unitId: row.unit_id,
      status: row.status,
      baseXp: row.base_xp,
      recordedAt: isoTime(row.recorded_at),
    }));
}

export function dailyProgress(db, memberId, now) {
  const summary = summarize(entriesOf(db, memberId), berlinDayKey(now));
  return { ...summary, entries: summary.entries.slice(-120) };
}

function record(ctx, req, body, status) {
  const memberId = linkedMember(ctx, req);
  object(body, ['dayKey', 'unitId', 'xpReward']);
  const today = berlinDayKey(ctx.now());
  const dayKey = body.dayKey ?? today;
  if (!isDayKey(dayKey)) throw badRequest('dayKey must be a date like 2026-10-01');
  if (dayKey > today) throw badRequest('dayKey lies in the future');
  if (dayKey < addDays(today, -BACKFILL_DAYS)) throw badRequest(`Only the last ${BACKFILL_DAYS} days can be recorded`);
  if (typeof body.unitId !== 'string' || !UNIT_ID_PATTERN.test(body.unitId)) throw badRequest('unitId is not a lesson id');
  const baseXp = status === 'done' ? clampXpReward(Number(body.xpReward)) : 0;

  const { db } = ctx;
  transaction(db, () => {
    const existing = db.prepare('SELECT status FROM daily_entries WHERE member_id = ? AND day_key = ?').get(memberId, dayKey);
    // A finished lesson stays finished; skipping afterwards changes nothing.
    // Skipping first and finishing later the same day is fine.
    if (existing?.status === 'done') return;
    db.prepare(
      `INSERT INTO daily_entries (member_id, day_key, unit_id, status, base_xp, recorded_at)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT (member_id, day_key) DO UPDATE SET unit_id = excluded.unit_id, status = excluded.status,
         base_xp = excluded.base_xp, recorded_at = excluded.recorded_at`,
    ).run(memberId, dayKey, body.unitId, status, baseXp, ctx.now());
  });
  const progress = dailyProgress(db, memberId, ctx.now());
  const entry = progress.entries.find((item) => item.dayKey === dayKey) ?? null;
  return { status: 200, body: { entry, progress } };
}

export function dailyRoutes() {
  return [
    {
      method: 'POST',
      path: '/daily/link-code',
      auth: 'member',
      async handler({ ctx, member }) {
        const { db } = ctx;
        const now = ctx.now();
        db.prepare('DELETE FROM daily_link_codes WHERE expires_at <= ? OR member_id = ?').run(now, member.id);
        let code = newLinkCode();
        while (db.prepare('SELECT 1 FROM daily_link_codes WHERE code = ?').get(code)) code = newLinkCode();
        const expiresAt = now + LINK_CODE_LIFETIME_MS;
        db.prepare('INSERT INTO daily_link_codes (code, member_id, expires_at) VALUES (?, ?, ?)').run(code, member.id, expiresAt);
        return { status: 201, body: { code, expiresAt: isoTime(expiresAt) } };
      },
    },
    {
      method: 'POST',
      path: '/daily/link',
      auth: 'none',
      // Per-address hourly bucket: six characters are not much to guess.
      bucket: 'gallery',
      async handler({ ctx, body }) {
        object(body, ['code']);
        const code = typeof body.code === 'string' ? body.code.trim().toUpperCase() : '';
        if (!CODE_PATTERN.test(code)) throw badRequest('The code has six letters and digits');
        const { db } = ctx;
        const now = ctx.now();
        const token = `daily_${randomBytes(32).toString('hex')}`;
        const linked = transaction(db, () => {
          const row = db.prepare('SELECT member_id, expires_at FROM daily_link_codes WHERE code = ?').get(code);
          if (!row || row.expires_at <= now) return null;
          db.prepare('DELETE FROM daily_link_codes WHERE code = ?').run(code);
          db.prepare('INSERT INTO daily_links (token_hash, member_id, created_at, last_used_at) VALUES (?, ?, ?, ?)').run(
            sha256(token),
            row.member_id,
            now,
            now,
          );
          return row.member_id;
        });
        if (!linked) throw new HttpError(404, 'not_found', 'This code is unknown or expired. Ask Ma for a new one.');
        return { status: 201, body: { token, progress: dailyProgress(db, linked, now) } };
      },
    },
    {
      method: 'POST',
      path: '/daily/done',
      auth: 'none',
      async handler({ ctx, req, body }) {
        return record(ctx, req, body, 'done');
      },
    },
    {
      method: 'POST',
      path: '/daily/skip',
      auth: 'none',
      async handler({ ctx, req, body }) {
        return record(ctx, req, body, 'skipped');
      },
    },
    {
      method: 'GET',
      path: '/daily/progress',
      auth: 'none',
      async handler({ ctx, req }) {
        return { status: 200, body: dailyProgress(ctx.db, readerMember(ctx, req), ctx.now()) };
      },
    },
    {
      method: 'DELETE',
      path: '/daily/link',
      auth: 'none',
      async handler({ ctx, req }) {
        const header = req.headers.authorization ?? '';
        const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
        linkedMember(ctx, req);
        ctx.db.prepare('DELETE FROM daily_links WHERE token_hash = ?').run(sha256(token));
        return { status: 204 };
      },
    },
  ];
}

export { replayEntries };

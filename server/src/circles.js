import { randomInt, randomUUID } from 'node:crypto';
import { transaction } from './db.js';
import { badRequest, conflict, forbidden, HttpError, isoTime, notFound } from './http.js';
import { CHALLENGE_KINDS, challengeProgress } from './challenges.js';
import { recentDays } from './stats.js';
import { label, object, uuid } from './validate.js';

export const MAX_MEMBERS = 20;
export const MAX_CIRCLES_PER_MEMBER = 10;
export const CIRCLE_NAME_MAX = 40;

// No 0/O, 1/I/L: a code gets read aloud and typed from a screenshot.
export const CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
export const CODE_LENGTH = 8;

export function newInviteCode() {
  let code = '';
  for (let i = 0; i < CODE_LENGTH; i++) code += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return code;
}

/** Accepts "abcd-efgh", "ABCD EFGH" and the like; returns null if it cannot be a code. */
export function normalizeCode(value) {
  if (typeof value !== 'string' || value.length > 32) return null;
  const v = value.toUpperCase().replace(/[\s-]/g, '');
  if (v.length !== CODE_LENGTH) return null;
  for (const ch of v) if (!CODE_ALPHABET.includes(ch)) return null;
  return v;
}

function uniqueCode(db) {
  const exists = db.prepare('SELECT 1 FROM circles WHERE invite_code = ?');
  // 31^8 codes; a collision is astronomically rare, but loop anyway.
  for (let i = 0; i < 20; i++) {
    const code = newInviteCode();
    if (!exists.get(code)) return code;
  }
  throw new HttpError(503, 'unavailable', 'Could not create an invite code');
}

function circleCount(db, memberId) {
  return Number(db.prepare('SELECT COUNT(*) AS n FROM circle_members WHERE member_id = ?').get(memberId).n);
}

function memberCount(db, circleId) {
  return Number(db.prepare('SELECT COUNT(*) AS n FROM circle_members WHERE circle_id = ?').get(circleId).n);
}

/** The circle if `memberId` belongs to it. Outsiders get 404, not 403, so ids do not leak. */
function circleFor(db, circleId, memberId) {
  const row = db
    .prepare(
      `SELECT c.* FROM circles c
         JOIN circle_members cm ON cm.circle_id = c.id AND cm.member_id = ?
        WHERE c.id = ?`,
    )
    .get(memberId, circleId);
  if (!row) throw notFound('Circle not found');
  return row;
}

function requireCreator(circle, memberId) {
  if (circle.creator_id !== memberId) throw forbidden('Only the creator can do that');
}

/**
 * Takes a member out of a circle. If they created it, the longest-standing
 * remaining member takes over; if nobody is left, the circle is deleted.
 * Must run inside a transaction.
 */
export function detachMember(db, circleId, memberId) {
  db.prepare('DELETE FROM circle_members WHERE circle_id = ? AND member_id = ?').run(circleId, memberId);
  const circle = db.prepare('SELECT creator_id FROM circles WHERE id = ?').get(circleId);
  if (!circle) return;
  const heir = db
    .prepare('SELECT member_id FROM circle_members WHERE circle_id = ? ORDER BY joined_at, member_id LIMIT 1')
    .get(circleId);
  if (!heir) {
    db.prepare('DELETE FROM circles WHERE id = ?').run(circleId);
  } else if (circle.creator_id === memberId) {
    db.prepare('UPDATE circles SET creator_id = ? WHERE id = ?').run(heir.member_id, circleId);
  }
}

function summary(db, row, memberId) {
  return {
    id: row.id,
    name: row.name,
    inviteCode: row.invite_code,
    isCreator: row.creator_id === memberId,
    memberCount: memberCount(db, row.id),
    maxMembers: MAX_MEMBERS,
    challengeKind: row.challenge_kind ?? null,
    createdAt: isoTime(row.created_at),
  };
}

function detail(ctx, row, memberId) {
  const { db } = ctx;
  const now = ctx.now();
  const members = db
    .prepare(
      `SELECT m.id, m.nickname, m.avatar, cm.joined_at
         FROM circle_members cm JOIN members m ON m.id = cm.member_id
        WHERE cm.circle_id = ?
        ORDER BY cm.joined_at, m.id`,
    )
    .all(row.id);
  const days = recentDays(db, members.map((m) => m.id), now);
  return {
    ...summary(db, row, memberId),
    members: members.map((m) => ({
      id: m.id,
      nickname: m.nickname,
      avatar: m.avatar,
      isCreator: m.id === row.creator_id,
      isMe: m.id === memberId,
      joinedAt: isoTime(m.joined_at),
      days: days.get(m.id) ?? [],
    })),
    challenge: row.challenge_kind ? challengeProgress(db, row.id, row.challenge_kind, now) : null,
  };
}

export function circleRoutes() {
  return [
    {
      method: 'POST',
      path: '/circles',
      auth: 'member',
      async handler({ ctx, member, body }) {
        object(body, ['name']);
        const name = label(body.name, CIRCLE_NAME_MAX, 'name');
        const { db } = ctx;
        const row = transaction(db, () => {
          if (circleCount(db, member.id) >= MAX_CIRCLES_PER_MEMBER) {
            throw conflict(`You can be in at most ${MAX_CIRCLES_PER_MEMBER} circles`);
          }
          const id = randomUUID();
          const now = ctx.now();
          db.prepare('INSERT INTO circles (id, name, creator_id, invite_code, created_at) VALUES (?, ?, ?, ?, ?)').run(
            id,
            name,
            member.id,
            uniqueCode(db),
            now,
          );
          db.prepare('INSERT INTO circle_members (circle_id, member_id, joined_at) VALUES (?, ?, ?)').run(id, member.id, now);
          return db.prepare('SELECT * FROM circles WHERE id = ?').get(id);
        });
        return { status: 201, body: detail(ctx, row, member.id) };
      },
    },
    {
      method: 'POST',
      path: '/circles/join',
      auth: 'member',
      bucket: 'join',
      async handler({ ctx, member, body }) {
        object(body, ['code']);
        const code = normalizeCode(body.code);
        if (!code) throw badRequest(`code must be ${CODE_LENGTH} characters`);
        const { db } = ctx;
        const row = transaction(db, () => {
          const circle = db.prepare('SELECT * FROM circles WHERE invite_code = ?').get(code);
          if (!circle) throw notFound('No circle with that code');
          const already = db
            .prepare('SELECT 1 FROM circle_members WHERE circle_id = ? AND member_id = ?')
            .get(circle.id, member.id);
          if (already) return circle;
          if (memberCount(db, circle.id) >= MAX_MEMBERS) throw conflict(`This circle already has ${MAX_MEMBERS} members`);
          if (circleCount(db, member.id) >= MAX_CIRCLES_PER_MEMBER) {
            throw conflict(`You can be in at most ${MAX_CIRCLES_PER_MEMBER} circles`);
          }
          db.prepare('INSERT INTO circle_members (circle_id, member_id, joined_at) VALUES (?, ?, ?)').run(
            circle.id,
            member.id,
            ctx.now(),
          );
          return circle;
        });
        return { status: 200, body: detail(ctx, row, member.id) };
      },
    },
    {
      method: 'GET',
      path: '/circles',
      auth: 'member',
      async handler({ ctx, member }) {
        const rows = ctx.db
          .prepare(
            `SELECT c.* FROM circles c JOIN circle_members cm ON cm.circle_id = c.id
              WHERE cm.member_id = ? ORDER BY cm.joined_at, c.id`,
          )
          .all(member.id);
        return { status: 200, body: { circles: rows.map((r) => summary(ctx.db, r, member.id)) } };
      },
    },
    {
      method: 'GET',
      path: '/circles/:id',
      auth: 'member',
      async handler({ ctx, member, params }) {
        const row = circleFor(ctx.db, uuid(params.id, 'circle id'), member.id);
        return { status: 200, body: detail(ctx, row, member.id) };
      },
    },
    {
      method: 'POST',
      path: '/circles/:id/leave',
      auth: 'member',
      async handler({ ctx, member, params }) {
        const id = uuid(params.id, 'circle id');
        transaction(ctx.db, () => {
          circleFor(ctx.db, id, member.id);
          detachMember(ctx.db, id, member.id);
        });
        return { status: 204 };
      },
    },
    {
      method: 'POST',
      path: '/circles/:id/rotate-code',
      auth: 'member',
      async handler({ ctx, member, params }) {
        const { db } = ctx;
        const row = transaction(db, () => {
          const circle = circleFor(db, uuid(params.id, 'circle id'), member.id);
          requireCreator(circle, member.id);
          db.prepare('UPDATE circles SET invite_code = ? WHERE id = ?').run(uniqueCode(db), circle.id);
          return db.prepare('SELECT * FROM circles WHERE id = ?').get(circle.id);
        });
        return { status: 200, body: summary(db, row, member.id) };
      },
    },
    {
      method: 'DELETE',
      path: '/circles/:id/members/:memberId',
      auth: 'member',
      async handler({ ctx, member, params }) {
        const { db } = ctx;
        const circleId = uuid(params.id, 'circle id');
        const target = uuid(params.memberId, 'member id');
        transaction(db, () => {
          const circle = circleFor(db, circleId, member.id);
          requireCreator(circle, member.id);
          if (target === member.id) throw badRequest('Use leave to remove yourself');
          const inCircle = db
            .prepare('SELECT 1 FROM circle_members WHERE circle_id = ? AND member_id = ?')
            .get(circleId, target);
          if (!inCircle) throw notFound('Member not in this circle');
          detachMember(db, circleId, target);
        });
        return { status: 204 };
      },
    },
    {
      method: 'PUT',
      path: '/circles/:id/challenge',
      auth: 'member',
      async handler({ ctx, member, params, body }) {
        object(body, ['kind']);
        if (!('kind' in body)) throw badRequest('kind is required (null clears the challenge)');
        const kind = body.kind;
        if (kind !== null && !CHALLENGE_KINDS.includes(kind)) {
          throw badRequest(`kind must be null or one of: ${CHALLENGE_KINDS.join(', ')}`);
        }
        const { db } = ctx;
        const row = transaction(db, () => {
          const circle = circleFor(db, uuid(params.id, 'circle id'), member.id);
          requireCreator(circle, member.id);
          db.prepare('UPDATE circles SET challenge_kind = ? WHERE id = ?').run(kind, circle.id);
          return db.prepare('SELECT * FROM circles WHERE id = ?').get(circle.id);
        });
        return { status: 200, body: detail(ctx, row, member.id) };
      },
    },
  ];
}

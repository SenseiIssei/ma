import { randomUUID } from 'node:crypto';
import { transaction } from './db.js';
import { badRequest, conflict, isoTime } from './http.js';
import { hashSecret, isSecret } from './auth.js';
import { detachMember } from './circles.js';
import { label, object, oneOf, uuid } from './validate.js';

export const NICKNAME_MAX = 24;

// SF Symbol names the app can draw. A fixed list, so an avatar can never
// carry a message or point at an image somewhere else.
export const AVATARS = [
  'leaf', 'moon.stars', 'sun.max', 'flame', 'drop', 'mountain.2',
  'tree', 'cloud', 'sparkles', 'bird', 'fish', 'tortoise',
  'hare', 'cat', 'dog', 'pawprint', 'star', 'heart',
  'bolt', 'snowflake', 'wind', 'book', 'music.note', 'cup.and.saucer',
];

function profile(row) {
  return { id: row.id, nickname: row.nickname, avatar: row.avatar, createdAt: isoTime(row.created_at) };
}

export function memberRoutes() {
  return [
    {
      method: 'POST',
      path: '/members',
      auth: 'none',
      bucket: 'signup',
      async handler({ ctx, body }) {
        object(body, ['id', 'secret', 'nickname', 'avatar']);
        // The device may bring its own UUID so it can store id and secret in
        // the Keychain before the network call; otherwise the server picks one.
        const id = body.id === undefined ? randomUUID() : uuid(body.id, 'id');
        if (!isSecret(body.secret)) throw badRequest('secret must be 64 lowercase hex characters (32 random bytes)');
        const nickname = label(body.nickname, NICKNAME_MAX, 'nickname');
        const avatar = body.avatar === undefined ? AVATARS[0] : oneOf(body.avatar, AVATARS, 'avatar');
        const { db } = ctx;
        const row = transaction(db, () => {
          if (db.prepare('SELECT 1 FROM members WHERE id = ?').get(id)) throw conflict('This id is taken');
          db.prepare('INSERT INTO members (id, secret_hash, nickname, avatar, created_at) VALUES (?, ?, ?, ?, ?)').run(
            id,
            hashSecret(body.secret),
            nickname,
            avatar,
            ctx.now(),
          );
          return db.prepare('SELECT * FROM members WHERE id = ?').get(id);
        });
        return { status: 201, body: profile(row) };
      },
    },
    {
      method: 'GET',
      path: '/me',
      auth: 'member',
      async handler({ member }) {
        return { status: 200, body: profile(member) };
      },
    },
    {
      method: 'PATCH',
      path: '/me',
      auth: 'member',
      async handler({ ctx, member, body }) {
        object(body, ['nickname', 'avatar']);
        const nickname = body.nickname === undefined ? member.nickname : label(body.nickname, NICKNAME_MAX, 'nickname');
        const avatar = body.avatar === undefined ? member.avatar : oneOf(body.avatar, AVATARS, 'avatar');
        ctx.db.prepare('UPDATE members SET nickname = ?, avatar = ? WHERE id = ?').run(nickname, avatar, member.id);
        return { status: 200, body: profile({ ...member, nickname, avatar }) };
      },
    },
    {
      method: 'DELETE',
      path: '/me',
      auth: 'member',
      async handler({ ctx, member }) {
        // Everything goes in one transaction: circles handed over or removed,
        // memberships, numbers, and the member row itself.
        const { db } = ctx;
        transaction(db, () => {
          const circles = db.prepare('SELECT circle_id FROM circle_members WHERE member_id = ?').all(member.id);
          for (const c of circles) detachMember(db, c.circle_id, member.id);
          db.prepare('DELETE FROM stats WHERE member_id = ?').run(member.id);
          db.prepare('DELETE FROM members WHERE id = ?').run(member.id);
        });
        return { status: 204 };
      },
    },
  ];
}

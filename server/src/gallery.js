import { randomUUID } from 'node:crypto';
import { checkAdmin } from './auth.js';
import { badRequest, HttpError, isoTime, notFound } from './http.js';
import { integer, isObject, label, object, uuid } from './validate.js';

// Community decks wait here until someone reviews them by hand. Nothing is
// ever published automatically, and no submitter identity is stored.

export const GALLERY_MAX_BYTES = 200 * 1024;
export const MAX_PENDING = 1000;
const CATEGORIES = ['languages', 'knowledge', 'mind', 'tech', 'life'];
const DECK_KEYS = ['id', 'title', 'subtitle', 'symbol', 'language', 'cards', 'isBuiltIn', 'locale', 'category'];
const CARD_KEYS = ['id', 'prompt', 'answer', 'accept', 'distractors', 'example', 'note'];
const ID_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$/;

function optionalId(value, what) {
  if (value === undefined) return undefined;
  if (typeof value !== 'string' || !ID_RE.test(value)) throw badRequest(`${what} must be letters, digits, dot, dash or underscore`);
  return value;
}

function text(value, max, what) {
  // Card text may be long and multi-line, unlike a nickname.
  if (typeof value !== 'string') throw badRequest(`${what} must be a string`);
  const v = value.trim();
  if (v.length === 0) throw badRequest(`${what} must not be empty`);
  if ([...v].length > max) throw badRequest(`${what} must be at most ${max} characters`);
  return v;
}

function stringList(value, maxItems, maxLen, what) {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > maxItems) throw badRequest(`${what} must be a list of at most ${maxItems}`);
  return value.map((v, i) => text(v, maxLen, `${what}[${i}]`));
}

/** Mirrors the app's Deck/Card Codable shape and the bundled deck rules. */
export function validateDeck(deck) {
  object(deck, DECK_KEYS, 'deck');
  const out = {
    id: optionalId(deck.id, 'deck id'),
    title: label(deck.title, 60, 'title'),
    subtitle: deck.subtitle === undefined || deck.subtitle === '' ? '' : label(deck.subtitle, 60, 'subtitle'),
    symbol: deck.symbol === undefined ? undefined : label(deck.symbol, 2, 'symbol'),
  };
  if (deck.language !== undefined && (typeof deck.language !== 'string' || !/^[a-z]{2,3}$/.test(deck.language))) {
    throw badRequest('language must be a language code like "ja"');
  }
  if (deck.locale !== undefined && deck.locale !== null && !['en', 'de'].includes(deck.locale)) {
    throw badRequest('locale must be "en" or "de"');
  }
  if (deck.category !== undefined && deck.category !== null && !CATEGORIES.includes(deck.category)) {
    throw badRequest(`category must be one of: ${CATEGORIES.join(', ')}`);
  }
  if (deck.isBuiltIn !== undefined && typeof deck.isBuiltIn !== 'boolean') throw badRequest('isBuiltIn must be a boolean');
  if (!Array.isArray(deck.cards) || deck.cards.length < 5 || deck.cards.length > 500) {
    throw badRequest('cards must be a list of 5 to 500 cards');
  }
  const seen = new Set();
  deck.cards.forEach((card, i) => {
    const where = `cards[${i}]`;
    if (!isObject(card)) throw badRequest(`${where} must be an object`);
    object(card, CARD_KEYS, where);
    const id = optionalId(card.id, `${where}.id`);
    if (id !== undefined) {
      if (seen.has(id)) throw badRequest(`${where}.id is a duplicate`);
      seen.add(id);
    }
    text(card.prompt, 300, `${where}.prompt`);
    const answer = text(card.answer, 80, `${where}.answer`);
    stringList(card.accept, 10, 80, `${where}.accept`);
    const distractors = stringList(card.distractors, 3, 80, `${where}.distractors`);
    if (distractors.length !== 0 && distractors.length !== 3) throw badRequest(`${where}.distractors must have 0 or 3 entries`);
    if (distractors.some((d) => d.toLowerCase() === answer.toLowerCase())) {
      throw badRequest(`${where}.distractors must not contain the answer`);
    }
    if (card.example !== undefined && card.example !== null) {
      const example = text(card.example, 300, `${where}.example`);
      if (!example.includes(answer)) throw badRequest(`${where}.example must contain the answer verbatim`);
    }
    if (card.note !== undefined && card.note !== null) text(card.note, 600, `${where}.note`);
  });
  return { title: out.title, cardCount: deck.cards.length };
}

export function galleryRoutes() {
  return [
    {
      method: 'POST',
      path: '/gallery/submissions',
      auth: 'none',
      bucket: 'gallery',
      bodyLimit: GALLERY_MAX_BYTES,
      async handler({ ctx, body }) {
        const { title, cardCount } = validateDeck(body);
        const pending = Number(ctx.db.prepare("SELECT COUNT(*) AS n FROM gallery_submissions WHERE status = 'pending'").get().n);
        // A full queue means nobody is reviewing; stop growing the disk.
        if (pending >= MAX_PENDING) throw new HttpError(503, 'queue_full', 'The review queue is full, please try again later');
        const id = randomUUID();
        ctx.db
          .prepare('INSERT INTO gallery_submissions (id, deck_json, title, card_count, created_at) VALUES (?, ?, ?, ?, ?)')
          .run(id, JSON.stringify(body), title, cardCount, ctx.now());
        return { status: 201, body: { id, status: 'pending' } };
      },
    },
    {
      method: 'GET',
      path: '/gallery/submissions',
      auth: 'none',
      async handler({ ctx, req, query }) {
        checkAdmin(req, ctx.config.adminToken);
        const status = query.get('status') ?? 'pending';
        if (!['pending', 'accepted', 'rejected', 'all'].includes(status)) throw badRequest('status must be pending, accepted, rejected or all');
        const limit = query.has('limit') ? integer(Number(query.get('limit')), 1, 200, 'limit') : 50;
        const sql =
          'SELECT id, deck_json, title, card_count, status, created_at FROM gallery_submissions' +
          (status === 'all' ? '' : ' WHERE status = ?') +
          ' ORDER BY created_at LIMIT ?';
        const args = status === 'all' ? [limit] : [status, limit];
        const rows = ctx.db.prepare(sql).all(...args);
        return {
          status: 200,
          body: {
            submissions: rows.map((r) => ({
              id: r.id,
              title: r.title,
              cardCount: r.card_count,
              status: r.status,
              createdAt: isoTime(r.created_at),
              deck: JSON.parse(r.deck_json),
            })),
          },
        };
      },
    },
    {
      method: 'PATCH',
      path: '/gallery/submissions/:id',
      auth: 'none',
      async handler({ ctx, req, params, body }) {
        checkAdmin(req, ctx.config.adminToken);
        object(body, ['status']);
        if (!['pending', 'accepted', 'rejected'].includes(body.status)) throw badRequest('status must be pending, accepted or rejected');
        const res = ctx.db.prepare('UPDATE gallery_submissions SET status = ? WHERE id = ?').run(body.status, uuid(params.id));
        if (Number(res.changes) === 0) throw notFound('Submission not found');
        return { status: 200, body: { id: params.id.toLowerCase(), status: body.status } };
      },
    },
    {
      method: 'DELETE',
      path: '/gallery/submissions/:id',
      auth: 'none',
      async handler({ ctx, req, params }) {
        checkAdmin(req, ctx.config.adminToken);
        const res = ctx.db.prepare('DELETE FROM gallery_submissions WHERE id = ?').run(uuid(params.id));
        if (Number(res.changes) === 0) throw notFound('Submission not found');
        return { status: 204 };
      },
    },
  ];
}

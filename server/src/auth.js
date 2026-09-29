import { createHash, timingSafeEqual } from 'node:crypto';
import { HttpError } from './http.js';
import { isUuid } from './validate.js';

// A member proves who they are with "Bearer <memberId>.<secret>". The secret
// is 32 random bytes from the device, so a plain SHA-256 is enough: there is
// nothing to brute force, unlike a human password that needs a slow hash.

const SECRET_RE = /^[0-9a-f]{64}$/;

export function isSecret(value) {
  return typeof value === 'string' && SECRET_RE.test(value);
}

export function hashSecret(secret) {
  return createHash('sha256').update(secret, 'utf8').digest('hex');
}

function sameHex(a, b) {
  const x = Buffer.from(a, 'hex');
  const y = Buffer.from(b, 'hex');
  return x.length === y.length && timingSafeEqual(x, y);
}

const unauthorized = () =>
  new HttpError(401, 'unauthorized', 'Missing or invalid credentials', { 'WWW-Authenticate': 'Bearer' });

/** Parses the header without touching the database. */
export function parseBearer(header) {
  if (typeof header !== 'string' || !header.startsWith('Bearer ')) return null;
  const token = header.slice(7).trim();
  const dot = token.indexOf('.');
  if (dot < 0) return null;
  const id = token.slice(0, dot).toLowerCase();
  const secret = token.slice(dot + 1).toLowerCase();
  if (!isUuid(id) || !isSecret(secret)) return null;
  return { id, secret };
}

export function makeAuthenticator(db) {
  const find = db.prepare('SELECT id, secret_hash, nickname, avatar, created_at FROM members WHERE id = ?');
  return function authenticate(req) {
    const creds = parseBearer(req.headers.authorization);
    if (!creds) throw unauthorized();
    const row = find.get(creds.id);
    // Hash even when the member is unknown so timing does not reveal which
    // ids exist.
    const hash = hashSecret(creds.secret);
    if (!row || !sameHex(hash, row.secret_hash)) throw unauthorized();
    return row;
  };
}

/** Admin endpoints are off unless ADMIN_TOKEN is set. */
export function checkAdmin(req, adminToken) {
  if (!adminToken) throw new HttpError(404, 'not_found', 'Not found');
  const header = req.headers.authorization;
  const given = typeof header === 'string' && header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  const a = createHash('sha256').update(given).digest();
  const b = createHash('sha256').update(adminToken).digest();
  if (!timingSafeEqual(a, b)) throw unauthorized();
}

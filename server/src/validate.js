import { badRequest } from './http.js';

// Validation lives in one place so every route rejects the same things the
// same way. Unknown keys are refused, not ignored: the privacy promise is
// "only these numbers", and a silent extra field would quietly break it.

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
// Control, format (bidi overrides, zero width) and line separator characters
// would let a nickname spoof layout on other members' screens.
const INVISIBLE_RE = /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u;

export function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export function object(value, allowed, what = 'Body') {
  if (!isObject(value)) throw badRequest(`${what} must be a JSON object`);
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) throw badRequest(`${what}: unknown field "${key}"`);
  }
  return value;
}

export function uuid(value, what = 'id') {
  if (typeof value !== 'string') throw badRequest(`${what} must be a UUID`);
  const v = value.toLowerCase();
  if (!UUID_RE.test(v)) throw badRequest(`${what} must be a UUID`);
  return v;
}

export function isUuid(value) {
  return typeof value === 'string' && UUID_RE.test(value.toLowerCase());
}

/** A short display text: trimmed, NFC, single spaces, no invisible characters. */
export function label(value, max, what) {
  if (typeof value !== 'string') throw badRequest(`${what} must be a string`);
  const v = value.normalize('NFC').replace(/\s+/g, ' ').trim();
  const length = [...v].length;
  if (length === 0) throw badRequest(`${what} must not be empty`);
  if (length > max) throw badRequest(`${what} must be at most ${max} characters`);
  if (INVISIBLE_RE.test(v)) throw badRequest(`${what} contains invisible characters`);
  return v;
}

export function integer(value, min, max, what) {
  if (!Number.isInteger(value) || value < min || value > max) {
    throw badRequest(`${what} must be a whole number from ${min} to ${max}`);
  }
  return value;
}

/** A real calendar date as YYYY-MM-DD. Returns the UTC midnight in ms. */
export function calendarDate(value, what = 'date') {
  if (typeof value !== 'string') throw badRequest(`${what} must be YYYY-MM-DD`);
  const m = DATE_RE.exec(value);
  if (!m) throw badRequest(`${what} must be YYYY-MM-DD`);
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const ms = Date.UTC(y, mo - 1, d);
  const back = new Date(ms);
  if (back.getUTCFullYear() !== y || back.getUTCMonth() !== mo - 1 || back.getUTCDate() !== d) {
    throw badRequest(`${what} is not a real date`);
  }
  return ms;
}

export function dayString(ms) {
  return new Date(ms).toISOString().slice(0, 10);
}

export function oneOf(value, list, what) {
  if (!list.includes(value)) throw badRequest(`${what} must be one of: ${list.join(', ')}`);
  return value;
}

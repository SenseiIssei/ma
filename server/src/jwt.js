import { createPublicKey, verify } from 'node:crypto';

// Verifies RS256 ID tokens (Google today) against the issuer's published
// keys. Just enough JWT for one job, so the service keeps its zero
// dependencies.

const KEY_CACHE_MS = 6 * 3_600_000;
const CLOCK_SKEW_SECONDS = 120;

function base64UrlJson(part) {
  return JSON.parse(Buffer.from(part, 'base64url').toString('utf8'));
}

export function createKeySet(jwksUrl, fetchImpl = fetch) {
  let cache = { at: 0, keys: new Map() };
  async function load() {
    const response = await fetchImpl(jwksUrl);
    if (!response.ok) throw new Error(`keys answered ${response.status}`);
    const body = await response.json();
    const keys = new Map();
    for (const jwk of body.keys ?? []) {
      if (jwk.kty === 'RSA' && jwk.kid) keys.set(jwk.kid, createPublicKey({ key: jwk, format: 'jwk' }));
    }
    cache = { at: Date.now(), keys };
  }
  return async function keyFor(keyId) {
    if (Date.now() - cache.at > KEY_CACHE_MS || !cache.keys.has(keyId)) await load();
    return cache.keys.get(keyId) ?? null;
  };
}

/**
 * Returns the payload when signature, issuer, audience and expiry hold,
 * otherwise null. `nowSeconds` is injectable for tests.
 */
export async function verifyIdToken(token, { keyFor, issuers, audiences, nowSeconds = Math.floor(Date.now() / 1000) }) {
  if (typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  let header;
  let payload;
  try {
    header = base64UrlJson(parts[0]);
    payload = base64UrlJson(parts[1]);
  } catch {
    return null;
  }
  if (header.alg !== 'RS256' || typeof header.kid !== 'string') return null;
  const key = await keyFor(header.kid);
  if (!key) return null;
  const signed = Buffer.from(`${parts[0]}.${parts[1]}`);
  const signature = Buffer.from(parts[2], 'base64url');
  if (!verify('RSA-SHA256', signed, key, signature)) return null;
  if (!issuers.includes(payload.iss)) return null;
  const audience = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!audience.some((value) => audiences.includes(value))) return null;
  if (typeof payload.exp !== 'number' || payload.exp + CLOCK_SKEW_SECONDS < nowSeconds) return null;
  if (typeof payload.iat === 'number' && payload.iat - CLOCK_SKEW_SECONDS > nowSeconds) return null;
  return payload;
}

export const GOOGLE_ISSUERS = ['https://accounts.google.com', 'accounts.google.com'];
export const GOOGLE_KEYS_URL = 'https://www.googleapis.com/oauth2/v3/certs';

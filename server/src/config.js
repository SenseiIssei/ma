// Every knob comes from the environment, so the same image runs in tests,
// on a laptop and on the VPS without code changes.

function int(name, fallback, env) {
  const raw = env[name];
  if (raw === undefined || raw === '') return fallback;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 0) throw new Error(`${name} must be a non-negative integer`);
  return n;
}

function basePath(raw) {
  // Normalise to "/x/y" without a trailing slash; "" means mounted at root.
  let p = (raw ?? '/ma/api').trim();
  if (p === '' || p === '/') return '';
  if (!p.startsWith('/')) p = '/' + p;
  return p.replace(/\/+$/, '');
}

export function loadConfig(env = process.env) {
  return {
    host: env.HOST || '0.0.0.0',
    port: int('PORT', 8095, env),
    basePath: basePath(env.BASE_PATH),
    dataDir: env.DATA_DIR || '/data',
    // Empty means the admin endpoints are switched off entirely.
    adminToken: env.ADMIN_TOKEN || '',
    // Behind nginx the socket address is always 127.0.0.1, so the real
    // client address has to come from X-Real-IP. Off when exposed directly.
    trustProxy: (env.TRUST_PROXY ?? '1') !== '0',
    // Old numbers are useless for a 7 day view and a weekly challenge, and
    // data we do not keep cannot leak.
    statsRetentionDays: int('STATS_RETENTION_DAYS', 30, env),
    rate: {
      ipCapacity: int('RATE_IP_CAPACITY', 120, env),
      ipPerMinute: int('RATE_IP_PER_MINUTE', 120, env),
      memberCapacity: int('RATE_MEMBER_CAPACITY', 60, env),
      memberPerMinute: int('RATE_MEMBER_PER_MINUTE', 60, env),
      // Creating identities and guessing invite codes get their own, much
      // tighter buckets, because those are the two things worth abusing.
      signupCapacity: int('RATE_SIGNUP_CAPACITY', 5, env),
      signupPerHour: int('RATE_SIGNUP_PER_HOUR', 10, env),
      joinCapacity: int('RATE_JOIN_CAPACITY', 10, env),
      joinPerHour: int('RATE_JOIN_PER_HOUR', 30, env),
      galleryCapacity: int('RATE_GALLERY_CAPACITY', 5, env),
      galleryPerHour: int('RATE_GALLERY_PER_HOUR', 5, env),
    },
  };
}

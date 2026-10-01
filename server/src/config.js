// Every knob comes from the environment, so the same image runs in tests,
// on a laptop and on the VPS without code changes.

function int(name, fallback, env) {
  const raw = env[name];
  if (raw === undefined || raw === '') return fallback;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 0) throw new Error(`${name} must be a non-negative integer`);
  return n;
}

function list(raw) {
  return (raw ?? '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
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
    // Links in emails and redirect targets point here.
    publicOrigin: (env.PUBLIC_ORIGIN || 'https://senseiissei.dev').replace(/\/+$/, ''),
    // Accounts with these verified addresses get the owner features
    // (daily lessons from senseiissei.dev, personal reminders).
    ownerEmails: list(env.OWNER_EMAILS).map((email) => email.toLowerCase()),
    // OAuth client ids whose Google ID tokens are accepted (iOS, web).
    googleClientIds: list(env.GOOGLE_CLIENT_IDS),
    mail: {
      host: env.SMTP_HOST || '',
      port: int('SMTP_PORT', 587, env),
      // "true" means TLS from the first byte (465); otherwise STARTTLS.
      secure: (env.SMTP_SECURE ?? '').toLowerCase() === 'true',
      user: env.SMTP_USER || '',
      pass: env.SMTP_PASS || '',
      from: env.EMAIL_FROM || '',
    },
    // The compile sandbox for the daily lessons (server/runner), reachable
    // only on the internal Docker network.
    runner: { url: (env.RUNNER_URL || '').replace(/\/+$/, ''), token: env.RUNNER_TOKEN || '' },
    telegram: { botToken: env.TELEGRAM_BOT_TOKEN || '', botName: env.TELEGRAM_BOT_NAME || '' },
    discord: {
      botToken: env.DISCORD_BOT_TOKEN || '',
      clientId: env.DISCORD_CLIENT_ID || '',
      clientSecret: env.DISCORD_CLIENT_SECRET || '',
    },
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
      // Password guessing and mail sending per address.
      authCapacity: int('RATE_AUTH_CAPACITY', 10, env),
      authPerHour: int('RATE_AUTH_PER_HOUR', 30, env),
    },
  };
}

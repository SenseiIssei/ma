import { createHash, randomBytes, scrypt as scryptCallback, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import { transaction } from './db.js';
import { badRequest, conflict, HttpError, isoTime } from './http.js';
import { createKeySet, GOOGLE_ISSUERS, GOOGLE_KEYS_URL, verifyIdToken } from './jwt.js';
import { mailConfigured, sendMail } from './mailer.js';
import { object } from './validate.js';

// Optional accounts for the Ma app: email and password with a confirmation
// mail, or Google. Ma works without one; an account only unlocks what the
// server grants it. Today that is the owner's features (the daily lessons
// from senseiissei.dev and personal reminders) for the addresses in
// OWNER_EMAILS.

const scrypt = promisify(scryptCallback);

export const ACCOUNT_SCHEMA = `
CREATE TABLE IF NOT EXISTS accounts (
  id                TEXT PRIMARY KEY,
  email             TEXT NOT NULL UNIQUE,
  password_hash     TEXT,
  email_verified_at INTEGER,
  google_sub        TEXT UNIQUE,
  created_at        INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS account_sessions (
  token_hash   TEXT PRIMARY KEY,
  account_id   TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  created_at   INTEGER NOT NULL,
  last_used_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS account_sessions_by_account ON account_sessions(account_id);
CREATE TABLE IF NOT EXISTS account_mail_tokens (
  token_hash TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  purpose    TEXT NOT NULL CHECK (purpose IN ('verify', 'reset')),
  expires_at INTEGER NOT NULL
);
`;

export const SESSION_IDLE_MS = 180 * 86_400_000;
const VERIFY_LIFETIME_MS = 48 * 3_600_000;
const RESET_LIFETIME_MS = 60 * 60_000;
const SESSION_PATTERN = /^mas_[0-9a-f]{64}$/;
const EMAIL_PATTERN = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,63}$/;
const PASSWORD_MIN = 8;
const PASSWORD_MAX = 200;

const sha256 = (text) => createHash('sha256').update(text, 'utf8').digest('hex');
const newToken = (prefix) => `${prefix}${randomBytes(32).toString('hex')}`;

export function normalizeEmail(value) {
  if (typeof value !== 'string') throw badRequest('email is missing');
  const email = value.trim().toLowerCase();
  if (email.length > 254 || !EMAIL_PATTERN.test(email)) throw badRequest('That does not look like an email address');
  return email;
}

function checkPassword(value) {
  if (typeof value !== 'string' || value.length < PASSWORD_MIN) {
    throw badRequest(`The password needs at least ${PASSWORD_MIN} characters`);
  }
  if (value.length > PASSWORD_MAX) throw badRequest('The password is too long');
  return value;
}

export async function hashPassword(password) {
  const salt = randomBytes(16);
  const hash = await scrypt(password, salt, 64, { N: 16384, r: 8, p: 1, maxmem: 64 * 1024 * 1024 });
  return `scrypt$16384$8$1$${salt.toString('base64')}$${hash.toString('base64')}`;
}

export async function verifyPassword(password, stored) {
  const parts = typeof stored === 'string' ? stored.split('$') : [];
  if (parts.length !== 6 || parts[0] !== 'scrypt') return false;
  const [, n, r, p, saltText, hashText] = parts;
  const expected = Buffer.from(hashText, 'base64');
  const actual = await scrypt(password, Buffer.from(saltText, 'base64'), expected.length, {
    N: Number(n),
    r: Number(r),
    p: Number(p),
    maxmem: 64 * 1024 * 1024,
  });
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

// A fixed hash to compare against when the account is unknown, so a login
// takes as long for a missing address as for a wrong password.
let decoyHash = null;
async function decoy() {
  decoyHash ??= await hashPassword(randomBytes(12).toString('hex'));
  return decoyHash;
}

/** What an account may use, decided here and nowhere else. */
export function featuresOf(account, config) {
  const owner = Boolean(account.email_verified_at) && config.ownerEmails.includes(account.email);
  return owner ? ['daily', 'reminders'] : [];
}

function view(account, config) {
  return {
    id: account.id,
    email: account.email,
    verified: Boolean(account.email_verified_at),
    hasPassword: Boolean(account.password_hash),
    google: Boolean(account.google_sub),
    features: featuresOf(account, config),
    createdAt: isoTime(account.created_at),
  };
}

const unauthorized = () =>
  new HttpError(401, 'unauthorized', 'Please sign in again', { 'WWW-Authenticate': 'Bearer' });

export function readSessionToken(req) {
  const header = req.headers.authorization;
  const token = typeof header === 'string' && header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  return SESSION_PATTERN.test(token) ? token : null;
}

export function makeAccountAuthenticator(db, now) {
  const find = db.prepare(
    `SELECT a.*, s.token_hash, s.last_used_at AS session_used FROM account_sessions s
     JOIN accounts a ON a.id = s.account_id WHERE s.token_hash = ?`,
  );
  const touch = db.prepare('UPDATE account_sessions SET last_used_at = ? WHERE token_hash = ?');
  const drop = db.prepare('DELETE FROM account_sessions WHERE token_hash = ?');
  return function authenticateAccount(req) {
    const token = readSessionToken(req);
    if (!token) throw unauthorized();
    const hash = sha256(token);
    const row = find.get(hash);
    if (!row) throw unauthorized();
    if (now() - row.session_used > SESSION_IDLE_MS) {
      drop.run(hash);
      throw unauthorized();
    }
    touch.run(now(), hash);
    return row;
  };
}

function openSession(db, accountId, now) {
  const token = newToken('mas_');
  db.prepare('INSERT INTO account_sessions (token_hash, account_id, created_at, last_used_at) VALUES (?, ?, ?, ?)').run(
    sha256(token),
    accountId,
    now,
    now,
  );
  return token;
}

function issueMailToken(db, accountId, purpose, lifetime, now) {
  db.prepare('DELETE FROM account_mail_tokens WHERE account_id = ? AND purpose = ?').run(accountId, purpose);
  const token = newToken('');
  db.prepare('INSERT INTO account_mail_tokens (token_hash, account_id, purpose, expires_at) VALUES (?, ?, ?, ?)').run(
    sha256(token),
    accountId,
    purpose,
    now + lifetime,
  );
  return token;
}

function takeMailToken(db, token, purpose, now) {
  if (typeof token !== 'string' || !/^[0-9a-f]{64}$/.test(token)) return null;
  const hash = sha256(token);
  const row = db.prepare('SELECT account_id, expires_at FROM account_mail_tokens WHERE token_hash = ? AND purpose = ?').get(hash, purpose);
  if (!row || row.expires_at <= now) return null;
  db.prepare('DELETE FROM account_mail_tokens WHERE token_hash = ?').run(hash);
  return row.account_id;
}

// --- mails and pages --------------------------------------------------------

function language(value) {
  return value === 'de' ? 'de' : 'en';
}

function mailFor(kind, lang, link) {
  const de = lang === 'de';
  const texts = {
    verify: de
      ? { subject: 'Bestätige deine E-Mail für Ma', title: 'Fast geschafft', body: 'Tippe auf den Knopf, um deine Adresse für dein Ma-Konto zu bestätigen. Der Link gilt 48 Stunden.', button: 'E-Mail bestätigen', ignore: 'Du hast kein Konto angelegt? Dann ignoriere diese Mail einfach.' }
      : { subject: 'Confirm your email for Ma', title: 'Almost there', body: 'Tap the button to confirm the address of your Ma account. The link works for 48 hours.', button: 'Confirm email', ignore: 'Did not create an account? Simply ignore this mail.' },
    reset: de
      ? { subject: 'Neues Passwort für Ma', title: 'Passwort zurücksetzen', body: 'Tippe auf den Knopf und wähle ein neues Passwort. Der Link gilt eine Stunde.', button: 'Neues Passwort wählen', ignore: 'Du hast das nicht angefordert? Dann ignoriere diese Mail, dein Passwort bleibt, wie es ist.' }
      : { subject: 'A new password for Ma', title: 'Reset your password', body: 'Tap the button and choose a new password. The link works for one hour.', button: 'Choose a new password', ignore: 'Did not ask for this? Ignore this mail and your password stays as it is.' },
  }[kind];
  const text = `${texts.title}\n\n${texts.body}\n\n${link}\n\n${texts.ignore}\n`;
  const html = `<!doctype html><html><body style="margin:0;background:#0A0E22;font-family:-apple-system,Segoe UI,sans-serif;color:#EEF0FF">
<div style="max-width:480px;margin:0 auto;padding:40px 24px">
<div style="font-size:28px;font-weight:800;letter-spacing:-0.5px">Ma</div>
<h1 style="font-size:22px;margin:28px 0 12px">${texts.title}</h1>
<p style="color:#A9AED3;line-height:1.6;font-size:16px">${texts.body}</p>
<p style="margin:28px 0"><a href="${link}" style="background:#A3A1FF;color:#0A0E22;text-decoration:none;font-weight:700;padding:14px 22px;border-radius:14px;display:inline-block">${texts.button}</a></p>
<p style="color:#656C98;font-size:13px;line-height:1.6">${texts.ignore}</p>
</div></body></html>`;
  return { subject: texts.subject, text, html };
}

export function page(title, message, { lang = 'en', extra = '' } = {}) {
  const escape = (text) => String(text).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
  return `<!doctype html><html lang="${lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escape(title)} · Ma</title>
<style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0A0E22;color:#EEF0FF;font:16px/1.6 -apple-system,Segoe UI,sans-serif}
main{max-width:420px;padding:32px 24px}h1{font-size:26px;margin:0 0 12px}p{color:#A9AED3}
input{width:100%;box-sizing:border-box;padding:14px;border-radius:12px;border:1px solid #252D58;background:#141A36;color:#EEF0FF;font-size:16px;margin:8px 0}
button,a.button{display:inline-block;margin-top:12px;background:#A3A1FF;color:#0A0E22;border:0;border-radius:14px;padding:14px 22px;font-weight:700;font-size:16px;text-decoration:none;cursor:pointer}
.brand{font-weight:800;font-size:22px;margin-bottom:24px}.note{font-size:14px;color:#656C98}</style></head>
<body><main><div class="brand">Ma</div><h1>${escape(title)}</h1><p>${escape(message)}</p>${extra}</main></body></html>`;
}

// --- routes -----------------------------------------------------------------

export function accountRoutes({ config, fetchImpl = fetch } = {}) {
  const googleKeys = createKeySet(GOOGLE_KEYS_URL, fetchImpl);
  const apiBase = `${config.publicOrigin}${config.basePath}`;

  async function mailTo(account, kind, lang, token, log) {
    if (!mailConfigured(config.mail)) {
      log?.error?.('[accounts] mail is not configured, no mail sent');
      return false;
    }
    const path = kind === 'verify' ? 'auth/verify' : 'auth/reset';
    const link = `${apiBase}/${path}?token=${token}&lang=${lang}`;
    try {
      await sendMail(config.mail, { to: account.email, ...mailFor(kind, lang, link) });
      return true;
    } catch (error) {
      log?.error?.('[accounts] mail failed:', error?.message ?? error);
      return false;
    }
  }

  return [
    {
      method: 'POST',
      path: '/auth/register',
      auth: 'none',
      bucket: 'auth',
      async handler({ ctx, body }) {
        object(body, ['email', 'password', 'lang']);
        const email = normalizeEmail(body.email);
        const password = checkPassword(body.password);
        const passwordHash = await hashPassword(password);
        const { db } = ctx;
        const now = ctx.now();
        const id = randomBytes(16).toString('hex');
        const { account, session, verifyToken } = transaction(db, () => {
          if (db.prepare('SELECT 1 FROM accounts WHERE email = ?').get(email)) {
            throw conflict('There is already an account with this address. Sign in or reset the password.');
          }
          db.prepare('INSERT INTO accounts (id, email, password_hash, email_verified_at, google_sub, created_at) VALUES (?, ?, ?, NULL, NULL, ?)').run(
            id,
            email,
            passwordHash,
            now,
          );
          return {
            account: db.prepare('SELECT * FROM accounts WHERE id = ?').get(id),
            session: openSession(db, id, now),
            verifyToken: issueMailToken(db, id, 'verify', VERIFY_LIFETIME_MS, now),
          };
        });
        const mailSent = await mailTo(account, 'verify', language(body.lang), verifyToken, ctx.log);
        return { status: 201, body: { account: view(account, config), session, mailSent } };
      },
    },
    {
      method: 'POST',
      path: '/auth/login',
      auth: 'none',
      bucket: 'auth',
      async handler({ ctx, body }) {
        object(body, ['email', 'password']);
        const email = normalizeEmail(body.email);
        const password = typeof body.password === 'string' ? body.password : '';
        const account = ctx.db.prepare('SELECT * FROM accounts WHERE email = ?').get(email);
        const ok = await verifyPassword(password, account?.password_hash ?? (await decoy()));
        if (!account || !account.password_hash || !ok) {
          throw new HttpError(401, 'unauthorized', 'Email or password is wrong');
        }
        const session = openSession(ctx.db, account.id, ctx.now());
        return { status: 200, body: { account: view(account, config), session } };
      },
    },
    {
      method: 'POST',
      path: '/auth/google',
      auth: 'none',
      bucket: 'auth',
      async handler({ ctx, body }) {
        object(body, ['idToken']);
        if (config.googleClientIds.length === 0) throw new HttpError(404, 'not_found', 'Google sign-in is not set up');
        const claims = await verifyIdToken(body.idToken, {
          keyFor: googleKeys,
          issuers: GOOGLE_ISSUERS,
          audiences: config.googleClientIds,
          nowSeconds: Math.floor(ctx.now() / 1000),
        });
        if (!claims || typeof claims.sub !== 'string' || typeof claims.email !== 'string' || claims.email_verified !== true) {
          throw new HttpError(401, 'unauthorized', 'Google did not confirm this sign-in');
        }
        const email = normalizeEmail(claims.email);
        const { db } = ctx;
        const now = ctx.now();
        const account = transaction(db, () => {
          let row = db.prepare('SELECT * FROM accounts WHERE google_sub = ?').get(claims.sub);
          if (!row) {
            row = db.prepare('SELECT * FROM accounts WHERE email = ?').get(email);
            if (row) {
              // Google vouches for the address, so an email account with the
              // same address becomes the same account, now confirmed.
              db.prepare('UPDATE accounts SET google_sub = ?, email_verified_at = COALESCE(email_verified_at, ?) WHERE id = ?').run(
                claims.sub,
                now,
                row.id,
              );
            } else {
              const id = randomBytes(16).toString('hex');
              db.prepare('INSERT INTO accounts (id, email, password_hash, email_verified_at, google_sub, created_at) VALUES (?, ?, NULL, ?, ?, ?)').run(
                id,
                email,
                now,
                claims.sub,
                now,
              );
              row = { id };
            }
            row = db.prepare('SELECT * FROM accounts WHERE id = ?').get(row.id);
          }
          return row;
        });
        const session = openSession(db, account.id, now);
        return { status: 200, body: { account: view(account, config), session } };
      },
    },
    {
      method: 'GET',
      path: '/auth/verify',
      auth: 'none',
      bucket: 'auth',
      async handler({ ctx, query }) {
        const lang = language(query.get('lang'));
        const de = lang === 'de';
        const accountId = takeMailToken(ctx.db, query.get('token'), 'verify', ctx.now());
        if (!accountId) {
          return {
            status: 400,
            html: page(de ? 'Link abgelaufen' : 'Link expired', de ? 'Dieser Link ist abgelaufen oder wurde schon benutzt. In Ma kannst du eine neue Mail anfordern.' : 'This link has expired or was used already. You can ask Ma for a new mail.', { lang }),
          };
        }
        ctx.db.prepare('UPDATE accounts SET email_verified_at = COALESCE(email_verified_at, ?) WHERE id = ?').run(ctx.now(), accountId);
        return {
          status: 200,
          html: page(de ? 'E-Mail bestätigt' : 'Email confirmed', de ? 'Danke. Dein Ma-Konto ist bestätigt, du kannst zur App zurück.' : 'Thank you. Your Ma account is confirmed, you can go back to the app.', {
            lang,
            extra: `<a class="button" href="ma://account/verified">${de ? 'Ma öffnen' : 'Open Ma'}</a>`,
          }),
        };
      },
    },
    {
      method: 'POST',
      path: '/auth/resend',
      auth: 'account',
      bucket: 'auth',
      async handler({ ctx, account, body }) {
        object(body ?? {}, ['lang']);
        if (account.email_verified_at) return { status: 200, body: { mailSent: false, verified: true } };
        const token = issueMailToken(ctx.db, account.id, 'verify', VERIFY_LIFETIME_MS, ctx.now());
        const mailSent = await mailTo(account, 'verify', language(body?.lang), token, ctx.log);
        return { status: 200, body: { mailSent, verified: false } };
      },
    },
    {
      method: 'POST',
      path: '/auth/forgot',
      auth: 'none',
      bucket: 'auth',
      async handler({ ctx, body }) {
        object(body, ['email', 'lang']);
        const email = normalizeEmail(body.email);
        const account = ctx.db.prepare('SELECT * FROM accounts WHERE email = ?').get(email);
        // Same answer either way, so the form does not reveal who has an account.
        if (account) {
          const token = issueMailToken(ctx.db, account.id, 'reset', RESET_LIFETIME_MS, ctx.now());
          await mailTo(account, 'reset', language(body.lang), token, ctx.log);
        }
        return { status: 204 };
      },
    },
    {
      method: 'GET',
      path: '/auth/reset',
      auth: 'none',
      async handler({ query }) {
        const lang = language(query.get('lang'));
        const de = lang === 'de';
        const token = String(query.get('token') ?? '').replace(/[^0-9a-f]/g, '').slice(0, 64);
        const script = `<form id="f"><input id="p" type="password" autocomplete="new-password" minlength="${PASSWORD_MIN}" placeholder="${de ? 'Neues Passwort' : 'New password'}" required>
<button>${de ? 'Passwort speichern' : 'Save password'}</button></form><p id="m" class="note"></p>
<script>document.getElementById('f').addEventListener('submit',async e=>{e.preventDefault();const m=document.getElementById('m');
const r=await fetch('reset',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:'${token}',password:document.getElementById('p').value})});
m.textContent=r.ok?'${de ? 'Gespeichert. Melde dich in Ma mit dem neuen Passwort an.' : 'Saved. Sign in to Ma with the new password.'}':((await r.json().catch(()=>({}))).message||'Error');
if(r.ok)document.getElementById('f').remove();});</script>`;
        return {
          status: 200,
          html: page(de ? 'Neues Passwort' : 'New password', de ? `Mindestens ${PASSWORD_MIN} Zeichen.` : `At least ${PASSWORD_MIN} characters.`, { lang, extra: script }),
        };
      },
    },
    {
      method: 'POST',
      path: '/auth/reset',
      auth: 'none',
      bucket: 'auth',
      async handler({ ctx, body }) {
        object(body, ['token', 'password']);
        const password = checkPassword(body.password);
        const passwordHash = await hashPassword(password);
        const { db } = ctx;
        const accountId = transaction(db, () => {
          const id = takeMailToken(db, body.token, 'reset', ctx.now());
          if (!id) return null;
          // The mail reached its owner, which also confirms the address.
          db.prepare('UPDATE accounts SET password_hash = ?, email_verified_at = COALESCE(email_verified_at, ?) WHERE id = ?').run(
            passwordHash,
            ctx.now(),
            id,
          );
          db.prepare('DELETE FROM account_sessions WHERE account_id = ?').run(id);
          return id;
        });
        if (!accountId) throw badRequest('This link has expired. Ask Ma for a new one.');
        return { status: 204 };
      },
    },
    {
      method: 'GET',
      path: '/auth/me',
      auth: 'account',
      async handler({ account }) {
        return { status: 200, body: view(account, config) };
      },
    },
    {
      method: 'POST',
      path: '/auth/logout',
      auth: 'account',
      async handler({ ctx, account }) {
        ctx.db.prepare('DELETE FROM account_sessions WHERE token_hash = ?').run(account.token_hash);
        return { status: 204 };
      },
    },
    {
      method: 'DELETE',
      path: '/auth/me',
      auth: 'account',
      async handler({ ctx, account }) {
        ctx.db.prepare('DELETE FROM accounts WHERE id = ?').run(account.id);
        return { status: 204 };
      },
    },
  ];
}

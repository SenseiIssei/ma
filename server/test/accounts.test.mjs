import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import net from 'node:net';
import { after, before, describe, test } from 'node:test';
import { hashPassword, verifyPassword } from '../src/accounts.js';
import { startServer } from './helpers.mjs';

/** A tiny SMTP server that keeps every message it receives. */
async function fakeSmtp() {
  const messages = [];
  const server = net.createServer((socket) => {
    let data = false;
    let buffer = '';
    socket.write('220 fake ESMTP\r\n');
    socket.on('data', (chunk) => {
      buffer += chunk.toString('utf8');
      if (data) {
        const end = buffer.indexOf('\r\n.\r\n');
        if (end < 0) return;
        messages.push(buffer.slice(0, end));
        buffer = buffer.slice(end + 5);
        data = false;
        socket.write('250 queued\r\n');
      }
      let newline;
      while (!data && (newline = buffer.indexOf('\r\n')) >= 0) {
        const line = buffer.slice(0, newline);
        buffer = buffer.slice(newline + 2);
        if (/^EHLO/i.test(line)) socket.write('250-fake\r\n250 AUTH PLAIN\r\n');
        else if (/^AUTH/i.test(line)) socket.write('235 ok\r\n');
        else if (/^(MAIL|RCPT)/i.test(line)) socket.write('250 ok\r\n');
        else if (/^DATA/i.test(line)) {
          data = true;
          socket.write('354 go\r\n');
        } else if (/^QUIT/i.test(line)) socket.end('221 bye\r\n');
      }
    });
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  return { port: server.address().port, messages, close: () => new Promise((resolve) => server.close(resolve)) };
}

/** The link in a mail's plain text part. */
function linkIn(message) {
  const parts = message.split(/--ma-[0-9a-f]+/);
  const plain = parts.find((part) => part.includes('text/plain'));
  const body = plain.split('\r\n\r\n')[1].replace(/\r\n/g, '');
  return /https?:\/\/\S+/.exec(Buffer.from(body, 'base64').toString('utf8'))[0];
}

describe('passwords', () => {
  test('scrypt hashes verify and differ per salt', async () => {
    const first = await hashPassword('correct horse battery');
    const second = await hashPassword('correct horse battery');
    assert.notEqual(first, second);
    assert.ok(await verifyPassword('correct horse battery', first));
    assert.ok(!(await verifyPassword('wrong horse battery', first)));
    assert.ok(!(await verifyPassword('anything', 'garbage')));
  });
});

describe('accounts', () => {
  let api;
  let smtp;
  before(async () => {
    smtp = await fakeSmtp();
    api = await startServer({
      OWNER_EMAILS: 'jakob@example.com',
      SMTP_HOST: '127.0.0.1',
      SMTP_PORT: String(smtp.port),
      EMAIL_FROM: 'Ma <ma@example.com>',
      PUBLIC_ORIGIN: 'https://senseiissei.dev',
    });
  });
  after(async () => {
    await api.close();
    await smtp.close();
  });

  test('register sends a confirmation mail whose link confirms the address', async () => {
    const res = await api.request('POST', '/auth/register', { body: { email: 'Jakob@Example.com', password: 'correct horse battery', lang: 'de' } });
    assert.equal(res.status, 201);
    assert.equal(res.body.account.email, 'jakob@example.com');
    assert.equal(res.body.account.verified, false);
    assert.deepEqual(res.body.account.features, [], 'no owner features before confirming');
    assert.equal(res.body.mailSent, true);
    const mail = smtp.messages.at(-1);
    assert.match(mail, /Subject: =\?UTF-8\?B\?/);
    const link = new URL(linkIn(mail));
    assert.equal(link.origin + link.pathname, 'https://senseiissei.dev/ma/api/auth/verify');

    const page = await fetch(`${api.origin}${api.prefix}/auth/verify${link.search}`);
    assert.equal(page.status, 200);
    assert.match(await page.text(), /E-Mail bestätigt/);
    const again = await fetch(`${api.origin}${api.prefix}/auth/verify${link.search}`);
    assert.equal(again.status, 400, 'a link works once');

    const me = await api.request('GET', '/auth/me', { token: res.body.session });
    assert.equal(me.body.verified, true);
    assert.deepEqual(me.body.features, ['daily', 'reminders'], 'the owner address unlocks the owner features');
  });

  test('one address, one account; wrong passwords get one answer', async () => {
    const twice = await api.request('POST', '/auth/register', { body: { email: 'jakob@example.com', password: 'another password' } });
    assert.equal(twice.status, 409);
    const wrong = await api.request('POST', '/auth/login', { body: { email: 'jakob@example.com', password: 'nope nope nope' } });
    const unknown = await api.request('POST', '/auth/login', { body: { email: 'nobody@example.com', password: 'nope nope nope' } });
    assert.equal(wrong.status, 401);
    assert.equal(unknown.status, 401);
    assert.equal(wrong.body.message, unknown.body.message);
    const right = await api.request('POST', '/auth/login', { body: { email: 'jakob@example.com', password: 'correct horse battery' } });
    assert.equal(right.status, 200);
    assert.match(right.body.session, /^mas_[0-9a-f]{64}$/);
  });

  test('bad input is refused', async () => {
    const short = await api.request('POST', '/auth/register', { body: { email: 'short@example.com', password: 'short' } });
    assert.equal(short.status, 400);
    const noEmail = await api.request('POST', '/auth/register', { body: { email: 'not-an-email', password: 'long enough password' } });
    assert.equal(noEmail.status, 400);
    const extra = await api.request('POST', '/auth/login', { body: { email: 'a@example.com', password: 'x', admin: true } });
    assert.equal(extra.status, 400);
  });

  test('a stranger stays without owner features even when confirmed', async () => {
    const stranger = await api.newAccount('stranger@example.com');
    const me = await api.request('GET', '/auth/me', { token: stranger.session });
    assert.deepEqual(me.body.features, []);
    const notify = await api.request('GET', '/notify', { token: stranger.session });
    assert.equal(notify.status, 403);
  });

  test('forgot password answers the same for everyone and the reset link works once', async () => {
    const before = smtp.messages.length;
    const unknown = await api.request('POST', '/auth/forgot', { body: { email: 'ghost@example.com' } });
    assert.equal(unknown.status, 204);
    assert.equal(smtp.messages.length, before, 'no mail for an unknown address');
    const known = await api.request('POST', '/auth/forgot', { body: { email: 'jakob@example.com', lang: 'en' } });
    assert.equal(known.status, 204);
    const link = new URL(linkIn(smtp.messages.at(-1)));
    const form = await fetch(`${api.origin}${api.prefix}/auth/reset${link.search}`);
    assert.match(await form.text(), /New password/);
    const token = link.searchParams.get('token');
    const reset = await api.request('POST', '/auth/reset', { body: { token, password: 'a brand new password' } });
    assert.equal(reset.status, 204);
    const reuse = await api.request('POST', '/auth/reset', { body: { token, password: 'yet another password' } });
    assert.equal(reuse.status, 400);
    const oldPassword = await api.request('POST', '/auth/login', { body: { email: 'jakob@example.com', password: 'correct horse battery' } });
    assert.equal(oldPassword.status, 401);
    const newPassword = await api.request('POST', '/auth/login', { body: { email: 'jakob@example.com', password: 'a brand new password' } });
    assert.equal(newPassword.status, 200);
  });

  test('logout ends the session, deleting the account ends everything', async () => {
    const account = await api.newAccount('leaving@example.com');
    const out = await api.request('POST', '/auth/logout', { token: account.session });
    assert.equal(out.status, 204);
    assert.equal((await api.request('GET', '/auth/me', { token: account.session })).status, 401);
    const login = await api.request('POST', '/auth/login', { body: { email: 'leaving@example.com', password: account.password } });
    const gone = await api.request('DELETE', '/auth/me', { token: login.body.session });
    assert.equal(gone.status, 204);
    const again = await api.request('POST', '/auth/login', { body: { email: 'leaving@example.com', password: account.password } });
    assert.equal(again.status, 401);
  });

  test('sessions expire after half a year without use', async () => {
    const account = await api.newAccount('sleepy@example.com');
    api.clock.t += 181 * 86_400_000;
    assert.equal((await api.request('GET', '/auth/me', { token: account.session })).status, 401);
    api.clock.t -= 181 * 86_400_000;
  });
});

describe('google sign-in', () => {
  let api;
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const jwk = { ...publicKey.export({ format: 'jwk' }), kid: 'test-key', alg: 'RS256', use: 'sig' };

  function idToken(claims, key = privateKey) {
    const header = Buffer.from(JSON.stringify({ alg: 'RS256', kid: 'test-key', typ: 'JWT' })).toString('base64url');
    const payload = Buffer.from(JSON.stringify(claims)).toString('base64url');
    const signature = sign('RSA-SHA256', Buffer.from(`${header}.${payload}`), key).toString('base64url');
    return `${header}.${payload}.${signature}`;
  }

  before(async () => {
    api = await startServer({ OWNER_EMAILS: 'jakob@gmail.com', GOOGLE_CLIENT_IDS: 'ios-client.apps.googleusercontent.com' });
    api.fetchStub.handler = async (url) => {
      assert.equal(url, 'https://www.googleapis.com/oauth2/v3/certs');
      return new Response(JSON.stringify({ keys: [jwk] }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    };
  });
  after(() => api.close());

  const nowSeconds = () => Math.floor(api.clock.t / 1000);
  const claims = (extra = {}) => ({
    iss: 'https://accounts.google.com',
    aud: 'ios-client.apps.googleusercontent.com',
    sub: '1234567890',
    email: 'Jakob@gmail.com',
    email_verified: true,
    iat: nowSeconds(),
    exp: nowSeconds() + 3600,
    ...extra,
  });

  test('a valid Google token creates a confirmed owner account, the next one signs in', async () => {
    const first = await api.request('POST', '/auth/google', { body: { idToken: idToken(claims()) } });
    assert.equal(first.status, 200);
    assert.equal(first.body.account.email, 'jakob@gmail.com');
    assert.equal(first.body.account.verified, true);
    assert.deepEqual(first.body.account.features, ['daily', 'reminders']);
    const second = await api.request('POST', '/auth/google', { body: { idToken: idToken(claims()) } });
    assert.equal(second.body.account.id, first.body.account.id);
  });

  test('forged, foreign, expired or unconfirmed tokens are refused', async () => {
    const other = generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey;
    const cases = [
      idToken(claims(), other),
      idToken(claims({ aud: 'someone-else' })),
      idToken(claims({ iss: 'https://evil.example' })),
      idToken(claims({ exp: nowSeconds() - 3600 })),
      idToken(claims({ email_verified: false, sub: '999' })),
      'not.a.token',
    ];
    for (const token of cases) {
      const res = await api.request('POST', '/auth/google', { body: { idToken: token } });
      assert.equal(res.status, 401, token.slice(0, 20));
    }
  });

  test('an email account with the same address is joined, not duplicated', async () => {
    const byMail = await api.newAccount('both@example.com', { verified: false });
    const google = await api.request('POST', '/auth/google', { body: { idToken: idToken(claims({ sub: '42', email: 'both@example.com' })) } });
    assert.equal(google.body.account.id, byMail.id);
    assert.equal(google.body.account.verified, true, 'Google confirms the address');
  });
});

describe('reminder channels', () => {
  let api;
  let owner;
  before(async () => {
    api = await startServer({
      OWNER_EMAILS: 'jakob@example.com',
      TELEGRAM_BOT_TOKEN: '123:abc',
      TELEGRAM_BOT_NAME: 'MaRemindBot',
      DISCORD_BOT_TOKEN: 'discord-bot',
      DISCORD_CLIENT_ID: '555',
      DISCORD_CLIENT_SECRET: 'secret',
    });
    owner = await api.newAccount('jakob@example.com');
  });
  after(() => api.close());

  test('telegram links with one tap: the bot gets the code as /start', async () => {
    const link = await api.request('POST', '/notify/telegram/link', { token: owner.session });
    assert.equal(link.status, 201);
    const url = new URL(link.body.url);
    assert.equal(url.origin + url.pathname, 'https://t.me/MaRemindBot');
    const code = url.searchParams.get('start');
    assert.match(code, /^[A-Za-z0-9_-]{16,64}$/);
    // What the polling loop does with "/start <code>":
    const row = api.app.db.prepare('SELECT account_id FROM notify_codes WHERE code = ?').get(code);
    assert.equal(row.account_id, owner.id);
  });

  test('discord links through its sign-in and stores the user', async () => {
    const link = await api.request('POST', '/notify/discord/link', { token: owner.session });
    const url = new URL(link.body.url);
    assert.equal(url.searchParams.get('scope'), 'identify');
    assert.equal(url.searchParams.get('redirect_uri'), 'https://senseiissei.dev/ma/api/notify/discord/callback');
    api.fetchStub.handler = async (target) => {
      if (target.endsWith('/oauth2/token')) return Response.json({ access_token: 'user-token' });
      if (target.endsWith('/users/@me')) return Response.json({ id: '777', username: 'sensei', global_name: 'Sensei' });
      throw new Error(`unexpected ${target}`);
    };
    const callback = await fetch(`${api.origin}${api.prefix}/notify/discord/callback?code=abc&state=${url.searchParams.get('state')}`);
    assert.equal(callback.status, 200);
    const status = await api.request('GET', '/notify', { token: owner.session });
    assert.deepEqual(status.body.discord, { available: true, connected: true, label: 'Sensei' });
    const replay = await fetch(`${api.origin}${api.prefix}/notify/discord/callback?code=abc&state=${url.searchParams.get('state')}`);
    assert.equal(replay.status, 400, 'a state works once');
  });

  test('test messages go to every linked channel; time is per account', async () => {
    api.app.db
      .prepare("INSERT INTO notify_targets (account_id, channel, target, label, created_at) VALUES (?, 'telegram', '4242', 'me', 0)")
      .run(owner.id);
    const sent = [];
    api.fetchStub.handler = async (target, options) => {
      sent.push(target);
      if (target.endsWith('/users/@me/channels')) return Response.json({ id: 'dm-1' });
      return Response.json({ ok: true, id: 'message' });
    };
    const res = await api.request('POST', '/notify/test', { token: owner.session });
    assert.deepEqual(res.body.failures, []);
    assert.ok(sent.some((target) => target.includes('api.telegram.org/bot123:abc/sendMessage')));
    assert.ok(sent.some((target) => target.endsWith('/channels/dm-1/messages')));
    assert.equal((await api.request('PUT', '/notify/time', { token: owner.session, body: { time: '07:30' } })).status, 204);
    assert.equal((await api.request('GET', '/notify', { token: owner.session })).body.time, '07:30');
    assert.equal((await api.request('PUT', '/notify/time', { token: owner.session, body: { time: '25:00' } })).status, 400);
  });
});

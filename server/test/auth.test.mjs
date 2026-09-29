import { strict as assert } from 'node:assert';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { after, before, describe, it } from 'node:test';
import { startServer } from './helpers.mjs';

describe('members and auth', () => {
  let s;
  before(async () => {
    s = await startServer();
  });
  after(() => s.close());

  it('serves health under the base path and nothing outside it', async () => {
    const ok = await s.request('GET', '/health');
    assert.equal(ok.status, 200);
    assert.deepEqual(ok.body, { ok: true });
    const outside = await fetch(s.origin + '/health');
    assert.equal(outside.status, 404);
    const unknown = await s.request('GET', '/nope');
    assert.equal(unknown.status, 404);
  });

  it('creates a member and stores only a hash of the secret', async () => {
    const id = randomUUID();
    const secret = randomBytes(32).toString('hex');
    const res = await s.request('POST', '/members', { body: { id, secret, nickname: '  Mika  ', avatar: 'leaf' } });
    assert.equal(res.status, 201);
    assert.equal(res.body.id, id);
    assert.equal(res.body.nickname, 'Mika');
    assert.equal(res.body.secret, undefined);
    const row = s.app.db.prepare('SELECT secret_hash FROM members WHERE id = ?').get(id);
    assert.notEqual(row.secret_hash, secret);
    assert.equal(row.secret_hash, createHash('sha256').update(secret).digest('hex'));
  });

  it('picks an id when the device sends none', async () => {
    const res = await s.request('POST', '/members', { body: { secret: randomBytes(32).toString('hex'), nickname: 'Ren' } });
    assert.equal(res.status, 201);
    assert.match(res.body.id, /^[0-9a-f-]{36}$/);
    assert.equal(res.body.avatar, 'leaf');
  });

  it('refuses a taken id', async () => {
    const m = await s.newMember();
    const res = await s.request('POST', '/members', { body: { id: m.id, secret: randomBytes(32).toString('hex'), nickname: 'X' } });
    assert.equal(res.status, 409);
  });

  it('validates the signup body', async () => {
    const secret = randomBytes(32).toString('hex');
    const cases = [
      { secret: 'short', nickname: 'A' },
      { secret, nickname: '' },
      { secret, nickname: 'x'.repeat(25) },
      { secret, nickname: 'bad‮name' },
      { secret, nickname: 'Ok', avatar: 'https://evil.example/pic.png' },
      { secret, nickname: 'Ok', email: 'a@b.c' },
      { id: 'not-a-uuid', secret, nickname: 'Ok' },
    ];
    for (const body of cases) {
      const res = await s.request('POST', '/members', { body });
      assert.equal(res.status, 400, JSON.stringify(body));
    }
    const junk = await s.request('POST', '/members', { raw: '{nope' });
    assert.equal(junk.status, 400);
    const arr = await s.request('POST', '/members', { body: [1, 2] });
    assert.equal(arr.status, 400);
  });

  it('accepts exactly 24 characters, counted as characters not bytes', async () => {
    const res = await s.request('POST', '/members', {
      body: { secret: randomBytes(32).toString('hex'), nickname: 'ä'.repeat(24) },
    });
    assert.equal(res.status, 201);
  });

  it('authenticates with Bearer id.secret and rejects everything else', async () => {
    const m = await s.newMember('Aoi');
    const me = await s.request('GET', '/me', { token: m.token });
    assert.equal(me.status, 200);
    assert.equal(me.body.nickname, 'Aoi');

    const wrongSecret = await s.request('GET', '/me', { token: `${m.id}.${randomBytes(32).toString('hex')}` });
    assert.equal(wrongSecret.status, 401);
    const unknownId = await s.request('GET', '/me', { token: `${randomUUID()}.${m.secret}` });
    assert.equal(unknownId.status, 401);
    const noDot = await s.request('GET', '/me', { token: m.id });
    assert.equal(noDot.status, 401);
    const none = await s.request('GET', '/me');
    assert.equal(none.status, 401);
    assert.equal(none.headers.get('www-authenticate'), 'Bearer');
    const basic = await s.request('GET', '/me', { headers: { Authorization: 'Basic abc' } });
    assert.equal(basic.status, 401);
  });

  it('updates nickname and avatar, and only those', async () => {
    const m = await s.newMember('Old');
    const res = await s.request('PATCH', '/me', { token: m.token, body: { nickname: 'New', avatar: 'moon.stars' } });
    assert.equal(res.status, 200);
    assert.equal(res.body.nickname, 'New');
    assert.equal(res.body.avatar, 'moon.stars');
    const partial = await s.request('PATCH', '/me', { token: m.token, body: { avatar: 'cat' } });
    assert.equal(partial.body.nickname, 'New');
    const bad = await s.request('PATCH', '/me', { token: m.token, body: { bio: 'hello' } });
    assert.equal(bad.status, 400);
    const badAvatar = await s.request('PATCH', '/me', { token: m.token, body: { avatar: 'not.a.symbol' } });
    assert.equal(badAvatar.status, 400);
  });

  it('answers 405 for a known path with the wrong method', async () => {
    const res = await s.request('DELETE', '/health');
    assert.equal(res.status, 405);
    assert.match(res.headers.get('allow'), /GET/);
  });

  it('refuses oversized bodies', async () => {
    const m = await s.newMember();
    const res = await s.request('PATCH', '/me', { token: m.token, raw: JSON.stringify({ nickname: 'x'.repeat(20_000) }) });
    assert.equal(res.status, 413);
  });
});

describe('base path', () => {
  it('can be mounted at the root', async () => {
    const s = await startServer({ BASE_PATH: '/' });
    try {
      const res = await fetch(s.origin + '/health');
      assert.equal(res.status, 200);
    } finally {
      await s.close();
    }
  });
});

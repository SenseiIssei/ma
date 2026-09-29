import { strict as assert } from 'node:assert';
import { after, before, describe, it } from 'node:test';
import { CODE_ALPHABET, normalizeCode } from '../src/circles.js';
import { startServer } from './helpers.mjs';

describe('circles', () => {
  let s;
  before(async () => {
    s = await startServer();
  });
  after(() => s.close());

  it('creates a circle with an unambiguous 8 character code', async () => {
    const owner = await s.newMember('Owner');
    const c = await s.newCircle(owner, 'Deep work');
    assert.equal(c.name, 'Deep work');
    assert.equal(c.isCreator, true);
    assert.equal(c.memberCount, 1);
    assert.equal(c.inviteCode.length, 8);
    for (const ch of c.inviteCode) assert.ok(CODE_ALPHABET.includes(ch), ch);
    assert.ok(!/[01OIL]/.test(CODE_ALPHABET));
    assert.equal(c.members.length, 1);
    assert.equal(c.members[0].isMe, true);
  });

  it('validates the circle name', async () => {
    const m = await s.newMember();
    for (const body of [{ name: '' }, { name: 'x'.repeat(41) }, { name: 5 }, { name: 'ok', secret: 1 }, {}]) {
      const res = await s.request('POST', '/circles', { token: m.token, body });
      assert.equal(res.status, 400, JSON.stringify(body));
    }
    const ok = await s.request('POST', '/circles', { token: m.token, body: { name: 'x'.repeat(40) } });
    assert.equal(ok.status, 201);
  });

  it('lets others join with a code in any case and with a dash', async () => {
    const owner = await s.newMember('Owner');
    const friend = await s.newMember('Friend');
    const c = await s.newCircle(owner);
    const typed = `${c.inviteCode.slice(0, 4).toLowerCase()}-${c.inviteCode.slice(4)}`;
    const res = await s.request('POST', '/circles/join', { token: friend.token, body: { code: typed } });
    assert.equal(res.status, 200);
    assert.equal(res.body.id, c.id);
    assert.equal(res.body.isCreator, false);
    assert.equal(res.body.members.length, 2);

    const again = await s.request('POST', '/circles/join', { token: friend.token, body: { code: c.inviteCode } });
    assert.equal(again.status, 200);
    assert.equal(again.body.members.length, 2);

    const mine = await s.request('GET', '/circles', { token: friend.token });
    assert.equal(mine.body.circles.length, 1);
    assert.equal(mine.body.circles[0].id, c.id);
  });

  it('rejects wrong and malformed codes', async () => {
    const m = await s.newMember();
    const wrong = await s.request('POST', '/circles/join', { token: m.token, body: { code: 'ZZZZZZZZ' } });
    assert.equal(wrong.status, 404);
    for (const code of ['SHORT', 'OOOOOOOO', 12345678, null]) {
      const res = await s.request('POST', '/circles/join', { token: m.token, body: { code } });
      assert.equal(res.status, 400, String(code));
    }
    assert.equal(normalizeCode('abcd efgh'), 'ABCDEFGH');
  });

  it('hides circles from outsiders', async () => {
    const owner = await s.newMember();
    const stranger = await s.newMember();
    const c = await s.newCircle(owner);
    const res = await s.request('GET', `/circles/${c.id}`, { token: stranger.token });
    assert.equal(res.status, 404);
    const leave = await s.request('POST', `/circles/${c.id}/leave`, { token: stranger.token });
    assert.equal(leave.status, 404);
    const bad = await s.request('GET', '/circles/not-a-uuid', { token: owner.token });
    assert.equal(bad.status, 400);
  });

  it('caps a circle at 20 members', async () => {
    const owner = await s.newMember();
    const c = await s.newCircle(owner);
    for (let i = 0; i < 19; i++) {
      const m = await s.newMember(`M${i}`);
      const res = await s.request('POST', '/circles/join', { token: m.token, body: { code: c.inviteCode } });
      assert.equal(res.status, 200);
    }
    const late = await s.newMember('Late');
    const res = await s.request('POST', '/circles/join', { token: late.token, body: { code: c.inviteCode } });
    assert.equal(res.status, 409);
    const detail = await s.request('GET', `/circles/${c.id}`, { token: owner.token });
    assert.equal(detail.body.members.length, 20);
  });

  it('lets any member leave and hands the circle to the next member', async () => {
    const owner = await s.newMember('Owner');
    const a = await s.newMember('A');
    const b = await s.newMember('B');
    const c = await s.newCircle(owner);
    s.clock.t += 1000;
    await s.request('POST', '/circles/join', { token: a.token, body: { code: c.inviteCode } });
    s.clock.t += 1000;
    await s.request('POST', '/circles/join', { token: b.token, body: { code: c.inviteCode } });

    const leaveB = await s.request('POST', `/circles/${c.id}/leave`, { token: b.token });
    assert.equal(leaveB.status, 204);

    const leaveOwner = await s.request('POST', `/circles/${c.id}/leave`, { token: owner.token });
    assert.equal(leaveOwner.status, 204);
    const view = await s.request('GET', `/circles/${c.id}`, { token: a.token });
    assert.equal(view.status, 200);
    assert.equal(view.body.isCreator, true);
    assert.equal(view.body.members.length, 1);

    const leaveA = await s.request('POST', `/circles/${c.id}/leave`, { token: a.token });
    assert.equal(leaveA.status, 204);
    const gone = s.app.db.prepare('SELECT 1 FROM circles WHERE id = ?').get(c.id);
    assert.equal(gone, undefined);
  });

  it('lets only the creator remove members and rotate the code', async () => {
    const owner = await s.newMember('Owner');
    const a = await s.newMember('A');
    const b = await s.newMember('B');
    const c = await s.newCircle(owner);
    await s.request('POST', '/circles/join', { token: a.token, body: { code: c.inviteCode } });
    await s.request('POST', '/circles/join', { token: b.token, body: { code: c.inviteCode } });

    const notAllowed = await s.request('DELETE', `/circles/${c.id}/members/${b.id}`, { token: a.token });
    assert.equal(notAllowed.status, 403);
    const rotateDenied = await s.request('POST', `/circles/${c.id}/rotate-code`, { token: a.token });
    assert.equal(rotateDenied.status, 403);

    const removed = await s.request('DELETE', `/circles/${c.id}/members/${b.id}`, { token: owner.token });
    assert.equal(removed.status, 204);
    const bView = await s.request('GET', `/circles/${c.id}`, { token: b.token });
    assert.equal(bView.status, 404);
    const self = await s.request('DELETE', `/circles/${c.id}/members/${owner.id}`, { token: owner.token });
    assert.equal(self.status, 400);
    const missing = await s.request('DELETE', `/circles/${c.id}/members/${b.id}`, { token: owner.token });
    assert.equal(missing.status, 404);

    const rotated = await s.request('POST', `/circles/${c.id}/rotate-code`, { token: owner.token });
    assert.equal(rotated.status, 200);
    assert.notEqual(rotated.body.inviteCode, c.inviteCode);
    const oldCode = await s.request('POST', '/circles/join', { token: b.token, body: { code: c.inviteCode } });
    assert.equal(oldCode.status, 404);
    const newCode = await s.request('POST', '/circles/join', { token: b.token, body: { code: rotated.body.inviteCode } });
    assert.equal(newCode.status, 200);
  });

  it('limits how many circles one member can be in', async () => {
    const m = await s.newMember();
    for (let i = 0; i < 10; i++) await s.newCircle(m, `C${i}`);
    const res = await s.request('POST', '/circles', { token: m.token, body: { name: 'One more' } });
    assert.equal(res.status, 409);
  });
});

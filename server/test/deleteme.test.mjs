import { strict as assert } from 'node:assert';
import { after, before, describe, it } from 'node:test';
import { day, startServer, stats } from './helpers.mjs';

describe('DELETE /me', () => {
  let s;
  before(async () => {
    s = await startServer();
  });
  after(() => s.close());

  it('removes the member, their numbers and memberships at once', async () => {
    const me = await s.newMember('Leaving');
    const friend = await s.newMember('Staying');
    const shared = await s.newCircle(me, 'Shared');
    const solo = await s.newCircle(me, 'Solo');
    s.clock.t += 1000;
    await s.request('POST', '/circles/join', { token: friend.token, body: { code: shared.inviteCode } });
    const friendsOwn = await s.newCircle(friend, 'Friend owns');
    await s.request('POST', '/circles/join', { token: me.token, body: { code: friendsOwn.inviteCode } });
    await s.request('PUT', `/stats/${day(0)}`, { token: me.token, body: stats() });
    await s.request('PUT', `/stats/${day(-1)}`, { token: me.token, body: stats() });

    const res = await s.request('DELETE', '/me', { token: me.token });
    assert.equal(res.status, 204);

    const db = s.app.db;
    assert.equal(db.prepare('SELECT 1 FROM members WHERE id = ?').get(me.id), undefined);
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM stats WHERE member_id = ?').get(me.id).n, 0);
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM circle_members WHERE member_id = ?').get(me.id).n, 0);
    // The solo circle had nobody else and is gone.
    assert.equal(db.prepare('SELECT 1 FROM circles WHERE id = ?').get(solo.id), undefined);

    // The shared circle lives on with the friend as its creator.
    const view = await s.request('GET', `/circles/${shared.id}`, { token: friend.token });
    assert.equal(view.status, 200);
    assert.equal(view.body.isCreator, true);
    assert.deepEqual(view.body.members.map((m) => m.nickname), ['Staying']);

    const other = await s.request('GET', `/circles/${friendsOwn.id}`, { token: friend.token });
    assert.equal(other.body.members.length, 1);

    const again = await s.request('GET', '/me', { token: me.token });
    assert.equal(again.status, 401);
  });
});

import { strict as assert } from 'node:assert';
import { after, before, describe, it } from 'node:test';
import { weekBounds } from '../src/challenges.js';
import { DAY, NOON, day, startServer, stats } from './helpers.mjs';

const zero = { streakDays: 0, focusMinutes: 0, pomodoros: 0, resisted: 0, correctAnswers: 0, habitsDone: 0 };

describe('weekly challenges', () => {
  let s;
  before(async () => {
    s = await startServer();
  });
  after(() => s.close());

  async function circleOf(n) {
    const members = [];
    for (let i = 0; i < n; i++) members.push(await s.newMember(`P${i}`));
    const c = await s.newCircle(members[0]);
    for (const m of members.slice(1)) {
      await s.request('POST', '/circles/join', { token: m.token, body: { code: c.inviteCode } });
    }
    return { c, members };
  }

  it('computes Monday to Sunday weeks in UTC', () => {
    assert.deepEqual(weekBounds(NOON), { weekStart: '2026-09-28', weekEnd: '2026-10-04' });
    assert.deepEqual(weekBounds(Date.UTC(2026, 9, 4, 23, 59)), { weekStart: '2026-09-28', weekEnd: '2026-10-04' });
    assert.deepEqual(weekBounds(Date.UTC(2026, 9, 5, 0, 1)), { weekStart: '2026-10-05', weekEnd: '2026-10-11' });
  });

  it('only the creator picks, and only from the fixed list', async () => {
    const { c, members } = await circleOf(2);
    const denied = await s.request('PUT', `/circles/${c.id}/challenge`, { token: members[1].token, body: { kind: 'resist-together' } });
    assert.equal(denied.status, 403);
    const unknown = await s.request('PUT', `/circles/${c.id}/challenge`, { token: members[0].token, body: { kind: 'run-a-marathon' } });
    assert.equal(unknown.status, 400);
    const missing = await s.request('PUT', `/circles/${c.id}/challenge`, { token: members[0].token, body: {} });
    assert.equal(missing.status, 400);
    const ok = await s.request('PUT', `/circles/${c.id}/challenge`, { token: members[0].token, body: { kind: 'resist-together' } });
    assert.equal(ok.status, 200);
    assert.equal(ok.body.challenge.kind, 'resist-together');
    assert.equal(ok.body.challenge.total, 0);
    const cleared = await s.request('PUT', `/circles/${c.id}/challenge`, { token: members[0].token, body: { kind: null } });
    assert.equal(cleared.body.challenge, null);
  });

  it('pools numbers for a "together" challenge and ignores last week', async () => {
    const { c, members } = await circleOf(3);
    await s.request('PUT', `/circles/${c.id}/challenge`, { token: members[0].token, body: { kind: 'resist-together' } });
    // Last Sunday belongs to the previous week and must not count.
    const now = s.clock.t;
    s.clock.t = NOON - 3 * DAY;
    await s.request('PUT', `/stats/${day(-3)}`, { token: members[0].token, body: { ...zero, resisted: 50 } });
    s.clock.t = now;
    await s.request('PUT', `/stats/${day(-1)}`, { token: members[0].token, body: { ...zero, resisted: 6 } });
    await s.request('PUT', `/stats/${day(0)}`, { token: members[1].token, body: { ...zero, resisted: 5 } });
    const mid = await s.request('GET', `/circles/${c.id}`, { token: members[2].token });
    assert.equal(mid.body.challenge.total, 11);
    assert.equal(mid.body.challenge.goal, 20);
    assert.equal(mid.body.challenge.completed, false);
    assert.ok(Math.abs(mid.body.challenge.progress - 0.55) < 1e-9);

    await s.request('PUT', `/stats/${day(0)}`, { token: members[2].token, body: { ...zero, resisted: 30 } });
    const done = await s.request('GET', `/circles/${c.id}`, { token: members[2].token });
    assert.equal(done.body.challenge.total, 41);
    assert.equal(done.body.challenge.progress, 1);
    assert.equal(done.body.challenge.completed, true);
  });

  it('caps each person for an "each" challenge', async () => {
    const { c, members } = await circleOf(2);
    await s.request('PUT', `/circles/${c.id}/challenge`, { token: members[0].token, body: { kind: 'focus-rounds-each' } });
    await s.request('PUT', `/stats/${day(0)}`, { token: members[0].token, body: stats({ pomodoros: 12 }) });
    await s.request('PUT', `/stats/${day(0)}`, { token: members[1].token, body: stats({ pomodoros: 2 }) });
    const res = await s.request('GET', `/circles/${c.id}`, { token: members[1].token });
    const ch = res.body.challenge;
    assert.equal(ch.mode, 'each');
    assert.equal(ch.goal, 10);
    assert.equal(ch.total, 7);
    assert.equal(ch.completed, false);
    assert.deepEqual(
      ch.members.map((m) => m.value).sort((x, y) => x - y),
      [2, 12],
    );

    await s.request('PUT', `/stats/${day(-1)}`, { token: members[1].token, body: stats({ pomodoros: 3 }) });
    const after2 = await s.request('GET', `/circles/${c.id}`, { token: members[1].token });
    assert.equal(after2.body.challenge.total, 10);
    assert.equal(after2.body.challenge.completed, true);
  });

  it('only counts people who are members now', async () => {
    const { c, members } = await circleOf(2);
    await s.request('PUT', `/circles/${c.id}/challenge`, { token: members[0].token, body: { kind: 'cards-together' } });
    await s.request('PUT', `/stats/${day(0)}`, { token: members[1].token, body: stats({ correctAnswers: 40 }) });
    await s.request('POST', `/circles/${c.id}/leave`, { token: members[1].token });
    const res = await s.request('GET', `/circles/${c.id}`, { token: members[0].token });
    assert.equal(res.body.challenge.total, 0);
  });
});

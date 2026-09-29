import { strict as assert } from 'node:assert';
import { after, before, describe, it } from 'node:test';
import { isTodayOrYesterday } from '../src/stats.js';
import { DAY, NOON, day, startServer, stats } from './helpers.mjs';

describe('daily numbers', () => {
  let s;
  before(async () => {
    s = await startServer();
  });
  after(() => s.close());

  it('accepts today and yesterday and upserts', async () => {
    const m = await s.newMember();
    const today = await s.request('PUT', `/stats/${day(0)}`, { token: m.token, body: stats() });
    assert.equal(today.status, 200);
    assert.equal(today.body.focusMinutes, 50);
    const yesterday = await s.request('PUT', `/stats/${day(-1)}`, { token: m.token, body: stats({ pomodoros: 1 }) });
    assert.equal(yesterday.status, 200);
    const again = await s.request('PUT', `/stats/${day(0)}`, { token: m.token, body: stats({ focusMinutes: 75 }) });
    assert.equal(again.status, 200);
    const rows = s.app.db.prepare('SELECT date, focus_minutes FROM stats WHERE member_id = ? ORDER BY date').all(m.id);
    assert.equal(rows.length, 2);
    assert.equal(rows[1].focus_minutes, 75);
  });

  it('refuses dates outside today or yesterday', async () => {
    const m = await s.newMember();
    for (const d of [day(-3), day(2), day(-30), '2026-02-30', '2026-9-30', 'today', '2026-13-01']) {
      const res = await s.request('PUT', `/stats/${d}`, { token: m.token, body: stats() });
      assert.equal(res.status, 400, d);
    }
  });

  it('allows for time zones from UTC-12 to UTC+14', () => {
    const today = Date.UTC(2026, 8, 30);
    // 11:00 UTC on the 29th is already the 30th in Kiribati (UTC+14).
    assert.ok(isTodayOrYesterday(today, today - 13 * 3_600_000));
    assert.ok(!isTodayOrYesterday(today, today - 15 * 3_600_000));
    // 11:00 UTC on 2 Oct is still 1 Oct on Baker Island (UTC-12), so the 30th is yesterday there.
    assert.ok(isTodayOrYesterday(today, today + 2 * DAY + 11 * 3_600_000));
    assert.ok(!isTodayOrYesterday(today, today + 2 * DAY + 13 * 3_600_000));
  });

  it('validates every number and refuses anything else', async () => {
    const m = await s.newMember();
    const bad = [
      stats({ focusMinutes: -1 }),
      stats({ focusMinutes: 1441 }),
      stats({ pomodoros: 1.5 }),
      stats({ resisted: '3' }),
      stats({ correctAnswers: null }),
      { ...stats(), note: 'had a great day' },
      (({ habitsDone, ...rest }) => rest)(stats()),
    ];
    for (const body of bad) {
      const res = await s.request('PUT', `/stats/${day(0)}`, { token: m.token, body });
      assert.equal(res.status, 400, JSON.stringify(body));
    }
    const empty = await s.request('PUT', `/stats/${day(0)}`, { token: m.token });
    assert.equal(empty.status, 400);
  });

  it('needs auth', async () => {
    const res = await s.request('PUT', `/stats/${day(0)}`, { body: stats() });
    assert.equal(res.status, 401);
  });

  it('shows members the last days of each other in the circle', async () => {
    const a = await s.newMember('A');
    const b = await s.newMember('B');
    const c = await s.newCircle(a);
    await s.request('POST', '/circles/join', { token: b.token, body: { code: c.inviteCode } });
    // Written back when those days were current.
    const now = s.clock.t;
    for (let i = 10; i >= 0; i--) {
      s.clock.t = NOON - i * DAY;
      await s.request('PUT', `/stats/${day(-i)}`, { token: b.token, body: stats({ streakDays: 10 - i }) });
    }
    s.clock.t = now;
    const res = await s.request('GET', `/circles/${c.id}`, { token: a.token });
    const bee = res.body.members.find((m) => m.id === b.id);
    assert.equal(bee.days[0].date, day(0));
    assert.equal(bee.days[0].streakDays, 10);
    assert.ok(bee.days.length >= 7 && bee.days.length <= 8, String(bee.days.length));
    assert.deepEqual(Object.keys(bee.days[0]).sort(), [
      'correctAnswers', 'date', 'focusMinutes', 'habitsDone', 'pomodoros', 'resisted', 'streakDays',
    ]);
    const me = res.body.members.find((m) => m.id === a.id);
    assert.deepEqual(me.days, []);
  });

  it('forgets numbers older than the retention window', async () => {
    const { pruneStats } = await import('../src/stats.js');
    const m = await s.newMember();
    s.app.db
      .prepare('INSERT INTO stats VALUES (?, ?, 1, 1, 1, 1, 1, 1, 0)')
      .run(m.id, day(-40));
    const removed = pruneStats(s.app.db, NOON, 30);
    assert.ok(removed >= 1);
    const left = s.app.db.prepare('SELECT 1 FROM stats WHERE member_id = ? AND date = ?').get(m.id, day(-40));
    assert.equal(left, undefined);
  });
});

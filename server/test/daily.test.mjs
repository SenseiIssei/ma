import assert from 'node:assert/strict';
import { after, before, describe, test } from 'node:test';
import {
  addDays,
  berlinDayKey,
  berlinMinuteOfDay,
  replayEntries,
  summarize,
  unitIndexForDay,
} from '../src/dailyStreak.js';
import { playlistIndexForDay, reminderText } from '../src/dailyReminders.js';
import { DAY, startServer } from './helpers.mjs';

const done = (dayKey, baseXp = 20) => ({ dayKey, unitId: 'cpp-raii', status: 'done', baseXp });
const skipped = (dayKey) => ({ dayKey, unitId: 'cpp-raii', status: 'skipped', baseXp: 0 });

describe('daily calendar', () => {
  test('the day switches at midnight Berlin time, not UTC', () => {
    // 22:30 UTC on 30 Sep is 00:30 on 1 Oct in Berlin (CEST, UTC+2).
    assert.equal(berlinDayKey(Date.UTC(2026, 8, 30, 22, 30)), '2026-10-01');
    assert.equal(berlinDayKey(Date.UTC(2026, 8, 30, 21, 59)), '2026-09-30');
    // Winter time: 23:30 UTC on 31 Dec is already 1 Jan in Berlin.
    assert.equal(berlinDayKey(Date.UTC(2026, 11, 31, 23, 30)), '2027-01-01');
    assert.equal(berlinMinuteOfDay(Date.UTC(2026, 9, 1, 7, 0)), 9 * 60);
  });

  test('unit N on day N, wrapping around, unit 1 before the start', () => {
    assert.equal(unitIndexForDay('2026-10-01', 52), 0);
    assert.equal(unitIndexForDay('2026-10-02', 52), 1);
    assert.equal(unitIndexForDay('2026-09-20', 52), 0);
    assert.equal(unitIndexForDay(addDays('2026-10-01', 52), 52), 0);
  });

  test('playlists visit every entry before repeating', () => {
    for (const count of [1, 7, 14, 40]) {
      const seen = new Set();
      for (let day = 0; day < count; day++) seen.add(playlistIndexForDay(20000 + day, count));
      assert.equal(seen.size, count);
    }
  });
});

describe('daily streak rules', () => {
  test('consecutive days grow the streak and the bonus, capped', () => {
    const entries = [];
    for (let day = 0; day < 15; day++) entries.push(done(addDays('2026-10-01', day)));
    const { entries: replayed } = replayEntries(entries);
    assert.deepEqual(replayed.slice(0, 3).map((entry) => entry.bonusXp), [0, 3, 6]);
    assert.equal(replayed[2].xpAwarded, 26);
    assert.equal(replayed[14].streakAfter, 15);
    assert.equal(replayed[14].bonusXp, 30, 'bonus is capped at 30');
  });

  test('one missed day costs the next bonus but keeps the streak', () => {
    const { entries: replayed } = replayEntries([done('2026-10-01'), done('2026-10-02'), done('2026-10-04')]);
    assert.equal(replayed[2].bonusXp, 0);
    assert.equal(replayed[2].streakAfter, 3);
  });

  test('two missed days in a row reset the streak', () => {
    const { entries: replayed } = replayEntries([done('2026-10-01'), done('2026-10-02'), done('2026-10-05')]);
    assert.equal(replayed[2].streakAfter, 1);
    assert.equal(replayed[2].bonusXp, 0);
  });

  test('a skip counts like a missed day, two skips reset', () => {
    const one = replayEntries([done('2026-10-01'), skipped('2026-10-02'), done('2026-10-03')]).entries;
    assert.equal(one[2].streakAfter, 2);
    assert.equal(one[2].bonusXp, 0);
    const two = replayEntries([done('2026-10-01'), skipped('2026-10-02'), skipped('2026-10-03'), done('2026-10-04')]).entries;
    assert.equal(two[3].streakAfter, 1);
  });

  test('summary looks at the empty days up to yesterday', () => {
    const entries = [done('2026-10-01'), done('2026-10-02')];
    assert.equal(summarize(entries, '2026-10-03').streak, 2);
    assert.equal(summarize(entries, '2026-10-03').bonusToday, 6);
    assert.equal(summarize(entries, '2026-10-04').bonusToday, 0, 'one empty day: no bonus');
    assert.equal(summarize(entries, '2026-10-04').streak, 2);
    assert.equal(summarize(entries, '2026-10-05').streak, 0, 'two empty days: streak gone');
    assert.equal(summarize(entries, '2026-10-02').today.status, 'done');
    assert.equal(summarize(entries, '2026-10-02').totalXp, 20 + 23);
  });
});

describe('daily routes', () => {
  let api;
  before(async () => {
    api = await startServer();
  });
  after(() => api.close());

  async function linkedBrowser() {
    const member = await api.newMember('Jakob');
    const code = await api.request('POST', '/daily/link-code', { token: member.token });
    assert.equal(code.status, 201);
    assert.match(code.body.code, /^[A-HJ-NP-Z2-9]{6}$/);
    const link = await api.request('POST', '/daily/link', { body: { code: code.body.code.toLowerCase() } });
    assert.equal(link.status, 201);
    assert.match(link.body.token, /^daily_[0-9a-f]{64}$/);
    return { member, token: link.body.token, code: code.body.code };
  }

  test('a code links once, then it is gone', async () => {
    const { code } = await linkedBrowser();
    const again = await api.request('POST', '/daily/link', { body: { code } });
    assert.equal(again.status, 404);
  });

  test('codes expire after ten minutes', async () => {
    const member = await api.newMember('Late');
    const code = await api.request('POST', '/daily/link-code', { token: member.token });
    api.clock.t += 11 * 60_000;
    const late = await api.request('POST', '/daily/link', { body: { code: code.body.code } });
    assert.equal(late.status, 404);
    api.clock.t -= 11 * 60_000;
  });

  test('nobody can record without a linked browser', async () => {
    const anonymous = await api.request('POST', '/daily/done', { body: { unitId: 'cpp-raii', xpReward: 20 } });
    assert.equal(anonymous.status, 401);
    const forged = await api.request('POST', '/daily/done', { token: `daily_${'a'.repeat(64)}`, body: { unitId: 'cpp-raii', xpReward: 20 } });
    assert.equal(forged.status, 401);
  });

  test('done records XP once per day and the app reads the same numbers', async () => {
    const { member, token } = await linkedBrowser();
    const today = berlinDayKey(api.clock.t);
    const first = await api.request('POST', '/daily/done', { token, body: { dayKey: today, unitId: 'cpp-raii', xpReward: 20 } });
    assert.equal(first.status, 200);
    assert.equal(first.body.entry.xpAwarded, 20);
    const repeat = await api.request('POST', '/daily/done', { token, body: { unitId: 'cpp-raii', xpReward: 50 } });
    assert.equal(repeat.body.entry.xpAwarded, 20, 'the second call changes nothing');
    const skipAfter = await api.request('POST', '/daily/skip', { token, body: { unitId: 'cpp-raii' } });
    assert.equal(skipAfter.body.entry.status, 'done', 'a finished day stays finished');
    const fromApp = await api.request('GET', '/daily/progress', { token: member.token });
    assert.equal(fromApp.status, 200);
    assert.equal(fromApp.body.totalXp, 20);
    assert.equal(fromApp.body.today.status, 'done');
  });

  test('buffered days can be sent later, within two weeks, never in the future', async () => {
    const { token } = await linkedBrowser();
    const today = berlinDayKey(api.clock.t);
    const yesterday = addDays(today, -1);
    const late = await api.request('POST', '/daily/done', { token, body: { dayKey: yesterday, unitId: 'cpp-rule-of-five', xpReward: 30 } });
    assert.equal(late.status, 200);
    const now = await api.request('POST', '/daily/done', { token, body: { dayKey: today, unitId: 'cpp-move', xpReward: 30 } });
    assert.equal(now.body.entry.bonusXp, 3, 'yesterday counts for the streak');
    const old = await api.request('POST', '/daily/done', { token, body: { dayKey: addDays(today, -20), unitId: 'cpp-raii', xpReward: 20 } });
    assert.equal(old.status, 400);
    const future = await api.request('POST', '/daily/done', { token, body: { dayKey: addDays(today, 1), unitId: 'cpp-raii', xpReward: 20 } });
    assert.equal(future.status, 400);
  });

  test('the reward is clamped and bad input is refused', async () => {
    const { token } = await linkedBrowser();
    const greedy = await api.request('POST', '/daily/done', { token, body: { unitId: 'cpp-raii', xpReward: 9000 } });
    assert.equal(greedy.body.entry.xpAwarded, 50);
    const bad = await api.request('POST', '/daily/skip', { token, body: { unitId: 'DROP TABLE' } });
    assert.equal(bad.status, 400);
    const extra = await api.request('POST', '/daily/skip', { token, body: { unitId: 'cpp-raii', admin: true } });
    assert.equal(extra.status, 400);
  });

  test('unlinking revokes the token, deleting the member removes everything', async () => {
    const { member, token } = await linkedBrowser();
    await api.request('POST', '/daily/done', { token, body: { unitId: 'cpp-raii', xpReward: 20 } });
    const unlink = await api.request('DELETE', '/daily/link', { token });
    assert.equal(unlink.status, 204);
    const after = await api.request('GET', '/daily/progress', { token });
    assert.equal(after.status, 401);
    const gone = await api.request('DELETE', '/me', { token: member.token });
    assert.equal(gone.status, 204);
    const rows = api.app.db.prepare('SELECT COUNT(*) AS n FROM daily_entries WHERE member_id = ?').get(member.id);
    assert.equal(rows.n, 0);
  });
});

describe('daily reminder text', () => {
  test('carries lesson, streak, music and the hint, without long dashes', () => {
    const text = reminderText({
      unit: { title: 'RAII', stageTitle: 'C++ Grundlagen', minutes: 30, xpReward: 15, task: 'Schreib eine Klasse FileHandle.' },
      unitNumber: 1,
      unitCount: 52,
      playlist: { title: 'morning cravings', artist: 'Someone', url: 'https://open.spotify.com/album/x' },
      streak: 4,
      bonusToday: 12,
      siteOrigin: 'https://senseiissei.dev',
    });
    assert.match(text, /RAII/);
    assert.match(text, /plus 12 Serienbonus/);
    assert.match(text, /Serie: 4 Tage/);
    assert.match(text, /morning cravings/);
    assert.doesNotMatch(text, /[–—]/);
  });
});

void DAY;

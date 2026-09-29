import { badRequest } from './http.js';
import { calendarDate, dayString, integer, object } from './validate.js';

// The only thing a member ever publishes: six numbers for one day.
// Upper bounds are generous but finite, so nobody can plant absurd values
// that wreck a circle's challenge.

export const STAT_FIELDS = [
  ['streakDays', 'streak_days', 36_500],
  ['focusMinutes', 'focus_minutes', 1_440],
  ['pomodoros', 'pomodoros', 100],
  ['resisted', 'resisted', 10_000],
  ['correctAnswers', 'correct_answers', 10_000],
  ['habitsDone', 'habits_done', 1_000],
];

const DAY = 86_400_000;
const HOUR = 3_600_000;

/**
 * "Today or yesterday" for the member. The server does not know their time
 * zone (and should not), so it accepts a date if it is today or yesterday in
 * some zone on Earth: UTC-12 through UTC+14.
 */
export function isTodayOrYesterday(dateMs, now) {
  return now >= dateMs - 14 * HOUR && now < dateMs + 2 * DAY + 12 * HOUR;
}

export function parseStats(body) {
  object(body, STAT_FIELDS.map(([key]) => key));
  const out = {};
  for (const [key, , max] of STAT_FIELDS) {
    if (!(key in body)) throw badRequest(`${key} is required`);
    out[key] = integer(body[key], 0, max, key);
  }
  return out;
}

function rowToDay(r) {
  return {
    date: r.date,
    streakDays: r.streak_days,
    focusMinutes: r.focus_minutes,
    pomodoros: r.pomodoros,
    resisted: r.resisted,
    correctAnswers: r.correct_answers,
    habitsDone: r.habits_done,
  };
}

/** Last days of numbers for a set of members, keyed by member id. */
export function recentDays(db, memberIds, now, days = 7) {
  const result = new Map(memberIds.map((id) => [id, []]));
  if (memberIds.length === 0) return result;
  // A member's local "today" can be one UTC day behind, so one extra day.
  const from = dayString(now - days * DAY);
  const placeholders = memberIds.map(() => '?').join(',');
  const rows = db
    .prepare(
      `SELECT member_id, date, streak_days, focus_minutes, pomodoros, resisted, correct_answers, habits_done
         FROM stats WHERE date >= ? AND member_id IN (${placeholders})
        ORDER BY date DESC`,
    )
    .all(from, ...memberIds);
  for (const r of rows) result.get(r.member_id)?.push(rowToDay(r));
  return result;
}

export function pruneStats(db, now, retentionDays) {
  if (retentionDays <= 0) return 0;
  const cutoff = dayString(now - retentionDays * DAY);
  return Number(db.prepare('DELETE FROM stats WHERE date < ?').run(cutoff).changes);
}

export function statsRoutes() {
  return [
    {
      method: 'PUT',
      path: '/stats/:date',
      auth: 'member',
      async handler({ ctx, member, params, body }) {
        const dateMs = calendarDate(params.date);
        if (!isTodayOrYesterday(dateMs, ctx.now())) {
          throw badRequest('Only today or yesterday can be published');
        }
        const s = parseStats(body);
        ctx.db
          .prepare(
            `INSERT INTO stats (member_id, date, streak_days, focus_minutes, pomodoros, resisted, correct_answers, habits_done, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
             ON CONFLICT (member_id, date) DO UPDATE SET
               streak_days = excluded.streak_days,
               focus_minutes = excluded.focus_minutes,
               pomodoros = excluded.pomodoros,
               resisted = excluded.resisted,
               correct_answers = excluded.correct_answers,
               habits_done = excluded.habits_done,
               updated_at = excluded.updated_at`,
          )
          .run(member.id, params.date, s.streakDays, s.focusMinutes, s.pomodoros, s.resisted, s.correctAnswers, s.habitsDone, ctx.now());
        return { status: 200, body: { date: params.date, ...s } };
      },
    },
  ];
}

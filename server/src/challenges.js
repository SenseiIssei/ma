import { dayString } from './validate.js';

// The fixed list a circle creator picks from. "each" means every member has
// to reach the target on their own; "together" means the circle pools its
// numbers. Titles are English fallbacks; the app shows its own translations.

export const CHALLENGES = [
  { kind: 'focus-rounds-each', metric: 'pomodoros', mode: 'each', target: 5, title: '5 focus rounds each' },
  { kind: 'focus-minutes-together', metric: 'focusMinutes', mode: 'together', target: 600, title: '600 focus minutes together' },
  { kind: 'resist-together', metric: 'resisted', mode: 'together', target: 20, title: 'Resist 20 impulses together' },
  { kind: 'cards-together', metric: 'correctAnswers', mode: 'together', target: 100, title: 'Learn 100 cards together' },
  { kind: 'cards-each', metric: 'correctAnswers', mode: 'each', target: 30, title: '30 right answers each' },
  { kind: 'habits-each', metric: 'habitsDone', mode: 'each', target: 10, title: '10 habits done each' },
];

export const CHALLENGE_KINDS = CHALLENGES.map((c) => c.kind);

// Metric name in the API to its column. Only these fixed strings ever reach
// SQL text, never anything from a request.
const COLUMNS = {
  pomodoros: 'pomodoros',
  focusMinutes: 'focus_minutes',
  resisted: 'resisted',
  correctAnswers: 'correct_answers',
  habitsDone: 'habits_done',
};

export function findChallenge(kind) {
  return CHALLENGES.find((c) => c.kind === kind) ?? null;
}

/** Monday to Sunday of the week containing `now`, as UTC calendar dates. */
export function weekBounds(now) {
  const d = new Date(now);
  const midnight = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
  const sinceMonday = (d.getUTCDay() + 6) % 7;
  const start = midnight - sinceMonday * 86_400_000;
  return { weekStart: dayString(start), weekEnd: dayString(start + 6 * 86_400_000) };
}

/**
 * Progress of a circle's challenge for the current week, counting only the
 * people who are members right now.
 */
export function challengeProgress(db, circleId, kind, now) {
  const def = findChallenge(kind);
  if (!def) return null;
  const { weekStart, weekEnd } = weekBounds(now);
  const column = COLUMNS[def.metric];
  const rows = db
    .prepare(
      `SELECT cm.member_id AS memberId, COALESCE(SUM(s.${column}), 0) AS value
         FROM circle_members cm
         LEFT JOIN stats s ON s.member_id = cm.member_id AND s.date BETWEEN ? AND ?
        WHERE cm.circle_id = ?
        GROUP BY cm.member_id
        ORDER BY cm.joined_at, cm.member_id`,
    )
    .all(weekStart, weekEnd, circleId)
    .map((r) => ({ memberId: r.memberId, value: Number(r.value) }));

  let total;
  let goal;
  let completed;
  if (def.mode === 'each') {
    // Capped per person, so one busy member cannot carry the whole circle.
    total = rows.reduce((sum, r) => sum + Math.min(r.value, def.target), 0);
    goal = def.target * Math.max(1, rows.length);
    completed = rows.length > 0 && rows.every((r) => r.value >= def.target);
  } else {
    total = rows.reduce((sum, r) => sum + r.value, 0);
    goal = def.target;
    completed = total >= goal;
  }
  return {
    kind: def.kind,
    title: def.title,
    metric: def.metric,
    mode: def.mode,
    target: def.target,
    goal,
    total,
    progress: goal > 0 ? Math.min(1, total / goal) : 0,
    completed,
    weekStart,
    weekEnd,
    members: rows,
  };
}

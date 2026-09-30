// Calendar and streak rules for the daily programming lesson. Pure
// functions, no database, so the same rules can be tested in isolation and
// mirrored one to one on the website (src/daily/streak.ts there).

export const TIME_ZONE = 'Europe/Berlin';
/** Day one of the curriculum: unit 1 on this day, unit N on day N. */
export const CURRICULUM_START = '2026-10-01';
export const BONUS_PER_STREAK_DAY = 3;
export const BONUS_CAP = 30;
export const XP_REWARD_MIN = 10;
export const XP_REWARD_MAX = 50;

const DAY_MS = 86_400_000;
const DAY_KEY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

// en-CA formats as YYYY-MM-DD, which is exactly a day key.
const berlinDateFormat = new Intl.DateTimeFormat('en-CA', {
  timeZone: TIME_ZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

const berlinClockFormat = new Intl.DateTimeFormat('en-GB', {
  timeZone: TIME_ZONE,
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
});

export function isDayKey(value) {
  if (typeof value !== 'string' || !DAY_KEY_PATTERN.test(value)) return false;
  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

/** The calendar day in Berlin for a moment, midnight local time is the switch. */
export function berlinDayKey(epochMilliseconds) {
  return berlinDateFormat.format(new Date(epochMilliseconds));
}

/** Minutes after midnight in Berlin, for the reminder schedule. */
export function berlinMinuteOfDay(epochMilliseconds) {
  const [hours, minutes] = berlinClockFormat.format(new Date(epochMilliseconds)).split(':').map(Number);
  return hours * 60 + minutes;
}

/** Whole days since 1970-01-01 for a day key. Only differences matter. */
export function dayNumber(dayKey) {
  const [year, month, day] = dayKey.split('-').map(Number);
  return Math.round(Date.UTC(year, month - 1, day) / DAY_MS);
}

export function addDays(dayKey, days) {
  return new Date((dayNumber(dayKey) + days) * DAY_MS).toISOString().slice(0, 10);
}

export function daysBetween(fromDayKey, toDayKey) {
  return dayNumber(toDayKey) - dayNumber(fromDayKey);
}

/** Position in the curriculum for a day; before the start it is unit 1. */
export function unitIndexForDay(dayKey, unitCount) {
  if (unitCount <= 0) return -1;
  const offset = Math.max(0, daysBetween(CURRICULUM_START, dayKey));
  return offset % unitCount;
}

export function clampXpReward(value) {
  const number = Number.isFinite(value) ? Math.round(value) : XP_REWARD_MIN;
  return Math.min(XP_REWARD_MAX, Math.max(XP_REWARD_MIN, number));
}

export function streakBonus(streakBefore, missedDaysInARow) {
  // One missed day costs the bonus of the next lesson, not the streak.
  if (missedDaysInARow > 0) return 0;
  return Math.min(streakBefore * BONUS_PER_STREAK_DAY, BONUS_CAP);
}

/**
 * Walks the days from the first entry onwards and applies the rules:
 * a finished lesson grows the streak and earns base XP plus the bonus;
 * a skipped or empty day earns nothing and cancels the next bonus; two such
 * days in a row set the streak back to zero.
 *
 * entries: [{ dayKey, status: 'done' | 'skipped', baseXp, ... }] in any order.
 * Returns the entries in day order with xpAwarded and streakAfter filled in,
 * plus the state at the end of the last entry.
 */
export function replayEntries(entries) {
  const sorted = [...entries].sort((first, second) => (first.dayKey < second.dayKey ? -1 : first.dayKey > second.dayKey ? 1 : 0));
  let streak = 0;
  let missedDaysInARow = 0;
  let previousDayKey = null;
  const replayed = [];
  for (const entry of sorted) {
    if (previousDayKey !== null) {
      const emptyDays = daysBetween(previousDayKey, entry.dayKey) - 1;
      for (let day = 0; day < emptyDays; day++) {
        missedDaysInARow += 1;
        if (missedDaysInARow >= 2) streak = 0;
      }
    }
    if (entry.status === 'done') {
      const bonus = streakBonus(streak, missedDaysInARow);
      streak += 1;
      missedDaysInARow = 0;
      replayed.push({ ...entry, bonusXp: bonus, xpAwarded: clampXpReward(entry.baseXp) + bonus, streakAfter: streak });
    } else {
      missedDaysInARow += 1;
      if (missedDaysInARow >= 2) streak = 0;
      replayed.push({ ...entry, bonusXp: 0, xpAwarded: 0, streakAfter: streak });
    }
    previousDayKey = entry.dayKey;
  }
  return { entries: replayed, streak, missedDaysInARow, lastDayKey: previousDayKey };
}

/**
 * The picture for today: current streak, the bonus today's lesson would
 * earn, totals. Days between the last entry and yesterday count as missed.
 */
export function summarize(entries, todayDayKey) {
  const past = entries.filter((entry) => entry.dayKey <= todayDayKey);
  const replay = replayEntries(past);
  const today = replay.entries.find((entry) => entry.dayKey === todayDayKey) ?? null;
  const beforeToday = replayEntries(past.filter((entry) => entry.dayKey < todayDayKey));
  let streak = beforeToday.streak;
  let missedDaysInARow = beforeToday.missedDaysInARow;
  if (beforeToday.lastDayKey !== null) {
    const emptyDays = daysBetween(beforeToday.lastDayKey, todayDayKey) - 1;
    for (let day = 0; day < emptyDays; day++) {
      missedDaysInARow += 1;
      if (missedDaysInARow >= 2) streak = 0;
    }
  }
  const doneEntries = replay.entries.filter((entry) => entry.status === 'done');
  return {
    todayDayKey,
    today,
    streak: today ? today.streakAfter : streak,
    bonusToday: today ? today.bonusXp : streakBonus(streak, missedDaysInARow),
    totalXp: doneEntries.reduce((sum, entry) => sum + entry.xpAwarded, 0),
    doneCount: doneEntries.length,
    skippedCount: replay.entries.length - doneEntries.length,
    entries: replay.entries,
  };
}

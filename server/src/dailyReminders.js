import { featuresOf } from './accounts.js';
import { dailyProgress } from './daily.js';
import { channelsAvailable, reminderMinute } from './notify.js';
import { berlinDayKey, berlinMinuteOfDay, unitIndexForDay } from './dailyStreak.js';

// Once a day, at each owner's own time (Berlin), a short note with the lesson
// of the day goes to the channels that account linked in Ma: Telegram and a
// Discord direct message. The lesson and the playlist come from the files
// the website publishes, so the content has exactly one home. When the
// lesson is already done, nothing is sent.

const FETCH_TIMEOUT_MS = 8_000;
const CONTENT_CACHE_MS = 60 * 60_000;

function parseClock(text) {
  const match = /^(\d{1,2}):(\d{2})$/.exec((text ?? '').trim());
  if (!match) return 9 * 60;
  const hours = Math.min(23, Number(match[1]));
  const minutes = Math.min(59, Number(match[2]));
  return hours * 60 + minutes;
}

export function reminderConfig(env = process.env) {
  return {
    minuteOfDay: parseClock(env.DAILY_REMINDER_TIME || '09:00'),
    siteOrigin: (env.DAILY_SITE_ORIGIN || 'https://senseiissei.dev').replace(/\/+$/, ''),
  };
}

async function fetchJson(url, { fetchImpl = fetch, ...options } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const response = await fetchImpl(url, { ...options, signal: controller.signal });
    if (!response.ok) throw new Error(`${url} answered ${response.status}`);
    return response.status === 204 ? null : await response.json();
  } finally {
    clearTimeout(timer);
  }
}

function allUnits(curriculum) {
  return (curriculum?.stages ?? []).flatMap((stage) => stage.units.map((unit) => ({ ...unit, stageTitle: stage.title })));
}

/** Pure: the text of the reminder, so it can be tested without a network. */
export function reminderText({ unit, unitNumber, unitCount, playlist, streak, bonusToday, siteOrigin }) {
  const lines = [
    `daily: ${unit.title}`,
    `${unit.stageTitle} · Einheit ${unitNumber} von ${unitCount} · etwa ${unit.minutes} Minuten · ${unit.xpReward} XP${bonusToday > 0 ? ` plus ${bonusToday} Serienbonus` : ''}`,
    '',
    unit.task,
    '',
    `Serie: ${streak} ${streak === 1 ? 'Tag' : 'Tage'}. Ohne KI lösen, dafür ist die Aufgabe da.`,
  ];
  if (playlist) lines.push(`Musik: ${playlist.title} von ${playlist.artist} ${playlist.url}`);
  lines.push(`Los geht's: ${siteOrigin}/ und im Terminal daily eingeben.`);
  return lines.join('\n');
}

export function playlistIndexForDay(dayNumberValue, count) {
  if (count <= 0) return -1;
  // A stride without common factors with the count visits every entry
  // before any repeats, and neighbouring days get different moods.
  let stride = 7;
  const gcd = (first, second) => (second === 0 ? first : gcd(second, first % second));
  while (gcd(stride, count) !== 1) stride += 1;
  return (((dayNumberValue * stride) % count) + count) % count;
}

export function startDailyReminders({ ctx, env = process.env, log = console, fetchImpl = fetch }) {
  const config = reminderConfig(env);
  const available = channelsAvailable(ctx.config);
  if (!available.telegram && !available.discord) return { stop() {}, config };

  let cache = { at: 0, curriculum: null, playlists: null };
  async function content() {
    if (Date.now() - cache.at < CONTENT_CACHE_MS && cache.curriculum) return cache;
    const [curriculum, playlists] = await Promise.all([
      fetchJson(`${config.siteOrigin}/daily/curriculum.json`, { fetchImpl }),
      fetchJson(`${config.siteOrigin}/daily/playlists.json`, { fetchImpl }).catch(() => null),
    ]);
    cache = { at: Date.now(), curriculum, playlists };
    return cache;
  }

  let running = false;
  async function tick() {
    if (running) return;
    running = true;
    try {
      const now = ctx.now();
      const todayDayKey = berlinDayKey(now);
      const minuteNow = berlinMinuteOfDay(now);
      const { db } = ctx;
      // Owners with at least one linked channel; each has their own time.
      const accounts = db
        .prepare(`SELECT DISTINCT a.* FROM accounts a JOIN notify_targets t ON t.account_id = a.id WHERE a.email_verified_at IS NOT NULL`)
        .all()
        .filter((account) => featuresOf(account, ctx.config).includes('reminders'));
      for (const account of accounts) {
        if (minuteNow < reminderMinute(db, account.id)) continue;
        if (db.prepare('SELECT 1 FROM daily_reminders_sent WHERE account_id = ? AND day_key = ?').get(account.id, todayDayKey)) continue;
        const markSent = () =>
          db.prepare('INSERT OR IGNORE INTO daily_reminders_sent (account_id, day_key, sent_at) VALUES (?, ?, ?)').run(account.id, todayDayKey, now);
        const progress = dailyProgress(db, account.id, now);
        if (progress.today?.status === 'done') {
          markSent();
          continue;
        }
        const { curriculum, playlists } = await content();
        const units = allUnits(curriculum);
        const index = unitIndexForDay(todayDayKey, units.length);
        if (index < 0) continue;
        const items = playlists?.items ?? [];
        const dayNumberValue = Math.round(Date.parse(`${todayDayKey}T00:00:00Z`) / 86_400_000);
        const text = reminderText({
          unit: units[index],
          unitNumber: index + 1,
          unitCount: units.length,
          playlist: items.length ? items[playlistIndexForDay(dayNumberValue, items.length)] : null,
          streak: progress.streak,
          bonusToday: progress.bonusToday,
          siteOrigin: config.siteOrigin,
        });
        const failures = await ctx.sendNotification(db, account.id, text);
        for (const failure of failures) log.error?.('[daily] reminder failed:', failure);
        // Marked as sent even when one channel failed, so a broken link does
        // not turn into a message every minute on the other one.
        markSent();
      }
    } catch (error) {
      log.error?.('[daily] reminder skipped:', error?.message ?? error);
    } finally {
      running = false;
    }
  }

  const timer = setInterval(tick, 60_000);
  timer.unref();
  tick();
  return { stop: () => clearInterval(timer), config, tick };
}

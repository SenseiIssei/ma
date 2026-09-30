import { dailyProgress } from './daily.js';
import { berlinDayKey, berlinMinuteOfDay, unitIndexForDay } from './dailyStreak.js';

// Once a day, at DAILY_REMINDER_TIME Berlin time, a short note with the
// lesson of the day goes to Discord as a direct message and to Telegram.
// Either channel is off until its token is set. The lesson and the playlist
// come from the files the website publishes, so the content has exactly one
// home. When the lesson is already done, nothing is sent.

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
    discordBotToken: env.DISCORD_BOT_TOKEN || '',
    discordUserId: env.DISCORD_USER_ID || '',
    telegramBotToken: env.TELEGRAM_BOT_TOKEN || '',
    telegramChatId: env.TELEGRAM_CHAT_ID || '',
  };
}

async function fetchJson(url, options = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const response = await fetch(url, { ...options, signal: controller.signal });
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

export function startDailyReminders({ ctx, env = process.env, log = console }) {
  const config = reminderConfig(env);
  const discordOn = Boolean(config.discordBotToken && config.discordUserId);
  const telegramOn = Boolean(config.telegramBotToken && config.telegramChatId);
  if (!discordOn && !telegramOn) return { stop() {}, config };

  let cache = { at: 0, curriculum: null, playlists: null };
  async function content() {
    if (Date.now() - cache.at < CONTENT_CACHE_MS && cache.curriculum) return cache;
    const [curriculum, playlists] = await Promise.all([
      fetchJson(`${config.siteOrigin}/daily/curriculum.json`),
      fetchJson(`${config.siteOrigin}/daily/playlists.json`).catch(() => null),
    ]);
    cache = { at: Date.now(), curriculum, playlists };
    return cache;
  }

  async function sendDiscord(text) {
    const headers = { Authorization: `Bot ${config.discordBotToken}`, 'Content-Type': 'application/json' };
    const channel = await fetchJson('https://discord.com/api/v10/users/@me/channels', {
      method: 'POST',
      headers,
      body: JSON.stringify({ recipient_id: config.discordUserId }),
    });
    await fetchJson(`https://discord.com/api/v10/channels/${channel.id}/messages`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ content: text.slice(0, 1900) }),
    });
  }

  async function sendTelegram(text) {
    await fetchJson(`https://api.telegram.org/bot${config.telegramBotToken}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: config.telegramChatId, text: text.slice(0, 4000) }),
    });
  }

  let running = false;
  async function tick() {
    if (running) return;
    const now = ctx.now();
    const todayDayKey = berlinDayKey(now);
    if (berlinMinuteOfDay(now) < config.minuteOfDay) return;
    const { db } = ctx;
    if (db.prepare('SELECT 1 FROM daily_reminders_sent WHERE day_key = ?').get(todayDayKey)) return;
    running = true;
    try {
      // The owner is whoever linked a browser most recently.
      const owner = db.prepare('SELECT member_id FROM daily_links ORDER BY last_used_at DESC LIMIT 1').get();
      const progress = owner ? dailyProgress(db, owner.member_id, now) : null;
      if (progress?.today?.status === 'done') {
        db.prepare('INSERT OR IGNORE INTO daily_reminders_sent (day_key, sent_at) VALUES (?, ?)').run(todayDayKey, now);
        return;
      }
      const { curriculum, playlists } = await content();
      const units = allUnits(curriculum);
      const index = unitIndexForDay(todayDayKey, units.length);
      if (index < 0) return;
      const items = playlists?.items ?? [];
      const dayNumberValue = Math.round(Date.parse(`${todayDayKey}T00:00:00Z`) / 86_400_000);
      const playlist = items.length ? items[playlistIndexForDay(dayNumberValue, items.length)] : null;
      const text = reminderText({
        unit: units[index],
        unitNumber: index + 1,
        unitCount: units.length,
        playlist,
        streak: progress?.streak ?? 0,
        bonusToday: progress?.bonusToday ?? 0,
        siteOrigin: config.siteOrigin,
      });
      const results = await Promise.allSettled([
        discordOn ? sendDiscord(text) : Promise.resolve(),
        telegramOn ? sendTelegram(text) : Promise.resolve(),
      ]);
      for (const result of results) {
        if (result.status === 'rejected') log.error?.('[daily] reminder failed:', result.reason?.message ?? result.reason);
      }
      // Marked as sent even when one channel failed, so a broken token does
      // not turn into a message every minute on the other one.
      db.prepare('INSERT OR IGNORE INTO daily_reminders_sent (day_key, sent_at) VALUES (?, ?)').run(todayDayKey, now);
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

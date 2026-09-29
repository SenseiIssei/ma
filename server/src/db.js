import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';

// One SQLite file. Every statement below uses "?" placeholders; no value
// ever gets spliced into SQL text.

const SCHEMA = `
CREATE TABLE IF NOT EXISTS members (
  id          TEXT PRIMARY KEY,
  secret_hash TEXT NOT NULL,
  nickname    TEXT NOT NULL,
  avatar      TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS circles (
  id             TEXT PRIMARY KEY,
  name           TEXT NOT NULL,
  creator_id     TEXT NOT NULL REFERENCES members(id),
  invite_code    TEXT NOT NULL UNIQUE,
  challenge_kind TEXT,
  created_at     INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS circle_members (
  circle_id TEXT NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  member_id TEXT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  joined_at INTEGER NOT NULL,
  PRIMARY KEY (circle_id, member_id)
);
CREATE INDEX IF NOT EXISTS circle_members_by_member ON circle_members(member_id);

CREATE TABLE IF NOT EXISTS stats (
  member_id       TEXT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  date            TEXT NOT NULL,
  streak_days     INTEGER NOT NULL,
  focus_minutes   INTEGER NOT NULL,
  pomodoros       INTEGER NOT NULL,
  resisted        INTEGER NOT NULL,
  correct_answers INTEGER NOT NULL,
  habits_done     INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  PRIMARY KEY (member_id, date)
);
CREATE INDEX IF NOT EXISTS stats_by_date ON stats(date);

CREATE TABLE IF NOT EXISTS gallery_submissions (
  id         TEXT PRIMARY KEY,
  deck_json  TEXT NOT NULL,
  title      TEXT NOT NULL,
  card_count INTEGER NOT NULL,
  status     TEXT NOT NULL DEFAULT 'pending',
  created_at INTEGER NOT NULL
);
`;

export function openDatabase(dataDir) {
  let file = ':memory:';
  if (dataDir !== ':memory:') {
    mkdirSync(dataDir, { recursive: true });
    file = join(dataDir, 'friends.sqlite');
  }
  const db = new DatabaseSync(file, { enableForeignKeyConstraints: true });
  // WAL lets the health check read while a write is running; busy_timeout
  // covers the rare moment a checkpoint holds the lock.
  if (file !== ':memory:') db.exec('PRAGMA journal_mode = WAL');
  db.exec('PRAGMA foreign_keys = ON');
  db.exec('PRAGMA busy_timeout = 3000');
  db.exec(SCHEMA);
  return db;
}

/** Runs fn inside one transaction; any throw rolls the whole thing back. */
export function transaction(db, fn) {
  db.exec('BEGIN IMMEDIATE');
  try {
    const result = fn();
    db.exec('COMMIT');
    return result;
  } catch (err) {
    db.exec('ROLLBACK');
    throw err;
  }
}

ALTER TABLE channel_limits ADD COLUMN last_cycle_reset_at TEXT;
ALTER TABLE channel_limits ADD COLUMN last_day_reset_at TEXT;
ALTER TABLE channel_limits ADD COLUMN last_hour_reset_at TEXT;

CREATE TABLE IF NOT EXISTS invite_codes (
  code TEXT PRIMARY KEY,
  enabled INTEGER NOT NULL DEFAULT 1,
  max_uses INTEGER,
  used_count INTEGER NOT NULL DEFAULT 0,
  created_by INTEGER REFERENCES users(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT OR IGNORE INTO system_settings(key, value) VALUES
  ('invite_code_default', 'TOKENALTAR');

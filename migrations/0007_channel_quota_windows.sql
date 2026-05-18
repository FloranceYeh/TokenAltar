PRAGMA foreign_keys = OFF;

CREATE TABLE IF NOT EXISTS channel_limits_new (
  channel_id INTEGER PRIMARY KEY REFERENCES channels(id) ON DELETE CASCADE,
  fire_sale_days_before INTEGER NOT NULL DEFAULT 3,
  fire_sale_remaining_pct REAL NOT NULL DEFAULT 0.25,
  fire_sale_discount REAL NOT NULL DEFAULT 0.2,
  provider_share REAL NOT NULL DEFAULT 0.7,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO channel_limits_new(
  channel_id, fire_sale_days_before, fire_sale_remaining_pct,
  fire_sale_discount, provider_share, updated_at
)
SELECT
  channel_id, fire_sale_days_before, fire_sale_remaining_pct,
  fire_sale_discount, provider_share, updated_at
FROM channel_limits;

CREATE TABLE IF NOT EXISTS channel_quota_windows (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel_id INTEGER NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  limit_tokens INTEGER NOT NULL CHECK (limit_tokens > 0),
  used_tokens INTEGER NOT NULL DEFAULT 0,
  period_unit TEXT NOT NULL CHECK (period_unit IN ('minute', 'hour', 'day', 'week', 'month', 'year')),
  period_count INTEGER NOT NULL CHECK (period_count > 0),
  anchor_at TEXT NOT NULL,
  timezone TEXT NOT NULL,
  current_window_start_at TEXT NOT NULL,
  current_window_end_at TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO channel_quota_windows(
  channel_id, name, limit_tokens, used_tokens, period_unit, period_count,
  anchor_at, timezone, current_window_start_at, current_window_end_at, sort_order
)
SELECT
  channel_id, 'Monthly', cycle_limit_tokens, used_cycle_tokens, 'month', 1,
  printf('%s-%s-01T00:00:00', strftime('%Y', 'now'), strftime('%m', 'now')), 'UTC',
  strftime('%Y-%m-01T00:00:00Z', 'now'),
  strftime('%Y-%m-01T00:00:00Z', 'now', '+1 month'),
  0
FROM channel_limits;

INSERT INTO channel_quota_windows(
  channel_id, name, limit_tokens, used_tokens, period_unit, period_count,
  anchor_at, timezone, current_window_start_at, current_window_end_at, sort_order
)
SELECT
  channel_id, 'Daily', daily_limit_tokens, used_day_tokens, 'day', 1,
  printf('%sT00:00:00', date('now')), 'UTC',
  strftime('%Y-%m-%dT00:00:00Z', 'now'),
  strftime('%Y-%m-%dT00:00:00Z', 'now', '+1 day'),
  1
FROM channel_limits;

INSERT INTO channel_quota_windows(
  channel_id, name, limit_tokens, used_tokens, period_unit, period_count,
  anchor_at, timezone, current_window_start_at, current_window_end_at, sort_order
)
SELECT
  channel_id, 'Hourly', hourly_limit_tokens, used_hour_tokens, 'hour', 1,
  printf('%s:00:00', strftime('%Y-%m-%dT%H', 'now')), 'UTC',
  strftime('%Y-%m-%dT%H:00:00Z', 'now'),
  strftime('%Y-%m-%dT%H:00:00Z', 'now', '+1 hour'),
  2
FROM channel_limits;

DROP TABLE channel_limits;

ALTER TABLE channel_limits_new RENAME TO channel_limits;

CREATE INDEX IF NOT EXISTS idx_channel_quota_windows_channel
  ON channel_quota_windows(channel_id, sort_order, id);

PRAGMA foreign_keys = ON;

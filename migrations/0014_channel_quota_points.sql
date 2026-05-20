PRAGMA foreign_keys = OFF;

DROP INDEX IF EXISTS idx_channel_quota_windows_channel;

CREATE TABLE channel_quota_windows_points (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel_id INTEGER NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  limit_points REAL NOT NULL CHECK (limit_points > 0),
  used_points REAL NOT NULL DEFAULT 0,
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

WITH conversion AS (
  SELECT COALESCE(
    (SELECT NULLIF(CAST(value AS REAL), 0.0) FROM system_settings WHERE key = 'fallback_input_price_per_unit'),
    5.0
  ) / COALESCE(
    (SELECT NULLIF(CAST(value AS REAL), 0.0) FROM system_settings WHERE key = 'pricing_unit_tokens'),
    1000000.0
  ) AS points_per_token
)
INSERT INTO channel_quota_windows_points(
  id, channel_id, name, limit_points, used_points, period_unit, period_count,
  anchor_at, timezone, current_window_start_at, current_window_end_at,
  sort_order, created_at, updated_at
)
SELECT
  id,
  channel_id,
  name,
  MAX(limit_tokens * (SELECT points_per_token FROM conversion), 0.0001),
  MAX(used_tokens * (SELECT points_per_token FROM conversion), 0.0),
  period_unit,
  period_count,
  anchor_at,
  timezone,
  current_window_start_at,
  current_window_end_at,
  sort_order,
  created_at,
  updated_at
FROM channel_quota_windows;

DROP TABLE channel_quota_windows;
ALTER TABLE channel_quota_windows_points RENAME TO channel_quota_windows;

CREATE INDEX IF NOT EXISTS idx_channel_quota_windows_channel
  ON channel_quota_windows(channel_id, sort_order, id);

UPDATE system_settings
SET value = '[{"name":"Monthly","limit_points":5,"period_unit":"month","period_count":1,"timezone":"UTC"},{"name":"Daily","limit_points":1,"period_unit":"day","period_count":1,"timezone":"UTC"},{"name":"Hourly","limit_points":0.25,"period_unit":"hour","period_count":1,"timezone":"UTC"}]',
    updated_at = datetime('now')
WHERE key = 'default_channel_windows_json'
  AND value = '[{"name":"Monthly","limit_tokens":1000000,"period_unit":"month","period_count":1,"timezone":"UTC"},{"name":"Daily","limit_tokens":200000,"period_unit":"day","period_count":1,"timezone":"UTC"},{"name":"Hourly","limit_tokens":50000,"period_unit":"hour","period_count":1,"timezone":"UTC"}]';

PRAGMA foreign_keys = ON;

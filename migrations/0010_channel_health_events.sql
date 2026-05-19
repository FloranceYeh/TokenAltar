CREATE TABLE IF NOT EXISTS channel_health_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel_id INTEGER NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  request_id TEXT,
  status TEXT NOT NULL CHECK (status IN ('available', 'empty', 'degraded', 'down')),
  http_status INTEGER,
  ttft_ms INTEGER,
  total_latency_ms INTEGER,
  error TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_channel_health_events_channel
  ON channel_health_events(channel_id, id DESC);

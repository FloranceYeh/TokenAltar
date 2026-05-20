PRAGMA foreign_keys = OFF;

DROP INDEX IF EXISTS idx_model_prices_global_pattern;
DROP INDEX IF EXISTS idx_model_prices_channel;

CREATE TABLE model_prices_one_million (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel_id INTEGER REFERENCES channels(id) ON DELETE CASCADE,
  model_pattern TEXT NOT NULL,
  input_price_per_1m REAL NOT NULL,
  output_price_per_1m REAL NOT NULL,
  cache_price_per_1m REAL NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(channel_id, model_pattern)
);

WITH old_unit AS (
  SELECT COALESCE(
    (SELECT NULLIF(CAST(value AS REAL), 0.0) FROM system_settings WHERE key = 'pricing_unit_tokens'),
    1000.0
  ) AS tokens
)
INSERT INTO model_prices_one_million(
  id, channel_id, model_pattern, input_price_per_1m, output_price_per_1m, cache_price_per_1m, created_at
)
SELECT
  id,
  channel_id,
  model_pattern,
  CASE
    WHEN channel_id IS NULL
      AND model_pattern = 'default'
      AND input_price_per_1k = 1.0
      AND output_price_per_1k = 3.0
      AND cache_price_per_1k = 0.2
    THEN 5.0
    ELSE input_price_per_1k * (1000000.0 / (SELECT tokens FROM old_unit))
  END,
  CASE
    WHEN channel_id IS NULL
      AND model_pattern = 'default'
      AND input_price_per_1k = 1.0
      AND output_price_per_1k = 3.0
      AND cache_price_per_1k = 0.2
    THEN 30.0
    ELSE output_price_per_1k * (1000000.0 / (SELECT tokens FROM old_unit))
  END,
  CASE
    WHEN channel_id IS NULL
      AND model_pattern = 'default'
      AND input_price_per_1k = 1.0
      AND output_price_per_1k = 3.0
      AND cache_price_per_1k = 0.2
    THEN 0.5
    ELSE cache_price_per_1k * (1000000.0 / (SELECT tokens FROM old_unit))
  END,
  created_at
FROM model_prices;

DROP TABLE model_prices;
ALTER TABLE model_prices_one_million RENAME TO model_prices;

CREATE UNIQUE INDEX IF NOT EXISTS idx_model_prices_global_pattern
  ON model_prices(model_pattern)
  WHERE channel_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_model_prices_channel
  ON model_prices(channel_id, model_pattern);

CREATE TABLE ledger_entries_one_million (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  request_id TEXT NOT NULL UNIQUE,
  user_id INTEGER NOT NULL REFERENCES users(id),
  api_key_id INTEGER NOT NULL REFERENCES api_keys(id),
  channel_id INTEGER NOT NULL REFERENCES channels(id),
  provider_user_id INTEGER NOT NULL REFERENCES users(id),
  model TEXT NOT NULL,
  tokenizer TEXT NOT NULL,
  input_tokens INTEGER NOT NULL,
  output_tokens INTEGER NOT NULL,
  cache_tokens INTEGER NOT NULL,
  input_price_per_1m REAL NOT NULL,
  output_price_per_1m REAL NOT NULL,
  cache_price_per_1m REAL NOT NULL,
  surge_multiplier REAL NOT NULL,
  fire_sale_discount REAL NOT NULL,
  total_points REAL NOT NULL,
  provider_points REAL NOT NULL,
  status TEXT NOT NULL,
  formula_note TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

WITH old_unit AS (
  SELECT COALESCE(
    (SELECT NULLIF(CAST(value AS REAL), 0.0) FROM system_settings WHERE key = 'pricing_unit_tokens'),
    1000.0
  ) AS tokens
)
INSERT INTO ledger_entries_one_million(
  id, request_id, user_id, api_key_id, channel_id, provider_user_id, model, tokenizer,
  input_tokens, output_tokens, cache_tokens, input_price_per_1m, output_price_per_1m,
  cache_price_per_1m, surge_multiplier, fire_sale_discount, total_points,
  provider_points, status, formula_note, created_at
)
SELECT
  id,
  request_id,
  user_id,
  api_key_id,
  channel_id,
  provider_user_id,
  model,
  tokenizer,
  input_tokens,
  output_tokens,
  cache_tokens,
  input_price_per_1k * (1000000.0 / (SELECT tokens FROM old_unit)),
  output_price_per_1k * (1000000.0 / (SELECT tokens FROM old_unit)),
  cache_price_per_1k * (1000000.0 / (SELECT tokens FROM old_unit)),
  surge_multiplier,
  fire_sale_discount,
  total_points,
  provider_points,
  status,
  printf(
    'input %d * %.4f/1M tokens + cache %d * %.4f/1M tokens + output %d * %.4f/1M tokens, surge %.2fx, fire sale %.2fx',
    input_tokens,
    input_price_per_1k * (1000000.0 / (SELECT tokens FROM old_unit)),
    cache_tokens,
    cache_price_per_1k * (1000000.0 / (SELECT tokens FROM old_unit)),
    output_tokens,
    output_price_per_1k * (1000000.0 / (SELECT tokens FROM old_unit)),
    surge_multiplier,
    fire_sale_discount
  ),
  created_at
FROM ledger_entries;

DROP TABLE ledger_entries;
ALTER TABLE ledger_entries_one_million RENAME TO ledger_entries;

CREATE INDEX IF NOT EXISTS idx_ledger_provider_month ON ledger_entries(provider_user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_ledger_consumer_month ON ledger_entries(user_id, created_at);

WITH old_unit AS (
  SELECT COALESCE(
    (SELECT NULLIF(CAST(value AS REAL), 0.0) FROM system_settings WHERE key = 'pricing_unit_tokens'),
    1000.0
  ) AS tokens
)
UPDATE system_settings
SET value = CASE
  WHEN key = 'fallback_input_price_per_unit' AND CAST(value AS REAL) = 1.0 THEN '5.0'
  WHEN key = 'fallback_output_price_per_unit' AND CAST(value AS REAL) = 3.0 THEN '30.0'
  WHEN key = 'fallback_cache_price_per_unit' AND CAST(value AS REAL) = 0.2 THEN '0.5'
  ELSE CAST(CAST(value AS REAL) * (1000000.0 / (SELECT tokens FROM old_unit)) AS TEXT)
END,
updated_at = datetime('now')
WHERE key IN (
  'fallback_input_price_per_unit',
  'fallback_output_price_per_unit',
  'fallback_cache_price_per_unit'
);

INSERT OR IGNORE INTO system_settings(key, value) VALUES ('pricing_unit_tokens', '1000000');
UPDATE system_settings
SET value = '1000000', updated_at = datetime('now')
WHERE key = 'pricing_unit_tokens';

INSERT OR IGNORE INTO model_prices(
  channel_id, model_pattern, input_price_per_1m, output_price_per_1m, cache_price_per_1m
) VALUES
  (NULL, '^gpt-5\.5$', 5.0, 30.0, 0.5),
  (NULL, '^gpt-5\.4$', 2.5, 15.0, 0.25),
  (NULL, '^gpt-5\.3-codex$', 2.5, 15.0, 0.25),
  (NULL, '^gpt-5\.2$', 2.5, 15.0, 0.25),
  (NULL, '^gpt-5\.2-codex$', 2.5, 15.0, 0.25),
  (NULL, '^claude-opus-4[.-]7(-.+)?$', 5.0, 25.0, 0.5),
  (NULL, '^claude-opus-4[.-]6(-.+)?$', 5.0, 25.0, 0.5),
  (NULL, '^claude-opus-4[.-]5(-.+)?$', 5.0, 25.0, 0.5),
  (NULL, '^claude-opus-4[.-]1(-.+)?$', 15.0, 75.0, 1.5),
  (NULL, '^claude-opus-4(-.+)?$', 15.0, 75.0, 1.5),
  (NULL, '^claude-sonnet-4[.-]6(-.+)?$', 3.0, 15.0, 0.3),
  (NULL, '^claude-sonnet-4[.-]5(-.+)?$', 3.0, 15.0, 0.3),
  (NULL, '^claude-sonnet-4(-.+)?$', 3.0, 15.0, 0.3),
  (NULL, '^claude-haiku-4[.-]5(-.+)?$', 1.0, 5.0, 0.1);

PRAGMA foreign_keys = ON;

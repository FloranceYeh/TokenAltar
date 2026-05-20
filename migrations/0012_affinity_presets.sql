ALTER TABLE affinity_rules ADD COLUMN include_model_name INTEGER NOT NULL DEFAULT 1;

INSERT OR IGNORE INTO affinity_rules(
  name, enabled, model_regex, request_path, user_agent_regex, key_source_type,
  key_source_path, group_name, ttl_seconds, skip_retry_on_failure, switch_on_success,
  include_model_name
) VALUES
  (
    'gpt prompt cache',
    1,
    '^gpt-.*$',
    '/v1/responses',
    NULL,
    'json_path',
    'prompt_cache_key',
    'default',
    3600,
    1,
    1,
    0
  ),
  (
    'claude metadata user',
    1,
    '^claude-.*$',
    '/v1/messages',
    NULL,
    'json_path',
    'metadata.user_id',
    'default',
    3600,
    1,
    1,
    0
  ),
  (
    'gemini cached content',
    1,
    '^gemini-.*$',
    '/v1beta/models/:generateContent',
    NULL,
    'json_path',
    'cachedContent',
    'default',
    3600,
    1,
    1,
    0
  ),
  (
    'gemini cached content stream',
    1,
    '^gemini-.*$',
    '/v1beta/models/:streamGenerateContent',
    NULL,
    'json_path',
    'cachedContent',
    'default',
    3600,
    1,
    1,
    0
  );

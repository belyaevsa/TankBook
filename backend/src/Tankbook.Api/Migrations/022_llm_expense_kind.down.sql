-- Reverses migration 022 (the expense extraction kind).
-- Deletes ONLY the row this migration inserted, matched on its exact kind and
-- model id. A blanket `DELETE FROM llm_settings` would also throw away
-- corrections written directly to the database since - which is how these
-- tables are meant to be maintained (RV.34: direct DB write, no admin
-- endpoint), so later rows are the normal case, not the exception.
DELETE FROM llm_settings
WHERE kind = 'expense'
  AND model_id = 'deepseek-v4-flash-vision-exp';

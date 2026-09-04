-- Reverses migration 018 (the LLM dictionary and settings baseline).
--
-- Deletes ONLY the rows this migration inserted, matched on their exact
-- (model_id, effective_from) and kind. A blanket `DELETE FROM llm_models` would
-- also throw away price corrections written directly to the database since -
-- which is how these tables are meant to be maintained (RV.34: direct DB write,
-- no admin endpoint), so later rows are the normal case, not the exception.
DELETE FROM llm_settings
WHERE kind IN ('receipt', 'pump', 'chargeScreenshot', 'invoice')
  AND model_id = 'deepseek-v4-flash-vision-exp';

DELETE FROM llm_models
WHERE effective_from = DATE '2026-08-16'
  AND model_id IN ('deepseek-v4-flash-vision-exp', 'deepseek-v4-flash', 'deepseek-v4-pro');

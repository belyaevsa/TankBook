-- Tankbook backend, migration 010 rollback: drop the tier column.
ALTER TABLE accounts DROP COLUMN IF EXISTS llm_tier;

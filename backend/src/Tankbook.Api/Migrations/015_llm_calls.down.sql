-- Tankbook backend, migration 015 rollback: drop the call ledger. The spend
-- history is discarded - it is a record, not a source of truth, so a rollback
-- loses observability rather than user data.
DROP TABLE llm_calls;

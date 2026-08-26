-- Tankbook backend, migration 007 rollback: drop the purge-scan index.
DROP INDEX IF EXISTS idx_accounts_deleted_at;

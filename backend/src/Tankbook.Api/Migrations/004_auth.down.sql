-- Tankbook backend, migration 004 rollback: drop the refresh-token table.
DROP TABLE IF EXISTS refresh_tokens;

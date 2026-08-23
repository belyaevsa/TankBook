-- Tankbook backend, migration 003 rollback: drop the remote config table.
DROP TABLE IF EXISTS config_documents;

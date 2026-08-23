-- Tankbook backend, migration 002 rollback: drop the payload contract tables
-- and the records.schema_version column (children before parents).
DROP TABLE IF EXISTS payload_migrations;
DROP TABLE IF EXISTS payload_schemas;
ALTER TABLE records DROP COLUMN IF EXISTS schema_version;

-- Tankbook backend, migration 001 rollback: drop the schema in reverse
-- dependency order (children before parents).
DROP TABLE IF EXISTS feedback;
DROP TABLE IF EXISTS vehicle_catalog;
DROP TABLE IF EXISTS exchange_rates;
DROP TABLE IF EXISTS llm_usage;
DROP TABLE IF EXISTS blobs;
DROP TABLE IF EXISTS account_seq;
DROP TABLE IF EXISTS records;
DROP TABLE IF EXISTS devices;
DROP TABLE IF EXISTS accounts;

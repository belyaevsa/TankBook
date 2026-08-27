-- Tankbook backend, migration 011 rollback: drop the catalog pack-state row.
DROP TABLE IF EXISTS catalog_pack_state;

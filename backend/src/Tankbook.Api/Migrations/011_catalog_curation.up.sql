-- Tankbook backend, migration 011 (vehicle catalog curation).
-- docs/SYNC.md "Reference data", docs/API.md "Vehicle catalog". The catalog's
-- pack_version lives per entry on vehicle_catalog (migrated in 001), so "current
-- version" has no single home and a concurrent publish could mint two packs with
-- the same version. This migration adds the singleton bookkeeping row that IS
-- the current pack version: the publish path claims the next version through it
-- (INSERT ... ON CONFLICT ... WHERE pack_version < EXCLUDED.pack_version, which
-- serializes concurrent publishes on the row lock and refuses a version not
-- greater than the current one), and GET /catalog reads it as the packVersion to
-- serve. Seeded from the existing rows so a table that already holds data keeps
-- its highest version authoritative.

CREATE TABLE catalog_pack_state (
    singleton    int PRIMARY KEY CHECK (singleton = 1),
    pack_version int NOT NULL
);

INSERT INTO catalog_pack_state (singleton, pack_version)
VALUES (1, COALESCE((SELECT max(pack_version) FROM vehicle_catalog), 0));

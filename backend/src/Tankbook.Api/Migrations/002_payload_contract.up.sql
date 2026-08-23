-- Tankbook backend, migration 002 (payload contract).
-- docs/SYNC.md "Payload contract and versioning". The registry lives in the
-- database, not in code: the server validates payload STRUCTURE against these
-- schemas and never reads domain meaning (CLAUDE.md hard rule 9). Adding or
-- evolving an entity is a data change (a new canonical schema file embedded at
-- build time + a migration), never a per-entity code change.

-- Registered JSON Schemas per (entity_type, schema_version). Payloads are
-- validated against the schema for their (entity_type, schema_version) on push.
CREATE TABLE payload_schemas (
    entity_type    text NOT NULL,
    schema_version int  NOT NULL,
    json_schema    jsonb NOT NULL,
    PRIMARY KEY (entity_type, schema_version)
);

-- Declarative, ordered payload migrations for the server-side backfill job
-- (docs/SYNC.md "Migrating payloads"). transform holds an ordered list of
-- mechanical JSON-surgery operations (rename / addDefault / wrap /
-- removeDeprecated); the server never learns what a field means.
CREATE TABLE payload_migrations (
    entity_type  text NOT NULL,
    from_version int  NOT NULL,
    to_version   int  NOT NULL,
    transform    jsonb NOT NULL,
    PRIMARY KEY (entity_type, from_version)
);

-- The payload contract version rides as a column (not inside the JSON) so the
-- server can filter and migrate without parsing domain content. Existing
-- records predate the contract and are already v1, hence DEFAULT 1.
ALTER TABLE records ADD COLUMN schema_version int NOT NULL DEFAULT 1;

-- Seed the registry from the canonical schemas (docs/schemas/v1/*.schema.json),
-- embedded as resources at build time. The marker below is replaced by the
-- PayloadSchemaSeeder with idempotent INSERT ... ON CONFLICT DO NOTHING
-- statements, so applying this migration is what populates the registry.
{{PAYLOAD_SCHEMAS_SEED}}

-- Tankbook backend, migration 001 (initial schema).
-- Table and column names are canonical per docs/SYNC.md ("Server data model")
-- and docs/SCHEMA.md ("Reference data" / "Feedback intake"). The server stores
-- opaque records, never domain tables; payloads travel as JSONB.

-- Accounts: one row per signed-in identity. apple_sub/google_sub are unique and
-- nullable (an account has at most one of each; sign-in IS registration).
CREATE TABLE accounts (
    id          uuid PRIMARY KEY,
    apple_sub   text UNIQUE,
    google_sub  text UNIQUE,
    email       text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    deleted_at  timestamptz
);

-- Devices registered per account; revoking one never touches records (a device
-- row carries only the sync cursor + push channel). last_pull_scn is the
-- device's pull cursor, zeroed for a fresh install (pull from 0 IS restore).
CREATE TABLE devices (
    id             uuid PRIMARY KEY,
    account_id     uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    name           text NOT NULL,
    platform       text NOT NULL,
    last_pull_scn  bigint NOT NULL DEFAULT 0,
    last_seen_at   timestamptz NOT NULL DEFAULT now(),
    push_token     text
);

CREATE INDEX idx_devices_account_id ON devices (account_id);

-- The account's record stream. The server never interprets entity_type or
-- payload (docs/SYNC.md forward-compatibility rule); scn is assigned on write
-- from account_seq (strictly monotonic per account).
CREATE TABLE records (
    account_id        uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    id                uuid NOT NULL,
    entity_type       text NOT NULL,
    scn               bigint NOT NULL,
    payload           jsonb NOT NULL,
    client_updated_at timestamptz NOT NULL,
    deleted           boolean NOT NULL DEFAULT false,
    origin_device     uuid REFERENCES devices (id) ON DELETE SET NULL,
    PRIMARY KEY (account_id, id)
);

-- Pull is WHERE account_id = ? AND scn > ? ORDER BY scn (docs/SYNC.md); the
-- (account_id, scn) index serves both the filter and the ordering.
CREATE INDEX idx_records_account_scn ON records (account_id, scn);

-- Per-account SCN allocator, bumped in the same transaction as the record
-- write. Concurrency-safe via the upsert's row lock in ScnAllocator.
CREATE TABLE account_seq (
    account_id uuid PRIMARY KEY REFERENCES accounts (id) ON DELETE CASCADE,
    next_scn   bigint NOT NULL DEFAULT 1
);

-- Content-addressed attachment index; the bytes live in S3-compatible storage.
-- PRIMARY KEY (account_id, sha256) also covers per-account prefix purges.
CREATE TABLE blobs (
    account_id  uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    sha256      text NOT NULL,
    size_bytes  bigint NOT NULL,
    storage_ref text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (account_id, sha256)
);

-- Metered LLM gateway usage, one row per account per period.
CREATE TABLE llm_usage (
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    period     date NOT NULL,
    requests   integer NOT NULL DEFAULT 0,
    tokens     bigint NOT NULL DEFAULT 0,
    PRIMARY KEY (account_id, period)
);

-- Public, read-only exchange-rate cache (docs/SCHEMA.md "Reference data").
-- base/quote are char(3) ISO 4217 codes; rows are append-only.
CREATE TABLE exchange_rates (
    date       date NOT NULL,
    base       char(3) NOT NULL,
    quote      char(3) NOT NULL,
    rate       numeric(18,8) NOT NULL,
    source     text NOT NULL,
    fetched_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (date, base, quote)
);

-- Vehicle dictionary backing Add-car pre-fill (docs/SCHEMA.md). No vehicle
-- ever references a catalog row by id; corrections never mutate user garages.
CREATE TABLE vehicle_catalog (
    id                   uuid PRIMARY KEY,
    make                 text NOT NULL,
    model                text NOT NULL,
    generation           text,
    years                int4range,
    powertrain           text NOT NULL,
    fuel_kinds           text[] NOT NULL,
    tank_capacity_l      numeric,
    battery_capacity_kwh numeric,
    pack_version         integer NOT NULL DEFAULT 1
);

-- Catalog pulls are versioned deltas: WHERE pack_version > ? (docs/SCHEMA.md).
CREATE INDEX idx_vehicle_catalog_pack_version ON vehicle_catalog (pack_version);

-- Feedback intake (docs/SCHEMA.md); account_id is nullable (no-account users
-- can complain too). Cascade on account deletion honors the signed-off
-- delete-account-deletes-everything stance (docs/SYNC.md).
CREATE TABLE feedback (
    id         uuid PRIMARY KEY,
    account_id uuid REFERENCES accounts (id) ON DELETE CASCADE,
    category   text NOT NULL,
    text       text NOT NULL,
    meta       jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Import parse index (docs/SECURITY.md "Import files at rest", docs/API.md
-- "Import parsing"). One row per stored parse: the uploaded file and its result
-- live in blob storage (file_key / result_key), and this row is the metadata
-- index that lets the 30-day purge enumerate what to drop without ever reading
-- a payload (hard rule 12: only shape is held here - format, file kind, counts).
CREATE TABLE import_parses (
    id               uuid PRIMARY KEY,
    -- NULL when the parse ran signed out: the file is then owned by the device
    -- that uploaded it (device_id), and access is by the importId capability.
    account_id       uuid,
    device_id        uuid NOT NULL,
    format           text NOT NULL,
    file_kind        text NOT NULL,
    file_key         text NOT NULL,
    result_key       text NOT NULL,
    rows_read        integer NOT NULL,
    candidate_count  integer NOT NULL,
    unparsed_count   integer NOT NULL,
    created_at       timestamptz NOT NULL DEFAULT now()
);

-- The purge job scans on created_at (both sides of the 30-day cutoff).
CREATE INDEX idx_import_parses_created_at ON import_parses (created_at);

-- Account deletion purges the account's imports too (docs/SECURITY.md).
CREATE INDEX idx_import_parses_account ON import_parses (account_id);

-- Debug cases (hard rule 9's debug-cases amendment, docs/SECURITY.md "Debug
-- cases", docs/API.md "Debug cases"). One row per case the user chose to send:
-- the parts (log, photos, traces) live in blob storage under the owner's
-- prefix, and this row is the index the 30-day purge, the account purge and
-- the admin viewer's lookup-by-id use. The server never reads a part (hard
-- rule 9); the row holds only the envelope - names, content types, sizes.
CREATE TABLE debug_cases (
    id           text PRIMARY KEY,
    -- NULL when sent signed out: the case is then owned by the device.
    account_id   uuid,
    device_id    uuid NOT NULL,
    app          text,
    parts        jsonb NOT NULL,
    total_bytes  bigint NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);

-- The purge job scans on created_at (both sides of the 30-day cutoff).
CREATE INDEX idx_debug_cases_created_at ON debug_cases (created_at);

-- Account deletion purges the account's cases too.
CREATE INDEX idx_debug_cases_account ON debug_cases (account_id);

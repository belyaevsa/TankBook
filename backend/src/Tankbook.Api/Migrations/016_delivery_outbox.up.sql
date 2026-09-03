-- Tankbook backend, migration 016 (the per-device delivery outbox, RV.44).
-- docs/SECURITY.md "The delivery outbox", CLAUDE.md hard rule 9 amendment
-- (2026-09-04). When the gateway computed an answer but could not hand it back -
-- the client vanished mid-request, which production shows as nginx 499 - the
-- result is queued here for the device that asked for it, and deleted once
-- collected.
--
-- The row is OPAQUE BYTES addressed to a device. The server never reads a field
-- of `payload`, never queries by meaning, and exposes no search or stats over
-- it - it is the same shape as GET /blobs/{sha256}: retrieve-what-you-are-
-- entitled-to. That is what keeps this from becoming a read endpoint over
-- llm_calls, which rule 9's ledger amendment explicitly forbids ("written by
-- the gateway and read by no endpoint").
--
-- Requires an account (so does /extract): a guest never has an outbox.
-- account_id carries a foreign key with ON DELETE CASCADE, because unlike the
-- call ledger the outbox does NOT survive account deletion - it is purged with
-- every other content store (docs/SECURITY.md "Deleting the account deletes
-- these too"). The AccountPurgeService also purges it explicitly (belt and
-- braces), and that explicit purge is what the L2 test asserts.
--
-- Retention is 30 days, the one number that already governs the tombstone/undo
-- window, /import/parse's file and the call ledger's content. The purge job
-- scans created_at.
CREATE TABLE delivery_outbox (
    id         uuid PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    device_id  uuid NOT NULL,
    payload    bytea NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- The 30-day retention purge scans on created_at (both sides of the cutoff).
CREATE INDEX idx_delivery_outbox_created_at ON delivery_outbox (created_at);

-- Account deletion purges the account's outbox too (docs/SECURITY.md).
CREATE INDEX idx_delivery_outbox_account ON delivery_outbox (account_id);

-- Drain is WHERE account_id = ? AND device_id = ? (retrieve-what-you-are-
-- entitled-to), so the device pair is indexed together.
CREATE INDEX idx_delivery_outbox_device ON delivery_outbox (account_id, device_id);

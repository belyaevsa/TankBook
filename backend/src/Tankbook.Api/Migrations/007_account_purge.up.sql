-- Tankbook backend, migration 007 (account-deletion grace purge).
-- docs/API.md "Account & devices", docs/SYNC.md "Offline & failure behavior"
-- (the normative sentence): DELETE /account tombstones the account (accounts.
-- deleted_at, already present since 001) and a background job purges records and
-- the blob prefix after a configurable grace period. That job scans
-- "tombstoned accounts past the grace period" on every pass; this partial index
-- makes the scan touch only the (rare) deleted rows instead of the whole
-- accounts table. No column is added - the tombstone column and the device
-- columns this task needs already exist (001/005/006).

CREATE INDEX idx_accounts_deleted_at ON accounts (deleted_at) WHERE deleted_at IS NOT NULL;

-- Tankbook backend, migration 006 rollback: drop the pending-upload table and
-- the sweep index (children before parents).
DROP INDEX IF EXISTS idx_blobs_account_created;
DROP TABLE IF EXISTS blob_pending;

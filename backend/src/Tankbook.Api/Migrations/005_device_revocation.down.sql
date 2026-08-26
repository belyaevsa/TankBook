-- Tankbook backend, migration 005 rollback: drop the revocation marker.
ALTER TABLE devices DROP COLUMN IF EXISTS revoked_at;

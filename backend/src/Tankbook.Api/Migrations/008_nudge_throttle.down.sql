-- Tankbook backend, migration 008 rollback: drop the throttle column.
ALTER TABLE devices DROP COLUMN IF EXISTS last_nudged_at;

-- Reverses migration 027: cases are again stored in the request.

DROP INDEX IF EXISTS idx_debug_cases_pending;
ALTER TABLE debug_cases
    DROP COLUMN IF EXISTS upload_failed_at,
    DROP COLUMN IF EXISTS upload_claimed_at,
    DROP COLUMN IF EXISTS upload_attempts,
    DROP COLUMN IF EXISTS stored_at;

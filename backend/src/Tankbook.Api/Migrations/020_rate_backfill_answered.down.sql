-- Tankbook backend, migration 020 rollback: drop the answered ledger. An
-- answered date simply becomes un-answered, so a device that still needs it asks
-- again and the backfill re-fetches (and re-answers) it - nothing is lost that
-- cannot be recovered.
DROP TABLE rate_backfill_answered;

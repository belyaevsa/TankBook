-- Tankbook backend, migration 013 rollback: drop the backfill queue. Pending
-- demand is discarded - a device that still needs the dates will ask again and
-- re-record them, so nothing is lost that cannot be recovered.
DROP TABLE rate_backfill;

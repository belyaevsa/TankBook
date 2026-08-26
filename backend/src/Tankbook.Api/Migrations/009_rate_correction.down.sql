-- Tankbook backend, migration 009 rollback: restore the 001 primary key and
-- drop the correction-path machinery. The rollback runs on a schema the tests
-- are discarding (no soft-deleted duplicates), so re-adding the composite key is
-- safe; in a real downgrade a database carrying soft-deleted duplicates would
-- need them resolved first, which is outside the migration runner's remit.

DROP INDEX IF EXISTS uq_exchange_rates_active;

ALTER TABLE exchange_rates DROP CONSTRAINT exchange_rates_pkey;
ALTER TABLE exchange_rates DROP COLUMN id;

ALTER TABLE exchange_rates ADD PRIMARY KEY (date, base, quote);

ALTER TABLE exchange_rates DROP COLUMN deleted_at;

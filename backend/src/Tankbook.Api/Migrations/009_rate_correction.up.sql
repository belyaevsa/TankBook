-- Tankbook backend, migration 009 (exchange-rate correction path).
-- docs/SCHEMA.md "Reference data -> Exchange rates": rows are append-only, and
-- the manual correction for a bad feed day is soft-delete + re-fetch. A bare
-- deleted marker is not enough on its own: the corrected re-fetch must insert a
-- row with the same (date, base, quote) as the soft-deleted one, and the 001
-- primary key forbids a second live row for that key. So uniqueness of the live
-- set moves to a partial unique index over non-deleted rows, and the primary key
-- moves to a surrogate identity column. A soft-deleted row stays physically
-- (append-only audit) but frees its (date, base, quote) slot, so a re-fetch
-- inserts a fresh, corrected row without ever mutating the old row's rate.

ALTER TABLE exchange_rates ADD COLUMN deleted_at timestamptz;

ALTER TABLE exchange_rates DROP CONSTRAINT exchange_rates_pkey;
ALTER TABLE exchange_rates ADD COLUMN id bigint GENERATED ALWAYS AS IDENTITY;
ALTER TABLE exchange_rates ADD PRIMARY KEY (id);

CREATE UNIQUE INDEX uq_exchange_rates_active
    ON exchange_rates (date, base, quote)
    WHERE deleted_at IS NULL;

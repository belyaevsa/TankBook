-- Tankbook backend, migration 013 (demand-driven exchange-rate backfill queue).
-- docs/SCHEMA.md "Reference data -> Exchange rates": when GET /rates/pack serves a
-- range that has no rate for some date, the server records that (date, base) here
-- and a background job fetches it from the feeds, so a past date a device needs is
-- filled without blocking the response on up to hundreds of upstream requests.
--
-- The row is the DEMAND, not the answer: it means "a device asked for this date
-- and we did not have it". The backfill deletes the row once it has fetched the
-- date and carried back any remaining gap (or left it honestly absent), so the
-- table holds only work not yet attempted - the resumability that keeps a
-- five-year import from re-fetching itself on every deploy.
CREATE TABLE rate_backfill (
    date       date NOT NULL,
    base       char(3) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (base, date)
);

-- Tankbook backend, migration 020 (answered-state for the demand-driven rate
-- backfill, docs/SCHEMA.md "Reference data -> Exchange rates").
--
-- RV.50: the queue never drained because a date that no feed could fill was
-- settled (deleted) but not recorded ANSWERED, so GET /rates/pack re-enqueued it
-- on every refresh - 50 dates processed every five minutes, forever, publishing
-- nothing. A date answered "nothing published" must be distinguishable from "not
-- yet asked", exactly as RV.32's own row demanded and the carry-back rule was
-- wrongly believed to have dissolved. One row per (base, date, feed) that was
-- asked and returned no document; the queue (rate_backfill) remains "not yet
-- asked".
CREATE TABLE rate_backfill_answered (
    date        date NOT NULL,
    base        char(3) NOT NULL,
    source      text NOT NULL,
    answered_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (base, date, source)
);

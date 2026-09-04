-- Tankbook backend, migration 021 rollback: drop the ledger write queue. A row
-- still queued when this runs is an audit record that had not landed - the same
-- position the product was in before the queue existed. Its call was already
-- metered, so rolling the queue back cannot un-charge it; the give-up outcome
-- (a dropped row and a Warning) is the documented position for a row that never
-- lands, and a rollback is the same position applied to all of them at once.
DROP TABLE llm_ledger_pending;

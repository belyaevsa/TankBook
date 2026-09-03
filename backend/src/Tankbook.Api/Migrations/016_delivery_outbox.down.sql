-- Tankbook backend, migration 016 rollback: drop the delivery outbox. A row
-- still queued when this runs is a suggestion the device never received - the
-- same position the product was in before the outbox existed, so nothing that
-- was guaranteed before is lost.
DROP TABLE delivery_outbox;

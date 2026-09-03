-- Tankbook backend, migration 014 rollback: drop the model dictionary and the
-- per-kind settings table. The compiled ModelId default resumes being the only
-- model choice, and the pricing snapshot (015) goes with the tables it read
-- from - nothing is lost that cannot be re-seeded by direct DB write.
DROP TABLE llm_models;
DROP TABLE llm_settings;

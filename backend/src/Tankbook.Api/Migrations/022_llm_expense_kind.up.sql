-- Tankbook backend, migration 022 (the expense extraction kind, PJ.29).
-- docs/API.md "POST /extract", docs/JOURNEYS.md J7b. Every scanned document
-- reaches the cloud gateway, not only the fill-up receipt: a shop or parking
-- receipt (the Expense-mode capture) is now a kind of its own, so the provider
-- is asked for the fields that document actually carries (total, date, currency,
-- vendor, category) instead of the fuel fields it does not.
--
-- This row is what resolves the model for the kind (migration 014). All kinds
-- that send an IMAGE resolve to the vision model - a text model physically
-- cannot read them - so the row names the same vision model the four 018 kinds
-- do. A later move to a different model for expenses is a single UPDATE, which
-- is why the setting is keyed per kind rather than stored as one scalar.
--
-- Idempotent: ON CONFLICT DO NOTHING, so re-running the migration set on a
-- database that already carries a curated setting changes nothing. Direct DB
-- write remains the way these are updated - there is no admin endpoint (RV.34).
INSERT INTO llm_settings (kind, model_id)
VALUES ('expense', 'deepseek-v4-flash-vision-exp')
ON CONFLICT (kind) DO NOTHING;

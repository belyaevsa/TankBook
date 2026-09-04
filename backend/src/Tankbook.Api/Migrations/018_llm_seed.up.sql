-- Tankbook backend, migration 018 (the LLM dictionary and settings baseline).
-- RV.34 created these tables empty, which left the resolver falling back to the
-- compiled default for every call and - more importantly - left RV.33's cost
-- column at zero, because a cost cannot be computed from pricing that does not
-- exist. This is the baseline that makes the ledger real.
--
-- PRICES ARE THE PUBLISHED OpenRouter RATES for the DeepSeek models, taken from
-- the live https://openrouter.ai/api/v1/models feed on 2026-09-04 (product
-- owner: "take openrouter prices"). They are stored PER TOKEN, which is what
-- llm_models declares and what LlmService multiplies by - OpenRouter publishes
-- per-token already, so nothing is divided by 1M here and no unit conversion
-- can go wrong. For reference, per 1M tokens:
--
--   deepseek-v4-flash-vision-exp   $0.22 in / $0.66 out
--   deepseek-v4-flash              $0.0886 in / $0.1772 out
--   deepseek-v4-pro                $1.0423 in / $2.0845 out
--
-- ONE PRECISION NOTE, because a cost ledger deserves it: input_price is
-- numeric(18,10), so anything below 1e-10 is lost. That bites only the two TEXT
-- models, whose published rates carry more digits (flash input is 0.000000088606
-- and stores as 0.0000000886, a 0.007% understatement). The VISION model - the
-- only one /extract actually calls, because /extract sends an image - is exact
-- at ten places, so the numbers that reach the ledger today are exact. If a
-- future model's rate needs more precision than 1e-10, widen the column rather
-- than rounding the seed and calling it done.
--
-- effective_from is 2026-08-16, the date DeepSeek's current pricing took effect
-- (api-docs.deepseek.com change log). It is NOT today's date: a call recorded
-- against an earlier date must resolve the price that was actually in force, and
-- back-dating the baseline to the deploy date would silently misprice any
-- backfill. A later price change is a NEW row with its own effective_from, never
-- an edit to this one (the append-only rule llm_models was built for).
--
-- Idempotent: ON CONFLICT DO NOTHING, so re-running the migration set on a
-- database that already carries a curated dictionary changes nothing. Direct DB
-- write remains the way these are updated - there is no admin endpoint, by
-- decision (RV.34).

INSERT INTO llm_models
    (model_id, vendor, input_price, output_price, currency, context_window, supports_thinking, effective_from)
VALUES
    -- The vision model: the only one /extract can use, because the prompt IS a
    -- receipt image. Both prices are exact at ten decimal places.
    ('deepseek-v4-flash-vision-exp', 'deepseek', 0.0000002200, 0.0000006600, 'USD', 1048576, false, DATE '2026-08-16'),
    -- The two text models are seeded for the dictionary's own sake: they are
    -- what the [v2] agent turn would call, and having them here means a cost can
    -- be computed the day that lands rather than discovered missing then.
    ('deepseek-v4-flash',            'deepseek', 0.0000000886, 0.0000001772, 'USD', 1048576, true,  DATE '2026-08-16'),
    ('deepseek-v4-pro',              'deepseek', 0.0000010423, 0.0000020845, 'USD', 1048576, true,  DATE '2026-08-16')
ON CONFLICT (model_id, effective_from) DO NOTHING;

-- Which model serves which kind. All four extraction kinds send an IMAGE
-- (`ExtractModels` allows receipt, pump, chargeScreenshot, invoice), so all four
-- resolve to the vision model - a text model physically cannot read them. They
-- are separate rows rather than one default precisely so a future kind can move
-- to a different model by a single UPDATE, which is the whole reason RV.34 keyed
-- this per kind instead of storing one global scalar.
INSERT INTO llm_settings (kind, model_id)
VALUES
    ('receipt',          'deepseek-v4-flash-vision-exp'),
    ('pump',             'deepseek-v4-flash-vision-exp'),
    ('chargeScreenshot', 'deepseek-v4-flash-vision-exp'),
    ('invoice',          'deepseek-v4-flash-vision-exp')
ON CONFLICT (kind) DO NOTHING;

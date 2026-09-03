-- Tankbook backend, migration 015 (the LLM call ledger, RV.33).
-- docs/SECURITY.md "LLM call ledger", CLAUDE.md hard rule 9 amendment
-- (2026-09-03). One row per call to an LLM gate - /extract today, /agent/turn
-- when v2 lands. It records what was sent, what came back and what it cost,
-- because the gateway spends real money per call on the user's behalf and no
-- other record of any of it exists anywhere.
--
-- The row snapshots the unit prices it paid (input/output per token) and the
-- computed cost, so a vendor price rise never silently rewrites the cost of a
-- historical call - hard rule 3's rate-snapshot logic applied to a second kind
-- of money (docs/API.md "LLM gateway").
--
-- Content columns (prompt_body, response_body, thinking_body) and the rendition
-- blob referenced by prompt_sha256 are PURGED on account deletion and after 30
-- days; the row itself - the spend ledger - survives with account_id, model,
-- vendor, tokens, cost, outcome and the sha256 reference intact.
--
-- account_id deliberately has NO foreign key: it must survive account deletion
-- so per-account cost history outlives the account (product owner, 2026-09-03).
CREATE TABLE llm_calls (
    id                     uuid PRIMARY KEY,
    account_id             uuid NOT NULL,
    device_id              uuid,
    kind                   text NOT NULL,
    model_id               text NOT NULL,
    vendor                 text NOT NULL,
    outcome                text NOT NULL,
    category               text NOT NULL,
    prompt_tokens          bigint NOT NULL DEFAULT 0,
    completion_tokens      bigint NOT NULL DEFAULT 0,
    thinking_enabled       boolean NOT NULL DEFAULT false,
    input_price_per_token  numeric(18,10) NOT NULL DEFAULT 0,
    output_price_per_token numeric(18,10) NOT NULL DEFAULT 0,
    cost                   numeric(18,10) NOT NULL DEFAULT 0,
    currency               char(3) NOT NULL DEFAULT 'USD',
    prompt_sha256          text,
    prompt_body            text,
    response_body          text,
    thinking_body          text,
    duration_ms            bigint NOT NULL DEFAULT 0,
    created_at             timestamptz NOT NULL DEFAULT now()
);

-- The 30-day content purge scans on created_at.
CREATE INDEX idx_llm_calls_created_at ON llm_calls (created_at);

-- Account deletion purges content; per-account cost history is read by id.
CREATE INDEX idx_llm_calls_account ON llm_calls (account_id);

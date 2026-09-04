-- Tankbook backend, migration 021 (the ledger write queue, RV.53).
-- docs/SECURITY.md "The ledger write queue". When the gateway's audit write -
-- the llm_calls row that records a call the user was charged for - cannot land
-- synchronously, the row is queued here and retried for a bounded time instead
-- of failing the request. RV.33 put blob storage on /extract's critical path;
-- 021 takes the ledger write off it: an audit write must never fail a user's
-- request, and a row that cannot land synchronously must not be silently lost.
--
-- What this table is NOT, stated plainly: it is not a store of user images.
-- It holds one LEDGER ROW (the same columns as llm_calls) waiting for the row
-- insert to succeed. The prompt rendition lives in blob storage, referenced by
-- prompt_sha256 when the request could write it, and is never queued here - the
-- server retains no image bytes, so a rendition that could not be written in
-- the request is dropped and the row lands without one (docs/SECURITY.md, the
-- degradation RV.53 names). The device still holds the original photo.
--
-- account_id carries a foreign key with ON DELETE CASCADE like the delivery
-- outbox (migration 016): a queued row belongs to the account that is being
-- deleted. The account purge also deletes pending rows explicitly (belt and
-- braces), because llm_calls itself deliberately has no FK - the pending queue
-- is staging, not the surviving spend ledger, so it purges like the outbox.
--
-- Bounded two ways: the retry worker gives up after LlmCalls:MaxRetryAttempts
-- with backoff (the give-up is a defined outcome - a dropped row and a Warning
-- event, never an infinite retry), and the hourly retention purge drops any row
-- still queued past the 30-day cutoff (the one number that already governs
-- llm_calls' content, /import/parse's file and the delivery outbox).
CREATE TABLE llm_ledger_pending (
    id                     uuid PRIMARY KEY,
    account_id             uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
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
    attempts               integer NOT NULL DEFAULT 0,
    next_attempt_at        timestamptz NOT NULL DEFAULT now(),
    created_at             timestamptz NOT NULL DEFAULT now()
);

-- The retry worker scans for rows whose next attempt is due.
CREATE INDEX idx_llm_ledger_pending_due ON llm_ledger_pending (next_attempt_at);

-- The 30-day retention purge scans on created_at (both sides of the cutoff).
CREATE INDEX idx_llm_ledger_pending_created ON llm_ledger_pending (created_at);

-- Account deletion purges the account's pending rows (docs/SECURITY.md).
CREATE INDEX idx_llm_ledger_pending_account ON llm_ledger_pending (account_id);

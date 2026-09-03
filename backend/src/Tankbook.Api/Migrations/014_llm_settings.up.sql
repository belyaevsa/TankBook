-- Tankbook backend, migration 014 (LLM model choice and pricing as data, RV.34).
-- docs/API.md "LLM gateway (Pro)". Two tables move the model out of compiled
-- config and the pricing out of nowhere:
--
-- llm_settings keys which model serves which KIND. /extract already
-- distinguishes receipt from pump-display extraction (the llm.extract log line
-- carries the kind), and those are different problems that may want different
-- models, so the choice is per-kind, not one global scalar. A missing row means
-- "no override for this kind" - the resolver falls back to the compiled default
-- and logs the fallback at Warning rather than 500ing, so one bad row can never
-- take cloud extraction down for everyone (docs/API.md).
--
-- llm_models is the model dictionary: what a model costs and what it can do.
-- Prices are per token (input and output differ for every vendor), and
-- effective_from makes a price correction a NEW row, never an edit to a
-- historical one - the same append-only discipline as exchange_rates, because a
-- call row snapshots the price it paid and the dictionary must not silently
-- rewrite that snapshot (hard rule 3's logic applied to a second kind of money).
-- supports_thinking is the flag RV.33 needs: ILlmProvider has no notion of it
-- today, and the call ledger records whether thinking was enabled and its
-- response.
--
-- Updated by direct DB write, no admin endpoint (the same decision as the
-- vehicle catalog). No API keys live here - the dictionary NAMES a vendor, it
-- never authenticates to one (hard rule 11: keys stay in the platform secret
-- store, which is the entire reason the gateway exists).

CREATE TABLE llm_settings (
    kind       text PRIMARY KEY,
    model_id   text NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE llm_models (
    model_id         text NOT NULL,
    vendor           text NOT NULL,
    input_price      numeric(18,10) NOT NULL, -- per input (prompt) token
    output_price     numeric(18,10) NOT NULL, -- per output (completion) token
    currency         char(3) NOT NULL,
    context_window   integer NOT NULL,
    supports_thinking boolean NOT NULL DEFAULT false,
    effective_from   date NOT NULL,
    PRIMARY KEY (model_id, effective_from)
);

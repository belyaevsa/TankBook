-- Tankbook backend, migration 010 (LLM gateway tier).
-- docs/API.md "LLM gateway (Pro)": POST /extract is the Pro tier's cloud-fallback
-- path. The quota ledger (llm_usage, migrated in 001) counts requests and tokens
-- per account per period, but it cannot express whether an account's tier is
-- entitled to any LLM access at all: the free tier has no allowance (402, "the
-- tier lacks quota") while a paid tier has an allowance that can be spent (429,
-- "this period's allowance is used up"). That entitlement lives on the account
-- as a single scalar. The default is the free tier, so a fresh account is never
-- accidentally billed against an allowance it has not purchased; the Pro tier is
-- assigned by P6.3's paywall when it lands.

ALTER TABLE accounts ADD COLUMN llm_tier text NOT NULL DEFAULT 'free';

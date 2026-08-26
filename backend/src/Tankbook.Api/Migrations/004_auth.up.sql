-- Tankbook backend, migration 004 (auth: refresh tokens).
-- docs/API.md "Auth", docs/SECURITY.md "Backend - secret management". Refresh
-- tokens rotate on every use (POST /auth/refresh) and are stored as a SHA-256
-- hash, never the token itself: a database dump must not yield working
-- credentials. Reuse of an already-rotated token revokes the whole chain
-- (docs/API.md: reuse of a rotated token is a theft signal); the chain is the
-- rotation lineage, keyed by chain_id, so one revoke kills every token ever
-- issued for that sign-in.

CREATE TABLE refresh_tokens (
    id           uuid PRIMARY KEY,
    account_id   uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    device_id    uuid NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
    token_hash   text NOT NULL UNIQUE,
    chain_id     uuid NOT NULL,
    issued_at    timestamptz NOT NULL DEFAULT now(),
    expires_at   timestamptz NOT NULL,
    rotated_at   timestamptz,
    revoked_at   timestamptz,
    replaced_by  uuid REFERENCES refresh_tokens (id)
);

-- Lookup on refresh is by token_hash (the UNIQUE key already serves it); these
-- three serve the maintenance paths: revoke a whole chain (reuse), revoke a
-- whole device (sign-out), and cascade/sweep by account.
CREATE INDEX idx_refresh_tokens_chain   ON refresh_tokens (chain_id);
CREATE INDEX idx_refresh_tokens_device  ON refresh_tokens (device_id);
CREATE INDEX idx_refresh_tokens_account ON refresh_tokens (account_id);

-- The admin viewer's own tables (docs/SECURITY.md -> "The admin viewer"). Schema `admin`
-- only - created by roles.sql, owned by the write role: the viewer reads the API's tables
-- through a read-only role and writes nothing outside this schema.

-- The owner's passkeys. `label` is what the access log records as the actor - a device
-- name the owner chose, never an email.
CREATE TABLE admin.passkeys (
    id            uuid PRIMARY KEY,
    credential_id bytea NOT NULL UNIQUE,
    public_key    bytea NOT NULL,
    sign_count    bigint NOT NULL DEFAULT 0,
    user_handle   bytea NOT NULL,
    label         text NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    last_used_at  timestamptz
);

-- The one-time token that registers the first passkey. Only its SHA-256 is stored; a
-- consumed token never works again, whatever the configuration still holds.
CREATE TABLE admin.bootstrap_tokens (
    token_hash  text PRIMARY KEY,
    created_at  timestamptz NOT NULL DEFAULT now(),
    consumed_at timestamptz
);

-- One row per look at user content, including a look that found nothing. Kept a year and
-- never purged with the content it points at: the audit of the reader outlives what was read.
CREATE TABLE admin.access_log (
    id        bigserial PRIMARY KEY,
    at        timestamptz NOT NULL DEFAULT now(),
    actor     text NOT NULL,
    kind      text NOT NULL,
    target_id text,
    route     text NOT NULL,
    status    integer NOT NULL
);
CREATE INDEX access_log_at ON admin.access_log (at DESC);

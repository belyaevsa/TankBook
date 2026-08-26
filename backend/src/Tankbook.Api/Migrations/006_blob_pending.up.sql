-- Tankbook backend, migration 006 (blob pipeline: pending uploads + sweep index).
-- docs/API.md "Attachments (blob pipeline)", docs/SYNC.md "Attachments: the blob
-- pipeline". POST /blobs/begin returns a presigned PUT but inserts no blobs row
-- (a blobs row means "committed and size-verified"). The size the client declared
-- at begin must survive to commit, because POST /blobs/commit carries only
-- { sha256 } and the server has to verify the stored object against the declared
-- size (docs/API.md: "204 after server verifies object + size"). blob_pending is
-- that memory: one row per (account, sha256) begin, consumed (and deleted) by the
-- matching commit. It is never a quota charge - quota is metered from the blobs
-- index, not from pending uploads.

CREATE TABLE blob_pending (
    account_id   uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    sha256       text NOT NULL,
    size_bytes   bigint NOT NULL,
    content_type text NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (account_id, sha256)
);

-- The orphan sweep selects candidate blobs by account and commit age; the
-- primary key (account_id, sha256) serves account filtering but not the age
-- filter, so this index makes the sweep a range scan instead of a filter.
CREATE INDEX idx_blobs_account_created ON blobs (account_id, created_at);

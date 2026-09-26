-- Debug cases are stored asynchronously (docs/API.md "Debug cases"): the API
-- answers once the parts are on its own disk, and a background uploader moves
-- them to blob storage. stored_at is set when every part is in storage; until
-- then the case is readable by nobody (the admin viewer answers "still
-- uploading"). The claim columns let exactly one API container upload a case.
ALTER TABLE debug_cases
    ADD COLUMN stored_at         timestamptz,
    ADD COLUMN upload_attempts   integer NOT NULL DEFAULT 0,
    ADD COLUMN upload_claimed_at timestamptz,
    ADD COLUMN upload_failed_at  timestamptz;

-- Every case accepted before this migration was written to storage in the request.
UPDATE debug_cases SET stored_at = created_at;

CREATE INDEX idx_debug_cases_pending ON debug_cases (created_at)
    WHERE stored_at IS NULL AND upload_failed_at IS NULL;

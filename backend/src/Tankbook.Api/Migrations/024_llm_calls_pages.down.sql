-- Reverses migration 024 (multi-page invoice renditions). The page blobs the
-- column referenced are orphaned in storage until the account purge; the
-- extract key leaves the baseline document and the signature is blanked so the
-- seeder re-signs it.
UPDATE config_documents
SET document = document - 'extract', signature = ''
WHERE version = 1;
ALTER TABLE llm_ledger_pending DROP COLUMN prompt_page_sha256s;
ALTER TABLE llm_calls DROP COLUMN prompt_page_sha256s;

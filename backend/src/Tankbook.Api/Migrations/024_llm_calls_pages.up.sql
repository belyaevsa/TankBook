-- Tankbook backend, migration 024 (multi-page invoice renditions, PJ.301).
-- docs/API.md "multi-page invoices"; docs/SECURITY.md "LLM call ledger".
--
-- A multi-page /extract call sends every page of one invoice in one call. The
-- ledger row keeps referencing ONE rendition in prompt_sha256 (the first page,
-- so every reader of the single-image shape is unchanged) and lists every
-- further page here, each a content-addressed blob under the same account
-- prefix. The retention purge and the account purge delete these blobs exactly
-- as they delete prompt_sha256's, and the column is nulled with the rest of the
-- row's content when the row is purged.
ALTER TABLE llm_calls ADD COLUMN prompt_page_sha256s text[];
ALTER TABLE llm_ledger_pending ADD COLUMN prompt_page_sha256s text[];

-- The served config document echoes the page cap (ExtractLimits.MaxInvoicePages)
-- as extract.maxInvoicePages so the camera stops at the cap before a request is
-- built. The baseline document is version 1 and stays version 1 - a new
-- version is an operator publish (POST /config, CONFIG.md), never a migration -
-- so the key is added in place and the signature blanked: the seeder re-signs
-- an unsigned, schema-valid top document at the next startup, and an unsigned
-- document is never served (clients reject it). A fleet that already holds
-- version 1 keeps its copy until the next publish; a device without the key
-- uses the compiled default, which is the same number.
UPDATE config_documents
SET document = document || jsonb_build_object('extract', jsonb_build_object('maxInvoicePages', 6)),
    signature = ''
WHERE version = 1
  AND NOT (document ? 'extract');

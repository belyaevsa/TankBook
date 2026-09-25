-- The two roles the admin viewer connects as (docs/SECURITY.md -> "The admin viewer").
-- Run once by a database owner; the passwords are placeholders - set real ones from the
-- secret store, never commit them.
--
--   tankbook_admin_ro  - ConnectionStrings:ApiRead. SELECT on the API tables the viewer
--                        shows, nothing else: it cannot write, and it cannot read the
--                        API's secrets (refresh tokens, config signing, outbox).
--   tankbook_admin_rw  - ConnectionStrings:AdminWrite. Owns schema `admin` and can touch
--                        nothing outside it.

CREATE ROLE tankbook_admin_ro LOGIN PASSWORD 'change-me-ro';
GRANT USAGE ON SCHEMA public TO tankbook_admin_ro;
GRANT SELECT ON accounts, devices, records, blobs, llm_calls TO tankbook_admin_ro;

CREATE ROLE tankbook_admin_rw LOGIN PASSWORD 'change-me-rw';
CREATE SCHEMA IF NOT EXISTS admin AUTHORIZATION tankbook_admin_rw;
REVOKE ALL ON SCHEMA public FROM tankbook_admin_rw;

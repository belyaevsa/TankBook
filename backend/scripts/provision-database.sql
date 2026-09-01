-- Provisions the Tankbook production database, its roles and their grants.
--
--   psql -h <host> -U <admin> -d postgres \
--        -v db=tankbook -v app_user=tankbook_app -v app_password='<from the secret store>' \
--        -v ro_user=tankbook_ro -v ro_password='<from the secret store>' \
--        -f backend/scripts/provision-database.sql
--
-- Passwords are psql variables, never literals: this file is committed to a
-- public repo, and a password in it would be a credential in git history the
-- moment it was filled in. Generate them where they will live:
--
--   openssl rand -base64 32
--
-- and put the resulting connection string in the platform secret store as
-- POSTGRES_CONNECTION (docs/SECURITY.md -> "Backend - secret management").
--
-- Run once per environment, as a role that may CREATE DATABASE and CREATE ROLE.
-- It is idempotent: re-running changes nothing except rotating the passwords to
-- whatever was passed in, so it doubles as the password-rotation script.

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- 1 - Roles
-- ---------------------------------------------------------------------------
-- Two logins, and the split is the point:
--
--   app_user  owns the schema and RUNS THE MIGRATIONS. It needs DDL, because
--             MigrationHostedService applies pending migrations at startup as
--             this role (backend/src/Tankbook.Api/Data/SchemaMigrator.cs) -
--             there is no separate migration step to give a separate identity.
--             Splitting DDL into a second role would be security theatre here:
--             the process holding the runtime credential is the one issuing the
--             DDL, so the runtime credential can always reach it.
--
--   ro_user   read-only, for the operator work that used to need an API
--             endpoint. The vehicle catalog is now curated by writing to the
--             database directly (2026-09-01), and support questions are read
--             queries; neither should be done with the credential the API
--             serves traffic on. Read-only by default so the dangerous half is
--             a deliberate act - see the note at the end about catalog writes.
--
-- NOSUPERUSER / NOCREATEDB / NOCREATEROLE are stated rather than inherited:
-- these are the attributes an attacker with the connection string inherits.

-- Written with \gexec rather than a DO block on purpose: psql does NOT
-- substitute :'variables' inside dollar-quoted bodies, so the obvious
-- DO $$ ... :'app_user' ... $$ version fails with a syntax error at the colon.
-- \gexec runs whatever the preceding SELECT returned, and a SELECT that returns
-- no row runs nothing - which is how CREATE ROLE becomes idempotent without
-- IF NOT EXISTS, a clause CREATE ROLE does not have.
SELECT format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT', :'app_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user')
\gexec

SELECT format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT', :'ro_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'ro_user')
\gexec

-- Passwords are set unconditionally, so re-running this script IS the password
-- rotation procedure. %L quotes the literal, so a password containing a quote
-- cannot terminate the statement.
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'app_user', :'app_password')
\gexec

SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'ro_user', :'ro_password')
\gexec

-- ---------------------------------------------------------------------------
-- 2 - Database
-- ---------------------------------------------------------------------------
-- CREATE DATABASE cannot run inside a transaction or a DO block, so it is
-- guarded with \gexec: the SELECT produces the statement only when the database
-- is absent, and \gexec runs whatever the query returned (nothing, if present).
--
-- UTF8 with the C collation for indexes that do not depend on a locale being
-- installed on the host. Nothing in this schema does locale-aware ordering -
-- records are ordered by SCN, catalog entries by the client - so a stable,
-- portable collation is worth more than linguistic sorting.

SELECT format('CREATE DATABASE %I OWNER %I ENCODING ''UTF8'' LC_COLLATE ''C'' LC_CTYPE ''C'' TEMPLATE template0',
              :'db', :'app_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db')
\gexec

-- Revoke the default PUBLIC connect right: without this, every role on the
-- cluster can connect to this database, including ones created later for
-- something else entirely.
REVOKE ALL ON DATABASE :"db" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"db" TO :"app_user";
GRANT CONNECT ON DATABASE :"db" TO :"ro_user";

-- ---------------------------------------------------------------------------
-- 3 - Schema privileges (inside the new database)
-- ---------------------------------------------------------------------------
\connect :"db"

-- Postgres 15+ already removes PUBLIC's CREATE on the public schema; stated
-- anyway so this script produces the same result on 13/14, where it does not.
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- The app owns the schema: migrations CREATE TABLE and CREATE INDEX in it at
-- every startup that finds pending versions.
ALTER SCHEMA public OWNER TO :"app_user";
GRANT ALL ON SCHEMA public TO :"app_user";

-- The read-only role may look, never touch. USAGE lets it resolve names in the
-- schema; SELECT is granted on what exists now, and the DEFAULT PRIVILEGES
-- below cover what migrations create later - without that second grant, the
-- read-only role silently cannot see any table added after this script ran,
-- which is the failure that gets diagnosed as "the role is broken" months on.
GRANT USAGE ON SCHEMA public TO :"ro_user";
GRANT SELECT ON ALL TABLES IN SCHEMA public TO :"ro_user";
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO :"ro_user";

ALTER DEFAULT PRIVILEGES FOR ROLE :"app_user" IN SCHEMA public
    GRANT SELECT ON TABLES TO :"ro_user";
ALTER DEFAULT PRIVILEGES FOR ROLE :"app_user" IN SCHEMA public
    GRANT SELECT ON SEQUENCES TO :"ro_user";

-- ---------------------------------------------------------------------------
-- 4 - What is deliberately NOT here
-- ---------------------------------------------------------------------------
-- No CREATE EXTENSION. The migrations were checked and need none - no pgcrypto,
-- no uuid-ossp - because ids are generated by the application as UUIDv7. That
-- is why this script needs no superuser, and adding an extension later is a
-- decision that changes that, not a detail.
--
-- No table creation. The 16 tables and their indexes belong to the migrations
-- (backend/src/Tankbook.Api/Migrations/*.up.sql), applied on boot. Creating
-- them here would fork the schema definition into two places that drift.
--
-- CATALOG WRITES: the vehicle catalog is now updated directly in the database
-- (2026-09-01), and `ro_user` cannot do that on purpose. Grant the write
-- explicitly for the session that does it, rather than making the operator role
-- writable by default:
--
--   GRANT INSERT, UPDATE, DELETE ON vehicle_catalog, catalog_pack_state TO tankbook_ro;
--
-- Note what that bypasses. The schema check and the monotonic packVersion guard
-- live in CatalogPublishService, not in the database (docs/API.md -> "Vehicle
-- catalog"), so a hand-written INSERT can publish a malformed entry or roll the
-- version backwards and nothing will stop it.

\echo 'Provisioned. Connection string for POSTGRES_CONNECTION:'
\echo '  Host=<host>;Port=5432;Database=<db>;Username=<app_user>;Password=<app_password>;SSL Mode=Require'

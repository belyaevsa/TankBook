# AD.4 - The admin viewer: the service, passkey sign-in, the access log

## Where you may write

**Only inside `/Users/sbelyaev/repos/fuel-counter-ios/admin/`** (it does not exist yet - you create it).
Nothing in `backend/`, `ios/`, `docs/`, `scripts/` or anywhere else. Reading them is fine.
Do not commit. Do not tick `docs/TASKS.md`.

## Write code first, explore second

This is a new, self-contained service. Everything you need to know about the existing system is
below; do not tour the iOS app or the pump reader. Start writing within the first few minutes.

## What this is

The product owner debugs the app from what users captured. Hard rule 9's 2026-09-24 amendment
(`CLAUDE.md`, the paragraph "The debug cases and the admin viewer") and `docs/SECURITY.md` ->
"The admin viewer" (read both - they are the authority) allow **one internal tool** to read user
content. This row builds that tool's skeleton: the service, the owner's passkey sign-in, and the
access log that every content view writes. Later rows add its pages (AD.5 the LLM ledger, AD.6 an
account's attachments, the case page after AD.3).

Owner, 2026-09-25: *"frontend - react; backend must be separate to what we have, but still .net"*;
sign-in by **passkey**; reached at a **public URL** (`admin.tankbook.live`, deployed later by AD.8).

## What already exists (read, do not change)

- `backend/` - the public API, ASP.NET Core **.NET 10** (`net10.0`), minimal APIs, **Dapper +
  Npgsql 10**, xunit + `Microsoft.AspNetCore.Mvc.Testing` + **Testcontainers.PostgreSql 4.14**
  (`backend/tests/Tankbook.Api.Tests/Tankbook.Api.Tests.csproj` - copy its package versions).
- The API's database schema: `backend/src/Tankbook.Api/Migrations/*.up.sql`. The tables this
  viewer will read later: `accounts` (id, apple_sub, google_sub, email, created_at, deleted_at),
  `devices` (id, account_id, name, platform, last_seen_at, ...), `records` (account_id, id,
  entity_type, scn, payload jsonb, ...), `blobs` (account_id, sha256, size_bytes, storage_ref,
  created_at), `llm_calls` (see 015). **This row reads only `accounts` and `devices`.**
- Logging rules: `docs/LOGGING.md` §1 - ids, counts, durations, codes are loggable; email,
  payloads, prompts, images, tokens never are, at any level (hard rule 12).
- No docker-compose anywhere (owner's rule).

## What to build

### Layout

```
admin/
  Tankbook.Admin.slnx
  api/src/Tankbook.Admin/            ASP.NET Core, net10.0, minimal APIs, Dapper + Npgsql
  api/src/Tankbook.Admin/Migrations/ plain SQL, schema `admin` only (001_admin.up.sql / .down.sql)
  api/tests/Tankbook.Admin.Tests/    xunit + Mvc.Testing + Testcontainers.PostgreSql
  web/                               React 18 + Vite + TypeScript; `npm run build` writes into
                                     api/src/Tankbook.Admin/wwwroot (gitignored)
  README.md                          how to run it locally, configure it, register the first passkey
```

**No project in `admin/` references a project in `backend/`, and nothing in `backend/` changes.**
Tests may *read* `backend/src/Tankbook.Api/Migrations/*.up.sql` from disk to create the API's
tables in the test database - reading a file is not a reference.

### Two database connections, least privilege

- `ConnectionStrings:ApiRead` - the **read-only** role (`tankbook_admin_ro` in production): `SELECT`
  on API tables. Every query over API data goes through this connection and nothing else.
- `ConnectionStrings:AdminWrite` - a role that owns only schema `admin`. The access log, passkeys
  and bootstrap tokens live there.
- `admin/api/src/Tankbook.Admin/Migrations/roles.sql` - the SQL a DBA runs to create both roles
  (`CREATE ROLE ... LOGIN`, `GRANT USAGE ON SCHEMA public`, `GRANT SELECT ON accounts, devices,
  records, blobs, llm_calls TO tankbook_admin_ro`, the admin schema owned by the write role).
  Password placeholders only - no secret in the repo.
- A `--migrate` command-line mode applies `admin` migrations through `AdminWrite` and exits (the
  API applies its own migrations as a separate step for the same reason - `docs/SYNC.md`).

`001_admin.up.sql` creates, in schema `admin`:
- `passkeys` (id, credential_id bytea unique, public_key bytea, sign_count bigint, user_handle
  bytea, label text, created_at, last_used_at)
- `bootstrap_tokens` (token_hash text primary key, created_at, consumed_at)
- `access_log` (id bigserial, at timestamptz, actor text, kind text, target_id text, route text,
  status int) - `actor` is the passkey's label, never an email.

### Passkey sign-in (WebAuthn)

Use **`Fido2.AspNet` / `Fido2NetLib`** (the maintained .NET WebAuthn library, v4). Config section
`Fido2`: `ServerDomain`, `ServerName`, `Origins` (production `https://admin.tankbook.live`; development
`http://localhost:5173` and the service's own dev port).

Endpoints (JSON, under `/auth`):
- `POST /auth/register/options` - allowed only with a valid **bootstrap token** in the body (when no
  passkey exists yet) **or** a signed-in session (to add a second device). Returns credential
  creation options.
- `POST /auth/register/verify` - verifies the attestation, stores the passkey, **consumes the
  bootstrap token** (marks `consumed_at`), signs the owner in.
- `POST /auth/login/options`, `POST /auth/login/verify` - assertion ceremony against stored
  passkeys; updates `sign_count` and `last_used_at`; rejects a sign count that goes backwards.
- `POST /auth/logout`.

The bootstrap token: configuration `Admin:BootstrapToken` (from the secret store in production).
On startup, if no passkey exists and the token is set, store its **SHA-256** in
`bootstrap_tokens` (never the token itself). A consumed token never works again, even if the
configuration still holds it. Once any passkey exists, registration without a session is refused.

Session: ASP.NET Core cookie authentication - `HttpOnly`, `Secure` (except in Development),
`SameSite=Strict`, 8-hour absolute expiry, no sliding. Sign-in endpoints rate-limited
(`Microsoft.AspNetCore.RateLimiting`, fixed window per IP, e.g. 10 / minute).

### Content endpoints and the access log

Every endpoint that returns user content requires the session **and** writes one `access_log` row
(actor, kind, target id, route, status) - including when the target does not exist (404 is still
a look). Build this as one piece of middleware or an endpoint filter that content endpoints opt
into, so a later page cannot forget it.

This row's content endpoints (the minimum that proves the mechanism):
- `GET /api/accounts/{id}` - `{ id, createdAt, deletedAt, provider: "apple"|"google", email,
  devices: [{ id, name, platform, lastSeenAt }] }` through `ApiRead`. Kind `account`.
- `GET /api/lookup?q=` - classifies `q` (a UUID is tried as an account id; anything else is
  "not found" for now) and returns `{ kind, id }` or 404. Kind `lookup`. **No search, no prefix
  match, no list** - an exact id only.
- `GET /api/access-log?before=&limit=` - the log itself, newest first, paged (the owner reading his
  own audit trail; still session-only, not itself logged).
- `GET /api/me` - `{ label }` for the signed-in passkey.
- `GET /health` - no session, returns `{ status: "ok" }`, no content.

Everything else returns 401 without a session. Response headers on everything: a strict
`Content-Security-Policy` (`default-src 'self'`), `X-Content-Type-Options: nosniff`,
`Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`.

### The React app (`admin/web`)

Vite + React 18 + TypeScript, `@simplewebauthn/browser` for the WebAuthn calls, `react-router`.
Pages:
- **Sign in** - one button (passkey). A link "First time? Register with a bootstrap token" opens a
  form that takes the token and runs registration with a label (e.g. "iPhone").
- **Shell** - a header with the passkey label and Sign out; a single lookup box ("case id, traceId
  or account id"); results route to the matching page.
- **Account** (`/accounts/:id`) - the account endpoint's fields, devices as a table.
- **Access log** (`/access-log`) - a table, newest first, "older" paging.

Plain, dense, readable - an internal tool; no design system required. Dark theme by default
(`prefers-color-scheme`), because the owner works in dark.

`npm run build` must emit into `../api/src/Tankbook.Admin/wwwroot`; the service serves it with a
fallback to `index.html` for client routes. Add `admin/web/node_modules/`, `admin/web/dist/` and
`admin/api/src/Tankbook.Admin/wwwroot/` to an `admin/.gitignore`.

### Logging

Shape only: `admin.signin` (outcome), `admin.register` (outcome), `admin.view` (kind, target id,
status, duration). Never an email, a cookie, a token, a credential, a payload.

## Explicitly out of scope

AD.5 (the LLM ledger pages), AD.6 (attachments), AD.3 / AD.2 (cases), AD.8 (deployment: Dockerfile
tuning, nginx, TLS, CI) - but do add a minimal `admin/api/Dockerfile` modelled on
`backend/Dockerfile` so AD.8 has a starting point. No change to `backend/`. No docker-compose.

## Checks - by exit code, run them, report each

From `admin/`:
1. `dotnet build Tankbook.Admin.slnx` - 0.
2. `dotnet format Tankbook.Admin.slnx --verify-no-changes` - 0.
3. `dotnet test Tankbook.Admin.slnx` - 0; report the count (Testcontainers needs Docker; it is
   available on this machine).
From `admin/web/`:
4. `npm ci` (commit the `package-lock.json`), `npm run build` - 0; `npm test` (vitest) - 0 with a count.
From the repo root:
5. `cd backend && dotnet build` - still 0 (you changed nothing there - prove it).

## Tests you must add (each names its oracle)

- **401 without a session** on `GET /api/accounts/{id}`, `/api/lookup`, `/api/access-log`,
  `/api/me` - the oracle is SECURITY.md's "nothing answers without a session except sign-in".
- **The bootstrap token works once**: register options with the token -> 200; after a stored
  passkey (insert one directly in the test), options with the same token -> 403. Oracle: SECURITY.md
  "a consumed token never works again".
- **A view writes its access row**: an authenticated `GET /api/accounts/{id}` (use a test
  authentication scheme registered by the test's `WebApplicationFactory`, not a real WebAuthn
  ceremony) inserts exactly one `access_log` row with kind `account` and that id - **and so does a
  404**.
- **The read-only role cannot write**: in the Testcontainers database, create the API tables from
  the backend's migration files, run `roles.sql`, connect as `tankbook_admin_ro`, and assert an
  `INSERT INTO accounts` fails with a permission error while `SELECT` works.
- **Lookup is exact**: `q` = the first 8 characters of an existing account id -> 404.
- Web (vitest): the lookup box routes a UUID to `/accounts/<id>`; the sign-in page shows the
  register link.

**The mutation (named here, run it, paste the red output, restore):** remove the access-log filter
from `GET /api/accounts/{id}` - the "view writes its access row" test must go red.

## Vacuous traps

- A 401 test that hits a route that does not exist (404 would also "fail to return content") -
  assert the status is exactly 401.
- An access-log test that counts rows in a table the test never cleared.
- A read-only-role test that connects as the superuser.

## Report back

Every check with its exit code and test counts; the mutation's red output verbatim; the package
versions you chose; how to run locally (the README); anything you found and did not fix.

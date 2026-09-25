# Tankbook admin

The owner's debugging tool: a separate ASP.NET Core service (`api/`) and its React app
(`web/`). It reads user content under hard rule 9's admin-viewer amendment (`CLAUDE.md`);
`docs/SECURITY.md` -> "The admin viewer" is the authority for what it may read, how you sign
in, and what every view records. It shares no project, port or credential with `backend/`.

## What is here (AD.4)

- **Passkey sign-in** (WebAuthn - Face ID / Touch ID). No password exists. The first passkey
  is registered with a one-time bootstrap token; later ones only from a signed-in session.
- **An account by its exact id** (`/api/accounts/{id}`) and the **lookup box** - no list of
  users, no search.
- **The access log**: every content request writes a row (`admin.access_log`) - who (the
  passkey's label), what kind, which id, the status - including a look that found nothing.

Pages still to come: the LLM ledger (AD.5), an account's attachments (AD.6), debug cases
(after AD.3). Deployment is AD.8.

## Database

Two roles, created once by a database owner with `api/src/Tankbook.Admin/Migrations/roles.sql`
(set real passwords from the secret store):

| Connection | Role | Can |
|---|---|---|
| `ConnectionStrings:ApiRead` | `tankbook_admin_ro` | `SELECT` on accounts, devices, records, blobs, llm_calls - nothing else |
| `ConnectionStrings:AdminWrite` | `tankbook_admin_rw` | own schema `admin` (passkeys, bootstrap tokens, access log) - nothing outside it |

Apply the viewer's schema as its own step: `dotnet run --project api/src/Tankbook.Admin -- --migrate`.

## Run it locally

```
# a Postgres with the API's schema: backend/scripts/dev-up.sh, then the API's own migrations
psql ... -f api/src/Tankbook.Admin/Migrations/roles.sql      # once
export ConnectionStrings__ApiRead="Host=localhost;Database=tankbook;Username=tankbook_admin_ro;Password=change-me-ro"
export ConnectionStrings__AdminWrite="Host=localhost;Database=tankbook;Username=tankbook_admin_rw;Password=change-me-rw"
export Admin__BootstrapToken="$(openssl rand -hex 24)"; echo "$Admin__BootstrapToken"
dotnet run --project api/src/Tankbook.Admin -- --migrate
dotnet run --project api/src/Tankbook.Admin          # http://localhost:5047
cd web && npm ci && npm run dev                       # http://localhost:5173 (proxies the service)
```

Open http://localhost:5173, choose **First time? Register with a bootstrap token**, paste the
token, name the device, and confirm with Face ID / Touch ID. The token is spent; sign in with
the passkey from then on.

## Checks

```
dotnet build Tankbook.Admin.slnx && dotnet format Tankbook.Admin.slnx --verify-no-changes
dotnet test Tankbook.Admin.slnx            # needs Docker (Testcontainers Postgres)
cd web && npm ci && npm run build && npm test && npm run lint
```

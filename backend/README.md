# Tankbook Backend

ASP.NET Core minimal API implementing `docs/API.md`, backed by Postgres (opaque JSONB records, `docs/SYNC.md`) and S3-compatible object storage (MinIO locally). Npgsql + Dapper; RFC 7807 problem+json errors.

## Run locally

```sh
./backend/scripts/dev-up.sh      # start Postgres 17 (:5432) + MinIO (:9000 API, :9001 console)
dotnet run --project backend/src/Tankbook.Api
curl localhost:5000/health       # {"status":"ok","version":"0.1.0"}
./backend/scripts/dev-down.sh    # stop and remove the containers
```

## Test

```sh
cd backend && dotnet build && dotnet test
```

Configuration: `ConnectionStrings:Postgres` and `S3` options bind from appsettings + environment variables (`ConnectionStrings__Postgres`, `S3__Endpoint`, ...). Local dev defaults live in `appsettings.Development.json`; never commit real credentials.

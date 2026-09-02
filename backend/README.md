# Tankbook Backend

ASP.NET Core minimal API implementing `docs/API.md`, backed by Postgres (opaque JSONB records, `docs/SYNC.md`) and S3-compatible object storage (MinIO locally). Npgsql + Dapper; RFC 7807 problem+json errors.

## Run locally

```sh
./backend/scripts/generate-appsettings.sh   # REQUIRED on a fresh clone - see below
./backend/scripts/dev-up.sh                 # Postgres 17 (:5434) + MinIO (:9000 API, :9001 console)
dotnet run --project backend/src/Tankbook.Api
curl 127.0.0.1:5175/health                  # {"status":"ok","version":"0.1.0"}
./backend/scripts/dev-down.sh               # stop and remove the containers
```

The port is `5175`, from `Properties/launchSettings.json` – not 5000.

**The generate step is not optional.** `appsettings.json` and
`appsettings.Development.json` are gitignored (they hold real credentials and this repo is public);
what is committed is `appsettings.template.json` / `appsettings.Development.template.json` plus the
generator, which fills them from the environment. Measured: with `appsettings.json` absent
`dotnet test` **aborts after 117 of 295 tests**, so this is needed for the *suite*, not just for a
running server. Re-running the generator is safe – environment wins, then whatever the file already
had, then the template's blank, so it never destroys a value you typed in by hand.

Nothing needs to be exported for local work: the generated `appsettings.Development.json` carries
the localhost Postgres and MinIO defaults, and `dotnet run` picks the Development environment up
automatically.

## Docker

```sh
docker build -f backend/Dockerfile -t tankbook-api:dev .   # from the REPO ROOT
docker run --rm -p 8080:8080 \
  -e "ConnectionStrings__Postgres=Host=host.docker.internal;Port=5434;Database=tankbook;Username=tankbook;Password=tankbook" \
  -e ASPNETCORE_ENVIRONMENT=Development \
  tankbook-api:dev
curl 127.0.0.1:8080/health
```

**Build from the repository root, not from `backend/`.** `Tankbook.Api.csproj` embeds
`../../../docs/schemas/v1/*.schema.json`, so those files must be in the context; a `backend/`
context fails at restore. The root `.dockerignore` keeps that context at ~12 kB - unfiltered it is
3.1 GB, mostly `ios/.build`.

The image is the API only; Postgres and the S3 store are external. It runs as the non-root `app`
user, listens on 8080, and ships the *template* config - every secret blank, the non-secret
defaults kept - so credentials arrive as environment variables (`Section__Key`) and are never baked
into a layer. Outside Development the startup guard refuses to boot without the real secrets, in
the container exactly as on a host.

## Test

```sh
cd backend && dotnet build && dotnet test
```

Configuration: `ConnectionStrings:Postgres` and `S3` options bind from appsettings + environment variables (`ConnectionStrings__Postgres`, `S3__Endpoint`, ...). Local dev defaults live in `appsettings.Development.json`; never commit real credentials.

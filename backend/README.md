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

## CI and the self-hosted runner

`.github/workflows/backend.yml` splits by event, and the split is a security
boundary rather than a preference:

| Job | Event | Runner | What runs |
|---|---|---|---|
| `pr-gate` | `pull_request` | `ubuntu-latest` | build, test, format, image build - no host access |
| `build` | `push` | `self-hosted` | the gate, then the image build (and push, if a registry is configured) |
| `deploy` | `push` to `main` | `self-hosted` | pulls or reuses that image and hands it the serving port |

**Build and deploy are separate jobs on one host today, and the registry is
optional.** With both on the same machine the image never has to leave it, so an
unset `YC_REGISTRY_ID` simply builds a local tag. Set it - plus `YC_CI_SA_KEY`
and `YC_DEPLOY_SA_KEY` - and the same jobs push and pull through Yandex
Container Registry instead. Moving the build onto its own machine is then a
label change and nothing else. The registry (`tankbook`) and two service
accounts already exist: `tankbook-ci` can push, `tankbook-deployer` can only
pull, so a compromised deploy host cannot poison the registry.

**Pull requests never touch the self-hosted runner.** This repository is public,
so a `pull_request` job there would execute a stranger's code on the deploy host,
next to the runner token and the containers holding the production database
credential. `deploy-landing.yml` splits the same way and for the same reason.

Push builds, gates and deploys in **one** job on that host, so the bytes that
passed the suite are the bytes that run - a build/deploy split across runners can
ship an artifact nobody re-checked.

**What the runner must provide** (the job asserts all of it up front and names
the fix rather than failing three steps later):

- `dotnet` 10, `docker`, `curl`
- the runner user in the `docker` group - the suite uses Testcontainers for
  Postgres, and the deploy drives docker directly
- a writable `/opt/tankbook/api`
- an external nginx proxying to `127.0.0.1:17080` on that host
  (`backend/deploy/nginx/api.tankbook.live.conf`)

**The deploy is pinned to one machine.** `runs-on` is
`[self-hosted, tankbook-api, secondary-tankbook-api]`: `runs-on` cannot address a
runner by name, so the host-specific label is the only way to say "this runner
and no other". That matters because the job is not portable - it owns port 17080,
`/opt/tankbook/api` and the blue/green containers, and a second runner carrying
`tankbook-api` would deploy into a machine holding none of it while nginx kept
proxying to the old host. Moving hosts means changing the workflow line and the
runner's labels together.

Register the runner with `sudo bash backend/scripts/install-runner.sh`. It
installs docker, the .NET 10 SDK and curl, creates an unprivileged `tankbook-runner`
user in the docker group, prepares `/opt/tankbook/api`, and registers the runner
as a **service** so it survives a reboot. The label is `tankbook-api`, not bare
`self-hosted`: `deploy-landing.yml` also asks for `self-hosted`, so a bare label
would let the site deploy land on this host and fail for want of Hugo.

**Ports are 17080 (serving) and 17081 (verification), not 8080/8090.** The host
runs other containers, and the deploy refuses to start when either port is held
by a container that is not ours - proxying to somebody else's service would be
worse than failing. Change them together with the nginx upstream.

**This host is memory-constrained, and that has bitten twice.** On 2026-09-02 the
runner was OOM-killed mid-job (unit peak 1.2 GB) while the same machine served the
API and ran Postgres; an earlier run had timed out against Postgres for the same
underlying reason. Three mitigations are in place - `xUnit.MaxParallelThreads=2`,
`DOTNET_gcServer=0` for the test run, and workstation GC in the runtime image -
plus a systemd drop-in that restarts the runner and throttles it with
`MemoryHigh`. **None of them is the fix.** The full suite does not belong on the
machine that serves production; moving the `build` job to its own runner is, and
the workflow is already shaped for it.

The suite is also checked for **skips**, not just for green: without working
docker the 153 Postgres-backed tests report as skipped and `dotnet test` still
prints `Passed!`. The job reads `notExecuted` out of the TRX and fails the deploy
if it is non-zero, so the gate cannot silently shrink to the half that needs no
database.

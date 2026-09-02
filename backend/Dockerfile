# The Tankbook API, and only the API. Postgres and the S3-compatible store are
# external services (docs/SYNC.md: the blob provider is an ops choice behind the
# S3 API), so nothing here starts a database.
#
# BUILD FROM THE REPOSITORY ROOT, not from backend/:
#
#   docker buildx build --platform linux/amd64 -f backend/Dockerfile -t tankbook-api:<tag> .
#
# NOTE the --platform: the deploy host is x86_64 and the builder may not be.
#
# That is not a preference. Tankbook.Api.csproj embeds
# ../../../docs/schemas/v1/*.schema.json - the canonical payload schemas that
# migration 002 inserts into payload_schemas - so those files must be inside the
# build context. A context of backend/ cannot see them and the build fails at
# restore. The repo-root .dockerignore is what keeps that context small: without
# it the context is 3.1 GB, 2 GB of which is ios/.build.
#
#   docker run --rm -p 8080:8080 \
#     -e ConnectionStrings__Postgres="Host=...;Database=tankbook;Username=tankbook_app;Password=...;SSL Mode=Require" \
#     -e S3__AccessKey=... -e S3__SecretKey=... \
#     -e Tankbook__Logging__HashSalt=... -e Config__SigningKey=... \
#     -e Auth__JwtSigningKeyBase64=... \
#     -e Auth__AppleAudiences__0=app.tankbook.Tankbook \
#     tankbook-api:<tag>
#
# The double underscore is ASP.NET's nesting separator: Config__SigningKey binds
# to the "Config:SigningKey" this repo's docs name everywhere.

# --- build ------------------------------------------------------------------
# CROSS-COMPILES, because the build host and the deploy host are different
# architectures (2026-09-03): the builder is aarch64 and the server is x86_64.
# An image built natively on the builder simply does not run there - and the
# failure is `exec format error` at `docker run`, after a green build and a
# successful push, which reads as a broken image rather than a wrong platform.
#
# `--platform=$BUILDPLATFORM` pins the SDK stage to the BUILDER's native
# architecture and `dotnet publish -r $TARGETARCH` emits code for the TARGET.
# The alternative - running the whole SDK stage under QEMU emulation - produces
# the same bytes several times slower, which on a shared builder is the
# difference between a two-minute and a twenty-minute deploy.
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG TARGETARCH
WORKDIR /src

# Project files first, so `restore` is cached and only re-runs when a dependency
# changes - editing a .cs file must not re-download the NuGet graph.
COPY backend/Tankbook.slnx ./
COPY backend/src/Tankbook.Api/Tankbook.Api.csproj src/Tankbook.Api/
# The runtime identifier must be restored for too, or publish re-restores it.
RUN dotnet restore src/Tankbook.Api/Tankbook.Api.csproj -r linux-$TARGETARCH

COPY backend/src/ src/
# Outside backend/, and required: the csproj embeds these by relative path.
COPY docs/schemas/ ../docs/schemas/

# appsettings.json is gitignored (docs/SECURITY.md) and therefore absent from a
# clean checkout, so the image would otherwise ship without the NON-SECRET
# defaults the template carries - the S3 endpoint and bucket, the LLM base URL
# and model, the APNs endpoint, the nudge throttle. Rendering the template gives
# the container those defaults with every secret blank; real values arrive as
# environment variables at `docker run`, which override the file.
#
# Deliberately NOT running generate-appsettings.sh: that script reads secrets
# from the environment, and a secret passed at BUILD time is baked into an image
# layer, where `docker history` will show it. Build-time defaults only.
RUN cp src/Tankbook.Api/appsettings.template.json src/Tankbook.Api/appsettings.json && \
    rm -f src/Tankbook.Api/appsettings.Development.json \
          src/Tankbook.Api/appsettings.Development.template.json

# --self-contained false: the runtime image already carries the .NET runtime,
# so this ships IL plus a target-architecture apphost, not a second copy of the
# framework.
RUN dotnet publish src/Tankbook.Api/Tankbook.Api.csproj \
    --configuration Release \
    -r linux-$TARGETARCH \
    --self-contained false \
    --no-restore \
    --output /app

# --- runtime ----------------------------------------------------------------
# No --platform here on purpose: this stage IS the target, so buildx resolves it
# from --platform on the command line (linux/amd64 for our deploy host).
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

# Npgsql probes for GSSAPI while opening a connection, and without this library
# it prints `Error: libgssapi_krb5.so.2: cannot open shared object file` on
# every run. It is harmless - password auth succeeds and the migrations apply -
# but it appears on stderr as "Error:" at the top of every deploy, and a deploy
# that always prints an error is a deploy where nobody reads the errors. One
# package, installed as root before dropping to the app user.
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgssapi-krb5-2 \
    && rm -rf /var/lib/apt/lists/*

# The runtime image ships a non-root `app` user (UID 1654). Used rather than
# root because this process holds the database credential and the S3 key: a
# container escape should not also be a root shell.
USER $APP_UID

# Workstation GC, not server GC (changed 2026-09-02 after an OOM kill).
# Server GC allocates a heap PER LOGICAL CORE and holds on to memory to trade it
# for throughput - a good deal on a machine that exists to serve, a bad one here,
# where the API shares a host with a runner, Postgres and other containers, and
# where the blue-green handover briefly runs TWO of these at once. Throughput is
# not this app's constraint; a few dozen requests a minute is.
# Set DOTNET_gcServer=1 again on a host dedicated to the API.
ENV ASPNETCORE_HTTP_PORTS=8080 \
    ASPNETCORE_ENVIRONMENT=Production \
    DOTNET_gcServer=0
EXPOSE 8080

COPY --from=build /app .

# No HEALTHCHECK instruction on purpose. The runtime image carries neither curl
# nor wget, and installing one to probe a port would add an apt layer and a CVE
# surface to every deploy. `GET /health` is polled from OUTSIDE the container by
# the deploy script, which is where the answer has to be read anyway: blue-green
# has to decide whether to shift traffic, and a container reporting itself
# healthy to itself cannot make that call.
#
# Note the app applies pending migrations at startup (MigrationHostedService,
# with capped backoff), so a fresh container against an empty database migrates
# it. During a blue-green window BOTH colours run against ONE database, so every
# migration must be backward compatible with the version still serving.
ENTRYPOINT ["dotnet", "Tankbook.Api.dll"]

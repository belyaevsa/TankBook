#!/usr/bin/env bash
# Provisions a host to be the Tankbook API build-and-deploy runner, and registers
# it with GitHub Actions as a service.
#
#   sudo bash backend/scripts/install-runner.sh
#
# It installs what .github/workflows/backend.yml asserts (docker, the .NET 10
# SDK, curl), creates the unprivileged runner user, prepares /opt/tankbook/api,
# then downloads and registers the runner. Safe to re-run: every step checks for
# what it would create, and re-registration uses --replace.
#
# THE REGISTRATION TOKEN is short-lived (about an hour) and is NOT a secret you
# store. The script mints one with `gh` if that is installed and authenticated;
# otherwise pass one from
# Settings -> Actions -> Runners -> New self-hosted runner:
#
#   RUNNER_TOKEN=AXXXX... sudo -E bash backend/scripts/install-runner.sh
#
# IF A PREVIOUS ATTEMPT LEFT A BROKEN /opt/actions-runner, that directory is not
# used any more - this installs to /opt/actions-runner-tankbook-api instead. The
# old one can simply be removed once you have confirmed no other runner lives
# there:
#
#   sudo ls /opt/actions-runner            # a .runner file means it is registered
#   sudo rm -rf /opt/actions-runner        # only if it holds nothing you need
#
# THE LABEL MATTERS. The runner is registered with `tankbook-api`, and the
# backend workflow asks for `[self-hosted, tankbook-api]`. Without a distinct
# label, this runner would also match deploy-landing.yml's bare `self-hosted`
# and the site deploy could land here - on a host with no Hugo - failing in a way
# that reads as a broken site build rather than a misrouted job.
set -euo pipefail

REPO="${RUNNER_REPO:-belyaevsa/TankBook}"
RUNNER_USER="${RUNNER_USER:-tankbook-runner}"
# Runner-SPECIFIC, not the generic /opt/actions-runner. That path is what every
# other runner on a host also picks, and this script would then reconfigure
# somebody else's runner - on this host, plausibly the landing-site one, which
# `--replace` could unregister.
RUNNER_HOME="${RUNNER_HOME:-/opt/actions-runner-tankbook-api}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,linux,x64,tankbook-api}"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)-tankbook-api}"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/tankbook/api}"

log()  { printf '\n== %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "run with sudo - this installs packages and a systemd service"
command -v apt-get >/dev/null 2>&1 || fail "this script assumes Debian/Ubuntu (apt-get)"

# --- 1. packages ------------------------------------------------------------
log "installing prerequisites"
apt-get update -qq
apt-get install -y --no-install-recommends \
    ca-certificates curl jq tar gzip sudo

# Docker from Docker's own repository rather than the distro's: the distro
# package lags, and the deploy drives docker directly.
if ! command -v docker >/dev/null 2>&1; then
    log "installing docker"
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
    systemctl enable --now docker
else
    echo "docker present: $(docker --version)"
fi

# The .NET SDK, because the workflow builds and tests on this host rather than
# shipping an artifact from elsewhere.
if ! command -v dotnet >/dev/null 2>&1; then
    log "installing the .NET 10 SDK"
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    bash /tmp/dotnet-install.sh --channel 10.0 --install-dir /usr/share/dotnet
    ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet
    rm -f /tmp/dotnet-install.sh
else
    echo "dotnet present: $(dotnet --version)"
fi

# --- 2. the runner user -----------------------------------------------------
# Unprivileged, and in the docker group. GitHub's config.sh refuses to run as
# root, and this process builds images and drives the deploy - it should not also
# be able to become root outright.
if ! id -u "$RUNNER_USER" >/dev/null 2>&1; then
    log "creating ${RUNNER_USER}"
    useradd --system --create-home --shell /bin/bash "$RUNNER_USER"
fi
usermod -aG docker "$RUNNER_USER"

# NOTE, stated rather than buried: membership of the docker group is equivalent
# to root on this host - the group can start a container that mounts /. That is
# inherent to a runner that deploys containers, and it is the reason PULL
# REQUESTS MUST NEVER RUN HERE (backend.yml keeps them on ubuntu-latest).

log "preparing ${DEPLOY_DIR}"
mkdir -p "$DEPLOY_DIR"
chown -R "$RUNNER_USER":"$RUNNER_USER" "$(dirname "$DEPLOY_DIR")"

# --- 3. the runner itself ---------------------------------------------------
# A directory that already holds a CONFIGURED runner is somebody's - possibly
# another repo's. Refuse rather than --replace it into ours.
if [ -f "${RUNNER_HOME}/.runner" ] && [ "${RUNNER_ADOPT:-0}" != "1" ]; then
    existing="$(jq -r '.gitHubUrl // .serverUrl // "unknown"' "${RUNNER_HOME}/.runner" 2>/dev/null || echo unknown)"
    fail "${RUNNER_HOME} already holds a runner configured for ${existing}.
  Re-registering would take it over. Use a different RUNNER_HOME, or
  RUNNER_ADOPT=1 if you are certain this runner is meant to be replaced."
fi

# `config.sh` existing is NOT proof the runner is usable: an interrupted download
# leaves the scripts without bin/, and the failure then reads as a permissions or
# ldd error deep inside config.sh rather than as a broken unpack. Check for the
# actual binary, and re-extract when it is missing.
if [ -x "${RUNNER_HOME}/bin/Runner.Listener" ]; then
    echo "runner already unpacked at ${RUNNER_HOME}"
elif [ -d "$RUNNER_HOME" ] && [ -f "${RUNNER_HOME}/config.sh" ]; then
    log "${RUNNER_HOME} is incomplete (no bin/Runner.Listener) - re-extracting"
    rm -rf "${RUNNER_HOME:?}"/*
    NEEDS_DOWNLOAD=1
else
    NEEDS_DOWNLOAD=1
fi

if [ "${NEEDS_DOWNLOAD:-0}" = "1" ]; then
    log "downloading the runner"
    mkdir -p "$RUNNER_HOME"
    version="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest \
        | jq -r .tag_name | sed 's/^v//')"
    [ -n "$version" ] && [ "$version" != "null" ] || fail "could not resolve the latest runner version"
    arch="$(dpkg --print-architecture)"
    case "$arch" in
        amd64) rid="x64" ;;
        arm64) rid="arm64" ;;
        *) fail "unsupported architecture ${arch}" ;;
    esac
    echo "runner ${version} (${rid})"
    curl -fsSL -o /tmp/runner.tar.gz \
        "https://github.com/actions/runner/releases/download/v${version}/actions-runner-linux-${rid}-${version}.tar.gz"
    tar xzf /tmp/runner.tar.gz -C "$RUNNER_HOME"
    rm -f /tmp/runner.tar.gz
    [ -x "${RUNNER_HOME}/bin/Runner.Listener" ] \
        || fail "the runner archive extracted without bin/Runner.Listener - the download was truncated"
fi

# ALWAYS, not only after a download. The first version chowned inside the
# download branch alone, so a run that skipped the download left the directory
# owned by root - and every write then failed: `.path: Permission denied`,
# `_diag/...log' is denied`, and an aborted config.sh. The runner writes .path,
# .env, _diag and _work in here every time it starts, so ownership is not a
# one-off setup detail.
chown -R "$RUNNER_USER":"$RUNNER_USER" "$RUNNER_HOME"

# --- 4. registration token --------------------------------------------------
# Minted here rather than pasted where possible: a token typed into a shell ends
# up in that shell's history.
if [ -z "${RUNNER_TOKEN:-}" ]; then
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        log "minting a registration token with gh"
        RUNNER_TOKEN="$(gh api -X POST "repos/${REPO}/actions/runners/registration-token" --jq .token)"
    else
        fail "no RUNNER_TOKEN and gh is not authenticated here.
  Get one from https://github.com/${REPO}/settings/actions/runners/new
  then:  RUNNER_TOKEN=<token> sudo -E bash backend/scripts/install-runner.sh"
    fi
fi

log "registering ${RUNNER_NAME} with labels ${RUNNER_LABELS}"
# Run from INSIDE the directory: config.sh sources ./env.sh, which writes `.path`
# relative to the working directory - that is what produced
# `./env.sh: line 37: .path: Permission denied`.
#
# The token travels in the ENVIRONMENT, never in argv. A `--token X` on a command
# line is visible in `ps` to every user on the host, and this one can register a
# runner against the repository. Everything else is positional, so no value is
# interpolated into the shell string either.
export RUNNER_TOKEN
sudo -u "$RUNNER_USER" --preserve-env=RUNNER_TOKEN \
    bash -c 'cd "$1" && ./config.sh \
        --unattended \
        --replace \
        --url "$2" \
        --token "$RUNNER_TOKEN" \
        --name "$3" \
        --labels "$4" \
        --work _work' \
    _ "$RUNNER_HOME" "https://github.com/${REPO}" "$RUNNER_NAME" "$RUNNER_LABELS"

# --- 5. run it as a service -------------------------------------------------
# So it survives a reboot. Without this the runner lives only as long as the
# shell that started it, and the first reboot silently stops all deploys.
log "installing the service"
# FROM INSIDE THE DIRECTORY, like config.sh. svc.sh checks its working directory
# and refuses with "Must run from runner root or install is corrupt" when called
# by absolute path - which says "corrupt" and means "wrong cwd", so it reads as a
# broken download. Run as root: it writes a systemd unit and enables it.
cd "$RUNNER_HOME"
./svc.sh install "$RUNNER_USER"
./svc.sh start
./svc.sh status || true

cat <<EOF

Runner registered.

  name    ${RUNNER_NAME}
  labels  ${RUNNER_LABELS}
  user    ${RUNNER_USER}
  deploy  ${DEPLOY_DIR}

Still required before a deploy can succeed:

  1. Repository secrets: POSTGRES_CONNECTION, S3_ACCESS_KEY, S3_SECRET_KEY,
     TANKBOOK_HASH_SALT, CONFIG_SIGNING_KEY, AUTH_JWT_SIGNING_KEY, LLM_API_KEY
     (backend/scripts/generate-secrets.sh --gh-set mints three of them)
  2. Repository variables: APPLE_AUDIENCE, GOOGLE_AUDIENCE - these FAIL CLOSED,
     so sign-in refuses every token until they are set
  3. nginx proxying to 127.0.0.1:8080 - see backend/deploy/nginx/
  4. The database: backend/scripts/provision-database.sql

Verify the runner appears at:
  https://github.com/${REPO}/settings/actions/runners
EOF

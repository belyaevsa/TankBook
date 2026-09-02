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
# THE LABELS MATTER, and there are two of them for two different reasons.
#
#   tankbook-api            keeps OTHER workflows off this host. deploy-landing.yml
#                           asks for bare `self-hosted`, so without a distinct
#                           label the site deploy could land here - on a machine
#                           with no Hugo - failing in a way that reads as a broken
#                           site build rather than a misrouted job.
#   <hostname>-<role>      addresses ONE machine. The workflow does not ask for
#                          it while there is a single runner per role - a
#                          hostname in a workflow is a rename waiting to break
#                          it - but it is registered so a second runner of the
#                          same role can be disambiguated the day one exists. The
#                           backend deploy owns a fixed port, a state directory
#                           and the blue/green containers; a second runner
#                           carrying `tankbook-api` would be an eligible target
#                           and would deploy into a machine holding none of that.
#
# backend.yml asks for all three, so both directions are pinned.
set -euo pipefail

# ROLE decides what this host is for (2026-09-03, two machines):
#
#   deploy  (default)  x86_64, serves api.tankbook.live. Owns port 17080,
#                      /opt/tankbook/api and the blue/green containers.
#   build              aarch64. Runs the suite and cross-builds the image for
#                      the deploy host's amd64. Needs NO deploy directory and no
#                      production secrets - which is the point of moving it here.
#
#   RUNNER_ROLE=build sudo -E bash backend/scripts/install-runner.sh
ROLE="${RUNNER_ROLE:-deploy}"
case "$ROLE" in
  deploy|build) ;;
  *) printf 'error: RUNNER_ROLE must be deploy or build\n' >&2; exit 1 ;;
esac

REPO="${RUNNER_REPO:-belyaevsa/TankBook}"
RUNNER_USER="${RUNNER_USER:-tankbook-runner}"
# Runner-SPECIFIC, not the generic /opt/actions-runner. That path is what every
# other runner on a host also picks, and this script would then reconfigure
# somebody else's runner - on this host, plausibly the landing-site one, which
# `--replace` could unregister.
RUNNER_HOME="${RUNNER_HOME:-/opt/actions-runner-tankbook-${ROLE}}"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)-tankbook-${ROLE}}"
# The runner's own NAME is also registered as a label, and that is what pins the
# workflow to this one machine. `runs-on` cannot address a runner by name -
# GitHub matches on labels only - so a label unique to this host is the only way
# to say "this runner and no other". Without it, `tankbook-api` on a second
# runner would silently become an eligible target for the deploy.
# The architecture label is REPORTED, not assumed: this repo now spans x86_64
# and aarch64 hosts, and a wrong arch label would route a job to a machine that
# cannot run what it produces.
case "$(dpkg --print-architecture)" in
  amd64) ARCH_LABEL="x64" ;;
  arm64) ARCH_LABEL="arm64" ;;
  *)     ARCH_LABEL="$(dpkg --print-architecture)" ;;
esac
ROLE_LABEL="$([ "$ROLE" = build ] && echo tankbook-build || echo tankbook-api)"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,linux,${ARCH_LABEL},${ROLE_LABEL},${RUNNER_NAME}}"
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

if [ "$ROLE" = deploy ]; then
    log "preparing ${DEPLOY_DIR}"
    mkdir -p "$DEPLOY_DIR"
    chown -R "$RUNNER_USER":"$RUNNER_USER" "$(dirname "$DEPLOY_DIR")"
else
    # A build host never deploys, so it gets no deploy directory and needs none
    # of the production secrets. That separation is the reason it exists.
    log "build role: skipping ${DEPLOY_DIR}"
fi

# --- 3. the runner itself ---------------------------------------------------
# A directory holding a runner configured for ANOTHER repository is somebody
# else's - refuse rather than --replace it into ours. One already configured for
# THIS repository is our own previous run, and re-registering it is exactly what
# --replace is for, so that case proceeds: the script has to be re-runnable, and
# an earlier version of this guard blocked the very runner it had just
# registered.
if [ -f "${RUNNER_HOME}/.runner" ] && [ "${RUNNER_ADOPT:-0}" != "1" ]; then
    existing="$(jq -r '.gitHubUrl // .serverUrl // ""' "${RUNNER_HOME}/.runner" 2>/dev/null || echo "")"
    ours="https://github.com/${REPO}"
    # Trailing slash and case are not differences worth refusing over.
    normalise() { printf '%s' "${1%/}" | tr '[:upper:]' '[:lower:]'; }
    if [ -n "$existing" ] && [ "$(normalise "$existing")" != "$(normalise "$ours")" ]; then
        fail "${RUNNER_HOME} already holds a runner configured for ${existing}, not ${ours}.
  Re-registering would take it over. Use a different RUNNER_HOME, or
  RUNNER_ADOPT=1 if you are certain this runner is meant to be replaced."
    fi
    echo "re-registering the existing runner for ${ours}"
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
# The build host cross-compiles for another architecture, so buildx must be
# present and usable. Asserted rather than assumed: without it the build fails
# at `docker buildx`, which reads as a docker problem rather than a missing
# plugin.
if [ "$ROLE" = build ]; then
    docker buildx version >/dev/null 2>&1 \
        || fail "docker buildx is not available - the build host cross-compiles for linux/amd64 and needs it"
    echo "buildx: $(docker buildx version | head -1)"
fi

log "installing the service"
# FROM INSIDE THE DIRECTORY, like config.sh. svc.sh checks its working directory
# and refuses with "Must run from runner root or install is corrupt" when called
# by absolute path - which says "corrupt" and means "wrong cwd", so it reads as a
# broken download. Run as root: it writes a systemd unit and enables it.
cd "$RUNNER_HOME"
./svc.sh install "$RUNNER_USER"

# RESTART ON FAILURE. GitHub's generated unit does not set Restart=, so a runner
# killed by the OOM killer exits and stays dead - which is what happened on
# 2026-09-02: the listener was OOM-killed mid-job, logged "no retry needed", and
# the host went on serving with no runner at all until someone noticed. A deploy
# pipeline that silently stops accepting jobs is worse than one that fails loudly.
#
# MemoryHigh is a THROTTLE, not a kill: past it the kernel reclaims harder and
# the job slows down, which is the behaviour we want on a box that also serves
# production. It deliberately does not set MemoryMax, because a hard cap turns a
# slow build into a failed one, and the unit already peaked at 1.2 GB legitimately.
unit="actions.runner.$(sed 's|/|-|g' <<< "${REPO}").${RUNNER_NAME}.service"
dropin="/etc/systemd/system/${unit}.d"
mkdir -p "$dropin"
cat > "${dropin}/override.conf" <<EOF
[Service]
Restart=always
RestartSec=15
# Soft memory ceiling: throttle this unit before the kernel starts choosing
# victims elsewhere on the host - the API container is the one thing that must
# not be chosen.
MemoryHigh=${RUNNER_MEMORY_HIGH:-2G}
EOF
systemctl daemon-reload
echo "  wrote ${dropin}/override.conf (Restart=always, MemoryHigh=${RUNNER_MEMORY_HIGH:-2G})"

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

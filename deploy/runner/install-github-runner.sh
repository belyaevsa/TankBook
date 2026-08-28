#!/usr/bin/env bash
#
# Install and register the GitHub Actions self-hosted runner on this host, as a
# systemd service, with everything the deploy job needs.
#
#   sudo bash deploy/runner/install-github-runner.sh <REGISTRATION_TOKEN>
#
# Get the token from:
#   https://github.com/belyaevsa/TankBook/settings/actions/runners/new
# It expires about an hour after it is generated, so fetch it immediately before
# running this. It is deliberately an ARGUMENT and never written to a file - a
# token committed to a repository is a token published.
#
# Everything lives under one tree, so there is a single thing to back up, move
# or delete:
#
#   /opt/tankbook/
#     runner/              the GitHub Actions runner and its _work directory
#     releases/<sha>/      one built site per deployed commit
#     latest -> releases/<sha>    what nginx serves
#
# Safe to re-run: --replace re-registers the same runner name rather than adding
# a duplicate, and each install step checks before acting.

set -euo pipefail

REPO_URL="https://github.com/belyaevsa/TankBook"
RUNNER_VERSION="2.336.0"
RUNNER_SHA256="04cf0be1aff4c3ec3554466c39124ca250e3effd8873bb7e8d68535aa9505d5d"
HUGO_VERSION="0.153.4"

RUNNER_USER="github-runner"
TANKBOOK_ROOT="/opt/tankbook"
RUNNER_HOME="${TANKBOOK_ROOT}/runner"
DEPLOY_ROOT="${TANKBOOK_ROOT}"
RUNNER_NAME="$(hostname -s)"

TOKEN="${1:-}"
if [ -z "$TOKEN" ]; then
  echo "usage: sudo bash $0 <REGISTRATION_TOKEN>" >&2
  echo "get one at ${REPO_URL}/settings/actions/runners/new (expires in ~1 hour)" >&2
  exit 2
fi
if [ "$(id -u)" -ne 0 ]; then
  echo "run me with sudo - I create a user and a systemd service" >&2
  exit 2
fi

say() { printf '\n== %s\n' "$*"; }

# --- 1. a dedicated unprivileged user ---------------------------------------
# The runner must NOT run as root: config.sh refuses outright unless
# RUNNER_ALLOW_RUNASROOT is set, and that refusal is correct. Workflow jobs
# execute arbitrary repository code, so this account is the blast radius.
say "user ${RUNNER_USER}"
if id "$RUNNER_USER" >/dev/null 2>&1; then
  echo "   exists"
else
  useradd --system --create-home --home-dir "$RUNNER_HOME" --shell /bin/bash "$RUNNER_USER"
  echo "   created"
fi
mkdir -p "$RUNNER_HOME"
chown "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME"

# --- 2. the deploy target ----------------------------------------------------
# The deploy job writes releases here and flips the `latest` symlink. Note what
# it does NOT need: any sudo, and any nginx reload. nginx resolves the symlink
# per request and open_file_cache is deliberately off, so a release swap needs
# no privileged action at all. That is why this account gets no sudoers entry -
# adding one would hand arbitrary workflow code a root path for no benefit.
say "deploy root ${DEPLOY_ROOT}/releases"
mkdir -p "${DEPLOY_ROOT}/releases"
chown -R "$RUNNER_USER:$RUNNER_USER" "$DEPLOY_ROOT"
chmod 755 "$DEPLOY_ROOT" "${DEPLOY_ROOT}/releases"
echo "   owned by ${RUNNER_USER}, world-readable so nginx can serve it"

# --- 3. the runner package ---------------------------------------------------
say "actions runner ${RUNNER_VERSION}"
TARBALL="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
if [ -x "${RUNNER_HOME}/config.sh" ]; then
  echo "   already extracted"
else
  cd "$RUNNER_HOME"
  curl -fsSL -o "$TARBALL" \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${TARBALL}"
  # NOT optional, whatever the setup page says: this is the one moment the
  # supply chain is checkable, and an unverified tarball becomes a service
  # running as a user with write access to what the web server serves.
  echo "${RUNNER_SHA256}  ${TARBALL}" | sha256sum -c -
  tar xzf "$TARBALL"
  rm -f "$TARBALL"
  chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME"
  echo "   downloaded, checksum verified, extracted"
fi

say "runner OS dependencies"
if [ -x "${RUNNER_HOME}/bin/installdependencies.sh" ]; then
  "${RUNNER_HOME}/bin/installdependencies.sh" >/dev/null
  echo "   ok"
fi

# --- 4. Hugo, pinned ---------------------------------------------------------
# The workflow asserts this exact version and fails the job if it differs. That
# is not fussiness: the site's layouts use Hugo's 0.146+ flattened structure, and
# an older Hugo does not error - it fails to find them and renders a wrong page
# that every later step reports as a successful deploy. Ubuntu's apt Hugo is far
# too old, so install the release build directly.
say "hugo extended ${HUGO_VERSION}"
if command -v hugo >/dev/null 2>&1 && hugo version | grep -q "v${HUGO_VERSION}"; then
  echo "   already correct: $(hugo version | cut -c1-40)"
else
  DEB="hugo_extended_${HUGO_VERSION}_linux-amd64.deb"
  curl -fsSL -o "/tmp/${DEB}" \
    "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/${DEB}"
  dpkg -i "/tmp/${DEB}" >/dev/null
  rm -f "/tmp/${DEB}"
  echo "   installed: $(hugo version | cut -c1-40)"
fi

# The gate script uses these. Missing xmllint or python3 turns a real check into
# a silent skip, which is worse than a failure.
say "gate dependencies"
apt-get install -y --no-install-recommends libxml2-utils python3 git curl >/dev/null
echo "   libxml2-utils, python3, git, curl"

# --- 5. register -------------------------------------------------------------
# --unattended so it never waits on a prompt, --replace so re-running this
# re-registers the same name instead of accumulating dead runners.
say "registering ${RUNNER_NAME} with ${REPO_URL}"
sudo -u "$RUNNER_USER" bash -c "cd '$RUNNER_HOME' && ./config.sh \
  --url '$REPO_URL' \
  --token '$TOKEN' \
  --name '$RUNNER_NAME' \
  --labels self-hosted,Linux,X64,tankbook-deploy \
  --work _work \
  --unattended \
  --replace"

# --- 6. run as a service -----------------------------------------------------
# ./run.sh dies with the shell that started it. The service survives reboots,
# which is the difference between a runner and a demo.
say "systemd service"
cd "$RUNNER_HOME"
./svc.sh install "$RUNNER_USER"
./svc.sh start
sleep 2
./svc.sh status || true

cat <<EOF

== done

Verify, in this order - each answers a different question:

  1. Is the service actually up?
       sudo systemctl status 'actions.runner.*' --no-pager | head -20

  2. Does GitHub see it as Idle (not just "created")?
       ${REPO_URL}/settings/actions/runners

  3. Can it really build?  Push a change under site/, or:
       gh workflow run 'Deploy landing -> tankbook.live'

  4. Did the deploy land where nginx looks?
       ls -l ${DEPLOY_ROOT}/latest && curl -sI https://tankbook.live/ | head -1

Notes worth keeping:

  - This runner has NO sudo. The deploy needs none: it writes a release
    directory and flips a symlink, and nginx picks that up per request.
    If a future job needs a privileged action, add a single narrow sudoers
    rule for that exact command - never blanket sudo. Workflow code is
    arbitrary code.

  - belyaevsa/TankBook is PUBLIC. The workflow deliberately runs
    pull_request jobs on ubuntu-latest and only push-to-main here, so a
    stranger's PR cannot execute on this machine. Keep it that way.

  - Swift is not installed, so the design-token drift check prints a notice
    and skips rather than failing. Install Swift if you want that gate real
    on the server; it is checked locally either way.

EOF

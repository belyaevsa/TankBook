#!/usr/bin/env bash
# Deploys the Tankbook API container behind an EXTERNAL, unmanaged nginx.
#
#   bash backend/scripts/deploy-blue-green.sh <image-tag>
#
# nginx is separate, outside this repo and not in a container, so this script
# never edits or reloads it. That is what fixes the shape: nginx proxies forever
# to ONE fixed port on this host, and the deploy swaps which container holds it.
#
#   nginx (external)  ->  127.0.0.1:8080  ->  tankbook-api-{blue|green}
#
# A port cannot be rebound on a running container, so the handover is: verify the
# new colour on a SCRATCH port, stop it, stop the old one, start the new one on
# the real port. Connections are refused for roughly a second in the middle.
# That is a deliberate trade, chosen 2026-09-02: it keeps nginx untouched and
# adds no long-lived proxy of our own. **This is not zero-downtime** - do not
# describe it as such, and do not deploy during a spike expecting otherwise.
#
# What the brief window buys, and what it does NOT:
#   - it DOES catch an image that cannot start, cannot reach the database, or
#     fails its health check: all of that happens on the scratch port, before
#     anything serving is touched.
#   - it does NOT catch a fault that only appears under real traffic. The
#     verified instance is not the serving instance - it is the same image and
#     the same environment, restarted.
#
# Plain `docker run`, no compose file (the repo's standing rule).
set -euo pipefail

IMAGE_TAG="${1:?usage: deploy-blue-green.sh <image-tag>}"
IMAGE="tankbook-api:${IMAGE_TAG}"

# Deliberately uncommon ports. This host runs other containers, and 8080/8090
# are the first thing anything else grabs - a collision would either fail the
# deploy confusingly or, worse, have nginx proxy to somebody else's service.
# Bound to 127.0.0.1 only; nginx is the sole public entrance.
SERVE_PORT="${TANKBOOK_SERVE_PORT:-17080}"     # what external nginx proxies to
SCRATCH_PORT="${TANKBOOK_SCRATCH_PORT:-17081}" # verification only, never public
STATE_DIR="${TANKBOOK_API_DIR:-/opt/tankbook/api}"
STATE_FILE="${STATE_DIR}/active"
HEALTH_ATTEMPTS="${TANKBOOK_HEALTH_ATTEMPTS:-40}"
HEALTH_DELAY="${TANKBOOK_HEALTH_DELAY:-3}"

log()  { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
fail() { printf '::error::%s\n' "$*" >&2; exit 1; }

wait_healthy() { # <port> <attempts>
    local port="$1" attempts="$2"
    for _ in $(seq 1 "$attempts"); do
        if curl -fsS -m 3 "http://127.0.0.1:${port}/health" 2>/dev/null | grep -q '"status":"ok"'; then
            return 0
        fi
        sleep "$HEALTH_DELAY"
    done
    return 1
}

command -v docker >/dev/null 2>&1 || fail "docker is not on this runner"
docker image inspect "$IMAGE" >/dev/null 2>&1 || fail "image ${IMAGE} was not built"
mkdir -p "$STATE_DIR" || fail "cannot create ${STATE_DIR}"

# Refuse to deploy if either port is held by something that is not ours. Without
# this, a foreign container on the serving port makes `docker run` fail with a
# bind error AFTER the old colour has already been stopped - the one moment in
# this script where a confusing failure costs real downtime. The scratch port
# matters too: verifying against somebody else's service would "pass".
port_owner() { # <port> -> container name, or empty
    docker ps --format '{{.Names}} {{.Ports}}' \
        | awk -v p=":$1->" '$0 ~ p {print $1; exit}'
}
for port in "$SERVE_PORT" "$SCRATCH_PORT"; do
    owner="$(port_owner "$port")"
    case "$owner" in
        ""|tankbook-api-*) ;;
        *) fail "port ${port} is held by container '${owner}', which is not ours - set TANKBOOK_SERVE_PORT/TANKBOOK_SCRATCH_PORT to free ports and point nginx at the new serving port" ;;
    esac
done

# Which colour currently holds the serving port. Read from docker rather than
# only from the state file: docker is what actually owns the port, and a state
# file that disagrees with it would send this script to replace the wrong
# container. The file is a hint for humans; the container list is the truth.
current_colour=""
for colour in blue green; do
    if docker ps --filter "name=tankbook-api-${colour}" --filter "status=running" --format '{{.Names}}' \
        | grep -q "tankbook-api-${colour}"; then
        current_colour="$colour"
        break
    fi
done

case "$current_colour" in
    blue)  target_colour="green" ;;
    green) target_colour="blue" ;;
    *)     target_colour="blue"; log "nothing is running - first deploy" ;;
esac
target_container="tankbook-api-${target_colour}"
old_container="${current_colour:+tankbook-api-${current_colour}}"

log "live=${current_colour:-none} -> deploying ${target_colour} from ${IMAGE}"

# --- environment ------------------------------------------------------------
# Written to a file rather than passed with -e so the secrets never appear in
# `ps` output on a host where other processes can read it.
ENV_FILE="$(mktemp)"
chmod 600 "$ENV_FILE"
cleanup() { rm -f "$ENV_FILE"; }
trap cleanup EXIT
cat > "$ENV_FILE" <<EOF
ConnectionStrings__Postgres=${POSTGRES_CONNECTION:-}
S3__AccessKey=${S3_ACCESS_KEY:-}
S3__SecretKey=${S3_SECRET_KEY:-}
Tankbook__Logging__HashSalt=${TANKBOOK_HASH_SALT:-}
Config__SigningKey=${CONFIG_SIGNING_KEY:-}
Auth__JwtSigningKeyBase64=${AUTH_JWT_SIGNING_KEY:-}
Auth__AppleAudiences__0=${APPLE_AUDIENCE:-}
Auth__GoogleAudiences__0=${GOOGLE_AUDIENCE:-}
LlmGateway__ApiKey=${LLM_API_KEY:-}
Database__AutoMigrate=false
EOF

# --- 1. migrate, as its own step -------------------------------------------
# Before any container is touched. The schema moves at one known moment with its
# own exit code, rather than as a side effect of whichever container starts
# first - which is what made boot-time migration wrong here (docs/SYNC.md).
# A non-zero exit stops the deploy with the old version still serving.
log "applying migrations"
docker run --rm --env-file "$ENV_FILE" \
    -e Database__AutoMigrate=true \
    "$IMAGE" --migrate \
    || fail "migrations failed; ${current_colour:-nothing} is still serving and no container was replaced"
log "migrations applied"

# --- 2. verify the new image on a scratch port ------------------------------
docker rm -f "${target_container}-verify" >/dev/null 2>&1 || true
docker run -d --name "${target_container}-verify" \
    --env-file "$ENV_FILE" \
    --publish "127.0.0.1:${SCRATCH_PORT}:8080" \
    "$IMAGE" >/dev/null || fail "could not start the verification container"

if ! wait_healthy "$SCRATCH_PORT" "$HEALTH_ATTEMPTS"; then
    log "--- last 50 log lines ---"
    docker logs --tail 50 "${target_container}-verify" 2>&1 || true
    docker rm -f "${target_container}-verify" >/dev/null 2>&1 || true
    fail "${IMAGE} never became healthy; ${current_colour:-nothing} is still serving and was not touched"
fi
log "verified on scratch port ${SCRATCH_PORT}"
docker rm -f "${target_container}-verify" >/dev/null 2>&1 || true

# --- 3. the handover (the brief window) -------------------------------------
# Everything that can be checked has been checked; from here the serving port
# changes hands. Kept as short as possible: two docker calls, no build, no pull.
if [ -n "$old_container" ]; then
    log "stopping ${old_container} - serving port changes hands now"
    docker stop -t 10 "$old_container" >/dev/null 2>&1 || true
fi

docker rm -f "$target_container" >/dev/null 2>&1 || true
if ! docker run -d --name "$target_container" \
        --env-file "$ENV_FILE" \
        --restart unless-stopped \
        --publish "127.0.0.1:${SERVE_PORT}:8080" \
        "$IMAGE" >/dev/null; then
    # Could not even start: put the old one back immediately.
    [ -n "$old_container" ] && docker start "$old_container" >/dev/null 2>&1 || true
    fail "could not start ${target_container} on ${SERVE_PORT}; rolled back to ${current_colour:-nothing}"
fi

# --- 4. prove the serving port answers, or roll back ------------------------
if ! wait_healthy "$SERVE_PORT" 15; then
    log "--- last 50 log lines ---"
    docker logs --tail 50 "$target_container" 2>&1 || true
    log "ROLLING BACK to ${current_colour:-nothing}"
    docker rm -f "$target_container" >/dev/null 2>&1 || true
    if [ -n "$old_container" ]; then
        docker start "$old_container" >/dev/null 2>&1 || true
        wait_healthy "$SERVE_PORT" 15 && log "rollback OK - ${current_colour} is serving again" \
            || log "::error::rollback did not become healthy either"
    fi
    fail "${target_colour} did not answer on ${SERVE_PORT}"
fi

printf '%s %s %s\n' "$target_colour" "$IMAGE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_FILE"
log "${target_colour} is serving ${IMAGE} on ${SERVE_PORT}"

# The old container is left STOPPED, not removed, and its image is kept by the
# prune below: `docker start tankbook-api-<old>` is then a one-command rollback
# once the new one is stopped.
[ -n "$old_container" ] && log "rollback: docker stop ${target_container} && docker start ${old_container}"

# Keep the three most recent images. A runner that never prunes fills its disk,
# and that surfaces weeks later as an unrelated build failure.
docker images tankbook-api --format '{{.Tag}} {{.ID}}' \
    | grep -v '^latest ' \
    | tail -n +4 \
    | awk '{print $2}' \
    | xargs -r docker rmi -f >/dev/null 2>&1 || true

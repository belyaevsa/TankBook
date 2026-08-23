#!/usr/bin/env bash
# Starts local Postgres 17 and MinIO for Tankbook backend development.
# Idempotent: safe to re-run; existing containers are detected and left running.
# Requires docker. No docker-compose, ever (project rule).
set -euo pipefail

POSTGRES_NAME="tankbook-postgres"
POSTGRES_IMAGE="postgres:17"
POSTGRES_PORT="5432"
POSTGRES_DB="tankbook"
POSTGRES_USER="tankbook"
POSTGRES_PASSWORD="tankbook"
POSTGRES_VOLUME="tankbook-postgres-data"

MINIO_NAME="tankbook-minio"
MINIO_IMAGE="minio/minio"
MINIO_API_PORT="9000"
MINIO_CONSOLE_PORT="9001"
MINIO_ROOT_USER="tankbook"
MINIO_ROOT_PASSWORD="tankbook123"
MINIO_BUCKET="tankbook"
MINIO_VOLUME="tankbook-minio-data"

docker info >/dev/null 2>&1 || { echo "ERROR: docker is not running or not installed." >&2; exit 1; }

echo "==> Tankbook local infrastructure (dev-up)"

# --- Postgres 17 ---------------------------------------------------------
if docker container inspect "$POSTGRES_NAME" >/dev/null 2>&1; then
    echo "Postgres 17 container '$POSTGRES_NAME' already running - leaving it alone."
else
    echo "Starting Postgres 17 on port $POSTGRES_PORT (db/user/password: $POSTGRES_DB/$POSTGRES_USER/$POSTGRES_PASSWORD)..."
    docker run -d \
        --name "$POSTGRES_NAME" \
        -e POSTGRES_DB="$POSTGRES_DB" \
        -e POSTGRES_USER="$POSTGRES_USER" \
        -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        -p "$POSTGRES_PORT:5432" \
        -v "$POSTGRES_VOLUME:/var/lib/postgresql/data" \
        --health-cmd "pg_isready -U $POSTGRES_USER -d $POSTGRES_DB" \
        "$POSTGRES_IMAGE" >/dev/null
    echo "Postgres 17 container '$POSTGRES_NAME' started."
fi

# Wait for Postgres to accept connections.
for _ in $(seq 1 20); do
    status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' "$POSTGRES_NAME" 2>/dev/null || echo "starting")
    [ "$status" = "healthy" ] && break
    sleep 1
done
if [ "$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$POSTGRES_NAME" 2>/dev/null)" = "healthy" ]; then
    echo "Postgres 17 is ready on localhost:$POSTGRES_PORT."
else
    echo "WARNING: Postgres 17 is still starting on localhost:$POSTGRES_PORT; retry dev-up.sh shortly."
fi

# --- MinIO -----------------------------------------------------------------
if docker container inspect "$MINIO_NAME" >/dev/null 2>&1; then
    echo "MinIO container '$MINIO_NAME' already running - leaving it alone."
else
    echo "Starting MinIO (API $MINIO_API_PORT, console $MINIO_CONSOLE_PORT, root $MINIO_ROOT_USER)..."
    docker run -d \
        --name "$MINIO_NAME" \
        -e MINIO_ROOT_USER="$MINIO_ROOT_USER" \
        -e MINIO_ROOT_PASSWORD="$MINIO_ROOT_PASSWORD" \
        -p "$MINIO_API_PORT:9000" \
        -p "$MINIO_CONSOLE_PORT:9001" \
        -v "$MINIO_VOLUME:/data" \
        "$MINIO_IMAGE" server /data >/dev/null
    echo "MinIO container '$MINIO_NAME' started."
fi

# Ensure the tankbook bucket exists (idempotent). The minio image bundles `mc`.
alias_ok=""
for _ in $(seq 1 15); do
    if docker exec "$MINIO_NAME" mc alias set local "http://localhost:9000" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1; then
        alias_ok="1"
        break
    fi
    sleep 1
done
if [ -n "$alias_ok" ]; then
    docker exec "$MINIO_NAME" mc mb --ignore-existing "local/$MINIO_BUCKET" >/dev/null 2>&1 || true
    echo "MinIO bucket '$MINIO_BUCKET' ensured."
else
    echo "WARNING: MinIO not reachable yet; bucket '$MINIO_BUCKET' not created. Re-run dev-up.sh shortly."
fi

echo
echo "Running local infrastructure:"
echo "  Postgres   localhost:$POSTGRES_PORT  (db/user/password: $POSTGRES_DB/$POSTGRES_USER/$POSTGRES_PASSWORD)"
echo "  MinIO API  http://localhost:$MINIO_API_PORT"
echo "  MinIO web  http://localhost:$MINIO_CONSOLE_PORT  (root: $MINIO_ROOT_USER / $MINIO_ROOT_PASSWORD)"
echo "  S3 bucket  s3://$MINIO_BUCKET"
echo "Data persists in named volumes '$POSTGRES_VOLUME' and '$MINIO_VOLUME'."

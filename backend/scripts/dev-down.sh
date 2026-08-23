#!/usr/bin/env bash
# Stops and removes the local Postgres + MinIO dev containers started by dev-up.sh.
# Idempotent: safe to re-run; missing containers are reported and skipped.
# Named volumes are kept so data survives restarts - remove them manually with
# `docker volume rm tankbook-postgres-data tankbook-minio-data` for a clean slate.
set -euo pipefail

POSTGRES_NAME="tankbook-postgres"
MINIO_NAME="tankbook-minio"

docker info >/dev/null 2>&1 || { echo "ERROR: docker is not running or not installed." >&2; exit 1; }

echo "==> Tankbook local infrastructure (dev-down)"

for container in "$POSTGRES_NAME" "$MINIO_NAME"; do
    if docker container inspect "$container" >/dev/null 2>&1; then
        echo "Stopping and removing '$container'..."
        docker rm -f "$container" >/dev/null
        echo "Removed '$container'."
    else
        echo "Container '$container' not found - nothing to do."
    fi
done

echo
echo "Done. Postgres and MinIO are stopped. Data volumes are preserved; re-run dev-up.sh to start again."

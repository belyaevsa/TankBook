#!/usr/bin/env bash
# ARCHIVED (P4.13): PaddleOCR was measured and rejected. See Spike/PaddleOCR/README.md.
# Starts the Tankbook PaddleOCR measurement container (P4.13). Plain `docker run`,
# never compose (project rule). Idempotent: an existing container is left running.
#
# Pinned image tag `tankbook-paddleocr:0.1.0` - the measurement is unreproducible
# with an unpinned tag. The model cache lives in a named volume so the sweep pays
# the model download once, and the models themselves are pinned by their
# registered names (PP-OCRv5_server_det + cyrillic_PP-OCRv5_mobile_rec for Arm A,
# PaddleOCR-VL / PaddleOCR-VL-0.9B for Arm B).
#
# The image is built by `Spike/PaddleOCR/Dockerfile`:
#   docker build -t tankbook-paddleocr:0.1.0 Spike/PaddleOCR
set -euo pipefail

NAME="tankbook-paddleocr"
IMAGE="tankbook-paddleocr:0.1.0"
PORT="8000"
VOLUME="tankbook-paddleocr-models"

docker info >/dev/null 2>&1 || { echo "ERROR: docker is not running or not installed." >&2; exit 1; }

echo "==> Tankbook PaddleOCR measurement container (dev-up-paddleocr)"

if docker container inspect "$NAME" >/dev/null 2>&1; then
    echo "Container '$NAME' already exists - leaving it alone."
else
    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        echo "Image '$IMAGE' not present; building from Spike/PaddleOCR/Dockerfile..."
        docker build -t "$IMAGE" Spike/PaddleOCR
    fi
    echo "Starting '$NAME' on port $PORT (image $IMAGE)..."
    docker run -d \
        --name "$NAME" \
        -p "$PORT:8000" \
        -v "$VOLUME:/root/.paddlex" \
        "$IMAGE" >/dev/null
    echo "Container '$NAME' started."
fi

# Wait for the health endpoint (model load happens on first request, so the
# first real call pays the model download + warm-up cost - the sweep's first
# latency is that warm-up, and it is reported, not hidden).
for _ in $(seq 1 30); do
    if curl -sf "http://localhost:$PORT/health" >/dev/null 2>&1; then
        echo "PaddleOCR service is up on http://localhost:$PORT"
        exit 0
    fi
    sleep 1
done
echo "WARNING: PaddleOCR service not answering yet on localhost:$PORT; retry dev-up-paddleocr.sh."

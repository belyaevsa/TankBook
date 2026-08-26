# Tankbook PaddleOCR measurement container (P4.13).
#
# Two arms live in one image on purpose: the sweep scores both against the same
# corpus with the same scorer, and a single pinned image keeps the measurement
# reproducible. Arm A (PP-OCRv5 recognition -> lines) and Arm B (PaddleOCR-VL ->
# fields) are different pipelines but share the PaddlePaddle runtime.
#
# Pinned tags: python:3.12-slim-bookworm (base), paddlepaddle==3.2.2 (CPU),
# paddleocr==3.7.0, paddlex==3.7.2. Do not float any of these - an unpinned tag
# makes the numbers unreproducible.
#
# paddlepaddle is pinned to 3.2.2, NOT 3.3.x, because 3.3.x ships no Linux
# aarch64 wheel (verified against PyPI: 3.3.1 has macosx_arm64 + x86_64 only) and
# this machine's Docker runs aarch64. 3.2.2 is the newest paddlepaddle that runs
# natively here.
FROM python:3.12-slim-bookworm

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=1

WORKDIR /app

# System libs opencv-contrib-python needs but the slim image omits (libGL for
# cv2, libglib for the rest). Pinned bookworm so these package names stay stable.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# PaddlePaddle CPU build first (largest, least likely to change) so Docker layers
# cache across edits to the service code. setuptools is a runtime import of
# paddlepaddle 3.2.2 (cpp_extension), absent from the slim base image.
RUN pip install --no-cache-dir setuptools paddlepaddle==3.2.2 paddleocr==3.7.0 "paddlex[ocr]==3.7.2"

COPY service.py /app/service.py

# Default model: PP-OCRv5 server detection + Cyrillic mobile recognition (Arm A).
# The sweep overrides rec for other languages and switches to PaddleOCR-VL for
# Arm B via a request header, so nothing here is baked in.
ENV PADDLE_DET_MODEL="PP-OCRv5_server_det" \
    PADDLE_REC_MODEL="cyrillic_PP-OCRv5_mobile_rec"

EXPOSE 8000

CMD ["python", "-u", "service.py"]

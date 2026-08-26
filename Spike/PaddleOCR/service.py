#!/usr/bin/env python3
"""Tankbook PaddleOCR measurement service (P4.13).

Two arms, one container:

  POST /recognize   Arm A - PP-OCRv5 server_det + cyrillic mobile rec -> lines.
                    Returns per-line text, confidence and the detection quad in
                    PaddleOCR's pixel space (top-left origin, y increasing down),
                    plus the image width/height the boxes refer to. The sweep's
                    Swift side is responsible for normalising to Vision's space
                    (x/width, y flipped) - see the calibration test.

  POST /extract     Arm B - PaddleOCR-VL (0.9B) -> full-document text lines.

  GET  /health      liveness.

Input is a JSON body: {"image": "<base64 PNG or JPEG>"}. HEIC is converted to
PNG by the sweep before it reaches this service (same as P4.12). Output is JSON.
No image or its contents are ever logged.
"""

import base64
import io
import json
import os
import sys
import tempfile
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from PIL import Image
from PIL import ImageOps


DET_MODEL = os.environ.get("PADDLE_DET_MODEL", "PP-OCRv5_server_det")
REC_MODEL = os.environ.get("PADDLE_REC_MODEL", "cyrillic_PP-OCRv5_mobile_rec")


def _ocr_config(det_model, rec_model):
    return {
        "pipeline_name": "OCR",
        "use_doc_preprocessor": False,
        "use_textline_orientation": False,
        "text_type": "general",
        "SubModules": {
            "TextDetection": {"model_name": det_model},
            "TextRecognition": {"model_name": rec_model},
        },
    }


class Pipelines:
    """Lazily-created pipelines. Each arm loads its model only on first use so
    starting the container stays cheap and one arm can run without the other."""

    def __init__(self):
        self._ocr = None
        self._vl = None

    def ocr(self):
        if self._ocr is None:
            from paddlex import create_pipeline
            self._ocr = create_pipeline(config=_ocr_config(DET_MODEL, REC_MODEL))
        return self._ocr

    def vl(self):
        if self._vl is None:
            # paddlex's `is_bfloat16_available` calls
            # `paddle.amp.is_bfloat16_supported()` with no place argument, which
            # raises on paddlepaddle 3.2.2 aarch64 CPU builds ("Invoked with:
            # Place(undefined:0)"). Force float32 - correct for a CPU inference
            # and it dodges the aarch64-only bug.
            import paddle
            paddle.amp.is_bfloat16_supported = lambda *a, **k: False
            paddle.amp.is_float16_supported = lambda *a, **k: False
            from paddlex import create_pipeline
            self._vl = create_pipeline("PaddleOCR-VL")
        return self._vl


PIPELINES = Pipelines()


def _decode_image(body):
    data = body.get("image")
    if not data:
        raise ValueError("missing 'image'")
    raw = base64.b64decode(data)
    img = Image.open(io.BytesIO(raw))
    img.load()
    # The device applies EXIF orientation before OCR; Vision does the same
    # implicitly. PaddleOCR does not, so a portrait photo stored landscape
    # (receipt-001) arrives sideways and reads as garbage. Transpose to the
    # oriented pixels before any recognition - the boxes we return are then in
    # that oriented space.
    return ImageOps.exif_transpose(img)


def _line_json(img, res):
    width, height = img.size
    texts = res.get("rec_texts") or []
    scores = res.get("rec_scores") or []
    boxes = res.get("rec_boxes") or res.get("dt_polys") or []
    lines = []
    for i, text in enumerate(texts):
        box = boxes[i] if i < len(boxes) else None
        lines.append({
            "text": text,
            "score": float(scores[i]) if i < len(scores) else None,
            "box": box,  # pixel coords, top-left origin
        })
    return {"width": width, "height": height, "lines": lines}


def _vl_text_json(res):
    """Flatten the PaddleOCR-VL result into ordered text lines.

    PaddleOCR-VL returns `parsing_res_list`: one block per detected region with
    `block_content` (the recognised text/markdown) and `block_order`. Feed the
    content lines through in document order - the parser's text path reads them
    as plain lines.
    """
    lines = []
    blocks = res.get("parsing_res_list") or []
    ordered = sorted(
        (b for b in blocks if isinstance(b, dict)),
        key=lambda b: (b.get("block_order") is None, b.get("block_order") or 0),
    )
    for block in ordered:
        content = block.get("block_content")
        if isinstance(content, str):
            for ln in content.splitlines():
                if ln.strip():
                    lines.append(ln)
        elif isinstance(content, list):
            for item in content:
                text = item.get("text") if isinstance(item, dict) else str(item)
                if text and text.strip():
                    lines.append(text)
    return {"lines": lines}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # never log image bytes or paths

    def _read(self):
        length = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(length) or b"{}")

    def _send(self, obj, status=200):
        payload = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path == "/health":
            self._send({"ok": True})
        else:
            self._send({"error": "not found"}, 404)

    def do_POST(self):
        started = time.monotonic()
        try:
            body = self._read()
            img = _decode_image(body)
            # Both pipelines take a path. Save once so Arm A and Arm B share the
            # decode cost and neither is flattered or penalised by image handling.
            suffix = ".png" if img.mode in ("RGB", "RGBA", "L") else ".jpg"
            with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as fh:
                img.save(fh.name)
                img_path = fh.name
            try:
                if self.path == "/recognize":
                    out = list(PIPELINES.ocr().predict(img_path))
                    res = out[0].json.get("res", {})
                    payload = _line_json(img, res)
                elif self.path == "/extract":
                    out = list(PIPELINES.vl().predict(img_path))
                    res = out[0].json
                    payload = _vl_text_json(res)
                else:
                    self._send({"error": "not found"}, 404)
                    return
            finally:
                try:
                    os.unlink(img_path)
                except OSError:
                    pass
            payload["serverSeconds"] = round(time.monotonic() - started, 3)
            self._send(payload)
        except Exception as exc:  # noqa: BLE001 - a failed call is a miss, never a crash
            self._send({"error": "%s: %s" % (type(exc).__name__, exc)}, 500)


if __name__ == "__main__":
    port = int(os.environ.get("PADDLE_PORT", "8000"))
    print("Tankbook PaddleOCR service on :%d (det=%s rec=%s)" % (port, DET_MODEL, REC_MODEL), flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()

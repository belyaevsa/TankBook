#!/usr/bin/env python3
# ARCHIVED (P4.13, 2026-08-26): PaddleOCR was measured and REJECTED - worse than on-device
# Vision on receipts and above the 3 s budget in every class. See Spike/PaddleOCR/README.md.
# Nothing runs this in CI; the committed results under fixtures/vision-ab/ are scored offline.
"""P4.13 - sweep PaddleOCR over the OCR fixture corpus, three runs per image.

Two arms, one HTTP service (started by `scripts/dev-up-paddleocr.sh`):

  Arm A  PP-OCRv5 server det + cyrillic mobile rec -> lines (text + pixel box)
  Arm B  PaddleOCR-VL (0.9B) -> full-document text lines

Each image is run THREE times per arm and every run's latency and raw output are
recorded, so determinism is measured rather than assumed (the P4.12 cloud arm
flipped between correct and shifted on re-run; sampling once hides that).

The service returns PaddleOCR's PIXEL boxes with a top-left origin. The Swift
dump (`PaddleOCRDumpTests`, env-gated) does the coordinate normalisation to
Vision's space and runs the SAME `FuelExtractor` as the rules arm, then writes
the committed result + variance files. Raw output lands in a gitignored
directory here; only the field results and the `receipt-001` lines are committed.

HEIC is converted to PNG first (sips), same as P4.12's sweep.

Resume-safe: an image already recorded (with three runs) is skipped.

Usage:
    scripts/sweep-paddleocr.py --arm a|b [--class receipts] [--runs 3]
"""

import base64
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURES = os.path.join(ROOT, "Spike", "ReceiptSpike", "fixtures")
RAW_DIR = os.path.join(FIXTURES, "vision-ab", ".raw")
CLASSES = ["receipts", "pump", "fiscal", "screenshots"]
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".heic", ".tiff"}
SERVICE = os.environ.get("PADDLEOCR_SERVICE", "http://localhost:8000")
GENERATED = "2026-08-26"


def image_files(folder):
    return sorted(
        f for f in os.listdir(folder)
        if os.path.splitext(f)[1].lower() in IMAGE_EXTS
    )


def load_existing(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    return {e["filename"]: e for e in data.get("entries", [])}


def write_raw(path, arm, cls, entries):
    data = {"engine": arm, "className": cls, "generated": GENERATED, "entries": entries}
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, sort_keys=True)
    os.replace(tmp, path)


def to_png(image_path):
    if os.path.splitext(image_path)[1].lower() != ".heic":
        return image_path, None
    tmpdir = tempfile.mkdtemp(prefix="p413-heic-")
    out = os.path.join(tmpdir, os.path.basename(image_path) + ".png")
    subprocess.run(["sips", "-s", "format", "png", image_path, "--out", out],
                   capture_output=True, check=True)
    return out, tmpdir


def call(endpoint, image_path):
    with open(image_path, "rb") as fh:
        img = fh.read()
    payload = json.dumps({"image": base64.b64encode(img).decode()}).encode()
    req = urllib.request.Request(SERVICE + endpoint, data=payload,
                                 headers={"Content-Type": "application/json"})
    start = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=900) as resp:
            body = json.loads(resp.read())
        return body, None, time.monotonic() - start
    except urllib.error.HTTPError as exc:
        return None, "HTTP %s: %s" % (exc.code, exc.read().decode()[:160]), time.monotonic() - start
    except Exception as exc:  # noqa: BLE001
        return None, "%s: %s" % (type(exc).__name__, exc), time.monotonic() - start


def main():
    args = [a for a in sys.argv[1:]]
    arm = "a"
    runs = 3
    classes = CLASSES
    it = iter(args)
    for a in it:
        if a == "--arm":
            arm = next(it)
        elif a == "--runs":
            runs = int(next(it))
        elif a == "--class":
            classes = [next(it)]
        else:
            print("unknown arg", a)
            sys.exit(2)
    assert arm in ("a", "b"), "--arm a|b"
    endpoint = "/recognize" if arm == "a" else "/extract"
    engine = "paddleocr-%s" % arm

    os.makedirs(RAW_DIR, exist_ok=True)
    total_images = 0
    errors = 0
    for cls in classes:
        folder = os.path.join(FIXTURES, cls)
        out_path = os.path.join(RAW_DIR, "%s-%s.json" % (engine, cls))
        existing = load_existing(out_path)
        entries = []
        for name in image_files(folder):
            total_images += 1
            done = existing.get(name)
            if done is not None and len(done.get("runs", [])) >= runs:
                entries.append(done)
                continue
            image_path = os.path.join(folder, name)
            run_list = []
            entry_error = None
            feed, tmpdir = to_png(image_path)
            try:
                for _ in range(runs):
                    body, err, latency = call(endpoint, feed)
                    if err:
                        entry_error = err
                        run_list.append({"latencySeconds": round(latency, 2),
                                         "lines": None, "textLines": None,
                                         "width": None, "height": None})
                        errors += 1
                        print("[err] %s/%s (%.1fs) %s" % (cls, name, latency, err), flush=True)
                    else:
                        run_list.append({
                            "latencySeconds": round(latency, 2),
                            "width": body.get("width"),
                            "height": body.get("height"),
                            "lines": body.get("lines") if arm == "a" else None,
                            "textLines": body.get("lines") if arm == "b" else None,
                        })
                        if arm == "a":
                            print("[ok-a] %s/%s (%.1fs) %d lines"
                                  % (cls, name, latency, len(body.get("lines") or [])), flush=True)
                        else:
                            print("[ok-b] %s/%s (%.1fs) %d text lines"
                                  % (cls, name, latency, len(body.get("lines") or [])), flush=True)
            finally:
                if tmpdir is not None:
                    shutil.rmtree(tmpdir, ignore_errors=True)
            entries.append({"filename": name, "runs": run_list, "error": entry_error})
            write_raw(out_path, engine, cls, entries)
    print("sweep %s done: %d images, %d errors" % (engine, total_images, errors))


if __name__ == "__main__":
    main()

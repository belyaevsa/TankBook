#!/usr/bin/env python3
"""P4.12 - sweep the cloud vision model over the OCR fixture corpus.

Walks each fixture class folder, calls `opencode run` on the vision model once
per image (sequential, one at a time - two `opencode` processes starting in the
same instant kill each other on the local store), and writes one machine-readable
result file per class to `Spike/ReceiptSpike/fixtures/vision-ab/llm-<class>.json`.

The result files are the A/B artefact: the next person re-scores offline against
them and never pays for the sweep again. `high-water.json` is deliberately NOT
touched - those marks gate the rules parser, not this engine.

HEIC images are losslessly converted to PNG first (sips) so the measurement is
about the model's *extraction*, not about whether the harness can feed it HEIC -
the device converts to JPEG before upload anyway (API.md -> /extract).

Resume: an image already recorded in the output file is skipped, so an
interrupted sweep can be restarted without paying twice.

Usage:
    scripts/sweep-vision-ab.py [--retry-errors]
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURES = os.path.join(ROOT, "Spike", "ReceiptSpike", "fixtures")
AB = os.path.join(FIXTURES, "vision-ab")
CLASSES = ["receipts", "pump", "fiscal", "screenshots"]
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".heic", ".tiff"}
MODEL = "deepseek/deepseek-v4-flash-vision-exp"
GENERATED = "2026-08-26"

PROMPT = (
    "Read this photo. It shows a fuel purchase: a paper receipt, a pump display, or an "
    "electronic receipt. Extract exactly three numbers and report them as JSON: liters (the "
    "volume of fuel dispensed), unitPrice (the price per litre), and total (the amount charged "
    "for the fuel). Reply with ONLY a JSON object of the form "
    '{"liters":12.38,"unitPrice":243.0,"total":3008.0}. Use null for any field that is not '
    "legibly present in the image. Do not add any other text."
)

ANSI = re.compile(r"\x1b\[[0-9;]*m")


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


def write_file(path, cls, entries):
    data = {"engine": "llm", "className": cls, "generated": GENERATED, "entries": entries}
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, sort_keys=True)
    os.replace(tmp, path)


def to_png(image_path):
    """HEIC is not a format the vision model reads natively; convert losslessly.

    The conversion lands in a temp directory, never next to the fixture - a
    stray `*.heic.png` in the corpus folder would be picked up as an image by the
    scorer and would look like a silently missing image. Returns the path to feed
    the model (the original for non-HEIC, the temp PNG for HEIC).
    """
    if os.path.splitext(image_path)[1].lower() != ".heic":
        return image_path, None
    tmpdir = tempfile.mkdtemp(prefix="p412-heic-")
    out = os.path.join(tmpdir, os.path.basename(image_path) + ".png")
    subprocess.run(
        ["sips", "-s", "format", "png", image_path, "--out", out],
        capture_output=True,
        check=True,
    )
    return out, tmpdir


def call_model(image_path):
    cmd = ["opencode", "run", "--auto", "-m", MODEL, PROMPT, "-f", image_path]
    start = time.monotonic()
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
    except subprocess.TimeoutExpired:
        return "", "timeout after 240s", 124, time.monotonic() - start
    return proc.stdout, proc.stderr, proc.returncode, time.monotonic() - start


def extract_json(text):
    text = ANSI.sub("", text)
    start = text.find("{")
    if start == -1:
        return None
    depth = 0
    in_string = False
    escape = False
    for i in range(start, len(text)):
        ch = text[i]
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
    return None


def parse_reply(stdout):
    blob = extract_json(stdout)
    if blob is None:
        return None, None, None, "no JSON object in reply"
    try:
        obj = json.loads(blob)
    except json.JSONDecodeError as exc:
        return None, None, None, "unparseable JSON: %s" % exc

    def num(key):
        v = obj.get(key)
        if v is None:
            return None
        if isinstance(v, bool):
            return None
        if isinstance(v, (int, float)):
            return float(v)
        if isinstance(v, str):
            s = v.strip()
            try:
                return float(s)
            except ValueError:
                return None
        return None

    return num("liters"), num("unitPrice"), num("total"), None


def main():
    retry_errors = "--retry-errors" in sys.argv
    os.makedirs(AB, exist_ok=True)
    total_images = 0
    errors = 0
    for cls in CLASSES:
        folder = os.path.join(FIXTURES, cls)
        out_path = os.path.join(AB, "llm-%s.json" % cls)
        existing = load_existing(out_path)
        entries = []
        for name in image_files(folder):
            total_images += 1
            done = existing.get(name)
            if done is not None and (done.get("error") is None or not retry_errors):
                entries.append(done)
                continue
            image_path = os.path.join(folder, name)
            try:
                feed, tmpdir = to_png(image_path)
                stdout, stderr, rc, latency = call_model(feed)
                if tmpdir is not None:
                    shutil.rmtree(tmpdir, ignore_errors=True)
            except Exception as exc:  # sips failure, etc.
                stdout, stderr, rc, latency = "", str(exc), 1, 0.0
            if rc != 0:
                errors += 1
                reason = "opencode exit %s: %s" % (rc, ANSI.sub("", stderr)[:160].strip())
                entries.append({
                    "filename": name, "liters": None, "unitPrice": None, "total": None,
                    "latencySeconds": round(latency, 2), "error": reason,
                })
                print("[err ] %s/%s (%.1fs) %s" % (cls, name, latency, reason), flush=True)
                write_file(out_path, cls, entries)
                continue
            liters, unitPrice, total, err = parse_reply(stdout)
            if err:
                errors += 1
                entries.append({
                    "filename": name, "liters": None, "unitPrice": None, "total": None,
                    "latencySeconds": round(latency, 2), "error": err,
                })
                print("[err ] %s/%s (%.1fs) %s" % (cls, name, latency, err), flush=True)
            else:
                entries.append({
                    "filename": name, "liters": liters, "unitPrice": unitPrice,
                    "total": total, "latencySeconds": round(latency, 2), "error": None,
                })
                print("[ok  ] %s/%s (%.1fs) L=%s P=%s T=%s"
                      % (cls, name, latency, liters, unitPrice, total), flush=True)
            write_file(out_path, cls, entries)
    print("sweep done: %d images, %d errors" % (total_images, errors))


if __name__ == "__main__":
    main()

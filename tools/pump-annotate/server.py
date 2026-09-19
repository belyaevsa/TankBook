#!/usr/bin/env python3
"""Number-window annotator for the pump corpus - a local web page over
`Spike/ReceiptSpike/fixtures/pump/windows.json`.

    ml/pump-reader/.venv/bin/python tools/pump-annotate/server.py   # then open the URL it prints

Reads `expected.csv` for the truth cells and `windows.json` for the quads,
serves each fixture as an EXIF-oriented JPEG (HEIC included, via pillow-heif
from the ml venv), and writes the entry back on Save in the file's own
formatting. The page draws rectangles, drags corners, names the field and
types what the display shows; `Check` runs `scripts/pump-windows-check.py
--check` and shows its verdict. The format itself is documented in the file's
`_about` and in `.claude/skills/corpus-intake/SKILL.md`.

Loopback only: it writes files in the checkout, so it never binds a public
interface.
"""
from __future__ import annotations

import csv
import hashlib
import io
import json
import subprocess
import sys
import traceback
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parent.parent.parent
FIX = ROOT / "Spike" / "ReceiptSpike" / "fixtures" / "pump"
WINDOWS = FIX / "windows.json"
EXPECTED = FIX / "expected.csv"
CHECK = ROOT / "scripts" / "pump-windows-check.py"
HERE = Path(__file__).resolve().parent
CACHE = Path.home() / "Library" / "Caches" / "tankbook-pump-annotate"
IMAGE_EDGE = 2000
ENTRY_KEYS = ("windows", "rotationCW", "notOnDisplay", "csvDisagrees")
WINDOW_KEYS = ("field", "text", "quad", "legibility")


def load_windows() -> dict:
    return json.loads(WINDOWS.read_text())


def save_windows(data: dict) -> None:
    # Byte-compatible with the committed file: indent 1, no trailing newline.
    WINDOWS.write_text(json.dumps(data, indent=1))


def load_rows() -> dict[str, dict]:
    with EXPECTED.open() as f:
        return {r["filename"]: r for r in csv.DictReader(f)}


def oriented_jpeg(name: str) -> bytes:
    """The fixture as the browser must see it: EXIF applied, long edge capped,
    cached by content hash so a re-exported fixture is never served stale."""
    src = FIX / name
    digest = hashlib.sha256(src.read_bytes()).hexdigest()[:16]
    CACHE.mkdir(parents=True, exist_ok=True)
    cached = CACHE / f"{digest}.jpg"
    if cached.exists():
        return cached.read_bytes()
    from PIL import Image, ImageOps  # noqa: PLC0415 - the ml venv has it
    try:
        import pillow_heif  # noqa: PLC0415
        pillow_heif.register_heif_opener()
    except ImportError:
        pass
    with Image.open(src) as im:
        im = ImageOps.exif_transpose(im).convert("RGB")
        im.thumbnail((IMAGE_EDGE, IMAGE_EDGE))
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=88)
    cached.write_bytes(buf.getvalue())
    return buf.getvalue()


def clean_entry(entry: dict) -> dict:
    """Only the documented keys, in the file's order, empties dropped."""
    out: dict = {"windows": []}
    for w in entry.get("windows", []):
        quad = [[round(float(x), 4), round(float(y), 4)] for x, y in w["quad"]]
        cw = {"field": w["field"], "text": w.get("text", ""), "quad": quad}
        if w.get("legibility"):
            cw["legibility"] = w["legibility"]
        out["windows"].append(cw)
    if entry.get("rotationCW"):
        out["rotationCW"] = int(entry["rotationCW"])
    if entry.get("notOnDisplay"):
        out["notOnDisplay"] = list(entry["notOnDisplay"])
    if entry.get("csvDisagrees"):
        out["csvDisagrees"] = dict(entry["csvDisagrees"])
    return out


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):  # quieter than the default
        if self.command != "GET" or "/image/" not in self.path:
            sys.stderr.write("%s %s\n" % (self.command, self.path))

    def send_json(self, obj, status=HTTPStatus.OK):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_bytes(self, body: bytes, ctype: str):
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/index.html"):
            return self.send_bytes((HERE / "index.html").read_bytes(), "text/html; charset=utf-8")
        if path == "/api/fixtures":
            ann, rows = load_windows(), load_rows()
            names = list(rows) + [n for n in ann if not n.startswith("_") and n not in rows]
            return self.send_json([{
                "name": n,
                "inCsv": n in rows,
                "windows": len(ann.get(n, {}).get("windows", [])),
                "annotated": n in ann,
            } for n in names])
        if path.startswith("/api/entry/"):
            name = unquote(path[len("/api/entry/"):])
            ann, rows = load_windows(), load_rows()
            return self.send_json({"entry": ann.get(name, {"windows": []}), "row": rows.get(name)})
        if path.startswith("/image/"):
            name = unquote(path[len("/image/"):])
            if "/" in name or not (FIX / name).exists():
                return self.send_error(HTTPStatus.NOT_FOUND)
            try:
                return self.send_bytes(oriented_jpeg(name), "image/jpeg")
            except Exception:  # noqa: BLE001 - logged, then the raw file is served
                traceback.print_exc()
                # Without Pillow the browser gets the original: Safari renders
                # HEIC and applies EXIF orientation itself; other browsers
                # show HEIC as broken, which is the venv hint again.
                suffix = name.rsplit(".", 1)[-1].lower()
                ctype = {"jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "heic": "image/heic"}.get(suffix, "application/octet-stream")
                return self.send_bytes((FIX / name).read_bytes(), ctype)
        return self.send_error(HTTPStatus.NOT_FOUND)

    def do_PUT(self):
        path = urlparse(self.path).path
        if not path.startswith("/api/entry/"):
            return self.send_error(HTTPStatus.NOT_FOUND)
        name = unquote(path[len("/api/entry/"):])
        length = int(self.headers.get("Content-Length", "0"))
        entry = json.loads(self.rfile.read(length))
        ann = load_windows()
        ann[name] = clean_entry(entry)
        save_windows(ann)
        return self.send_json({"ok": True, "entry": ann[name]})

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/api/check":
            r = subprocess.run([sys.executable, str(CHECK), "--check"], capture_output=True, text=True)
            return self.send_json({"exit": r.returncode, "output": (r.stdout + r.stderr).strip()})
        return self.send_error(HTTPStatus.NOT_FOUND)


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    try:
        import PIL  # noqa: F401, PLC0415
    except ImportError:
        print("Pillow not importable: HEIC and EXIF-oriented images will only render in Safari. "
              "Run with ml/pump-reader/.venv/bin/python.", file=sys.stderr)
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"pump annotator: http://127.0.0.1:{port}/  ({WINDOWS.relative_to(ROOT)})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()

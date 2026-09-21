#!/usr/bin/env python3
"""Number-window annotator for the pump corpus - a local web page over
`Spike/ReceiptSpike/fixtures/pump/windows.json`.

    python3 tools/pump-annotate/server.py   # then open the URL it prints

Reads `expected.csv` for the truth cells and `windows.json` for the quads,
serves each fixture as a capped JPEG (HEIC included - Pillow when the ml venv
runs it, macOS `sips` otherwise), and writes the entry back on Save in the file's own
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
import os
import subprocess
import sys
import threading
import traceback
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import corpus_db  # noqa: E402

FIX = ROOT / "Spike" / "ReceiptSpike" / "fixtures" / "pump"
WINDOWS = FIX / "windows.json"
EXPECTED = FIX / "expected.csv"
CHECK = ROOT / "scripts" / "pump-windows-check.py"
HERE = Path(__file__).resolve().parent
CACHE = Path.home() / "Library" / "Caches" / "tankbook-pump-annotate"
IMAGE_EDGE = 2000
FRAMES = ROOT / "Spike" / "ReceiptSpike" / "fixtures" / "pump-live" / "frames"
DB = ROOT / "Spike" / "ReceiptSpike" / "fixtures" / "corpus.sqlite"
LIVE = ROOT / "Spike" / "ReceiptSpike" / "fixtures" / "pump-live"
VIDEOS = LIVE / "videos.json"
VIDEO_LABELS = LIVE / "video-labels.json"
READ_TOOL = ROOT / "ios" / ".build" / "debug" / "pump-read"
CLASSIFIER = ROOT / "ios" / "App" / "Resources" / "PumpSegments.mlpackage"
DETECTOR = ROOT / "ios" / "App" / "Resources" / "DigitRows.mlmodel"

# Writes go database-first: one transaction and one dump per request, and no
# two requests interleave between the two.
WRITE_LOCK = threading.Lock()


def load_windows() -> dict:
    return json.loads(WINDOWS.read_text())


def load_rows() -> dict[str, dict]:
    with EXPECTED.open() as f:
        return {r["filename"]: r for r in csv.DictReader(f)}


def oriented_jpeg(name: str) -> bytes:
    """The fixture as the browser must see it: HEIC decoded, long edge capped,
    cached by content hash so a re-exported fixture is never served stale.
    Pillow (the ml venv) bakes the EXIF orientation in; without it macOS
    `sips` converts and the browser applies the orientation tag itself."""
    src = FIX / name
    digest = hashlib.sha256(src.read_bytes()).hexdigest()[:16]
    CACHE.mkdir(parents=True, exist_ok=True)
    cached = CACHE / f"{digest}.jpg"
    if cached.exists():
        return cached.read_bytes()
    try:
        from PIL import Image, ImageOps  # noqa: PLC0415
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
    except ImportError:
        probe = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(src)],
                               check=True, capture_output=True, text=True).stdout
        edge = max(int(line.split()[-1]) for line in probe.splitlines() if "pixel" in line)
        # sips resamples up as readily as down; only cap what is larger.
        cap = ["--resampleHeightWidthMax", str(IMAGE_EDGE)] if edge > IMAGE_EDGE else []
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "88", *cap,
                        str(src), "--out", str(cached)], check=True, capture_output=True)
    return cached.read_bytes()


live_stems: dict[str, list[str]] = {}


def live_counts() -> dict[str, int]:
    """Live records per still, from corpus.sqlite; also fills `live_stems`."""
    import sqlite3  # noqa: PLC0415
    live_stems.clear()
    try:
        with sqlite3.connect(DB) as con:
            for name, still in con.execute(
                    "select name, paired_fixture from media where kind = 'live' and paired_fixture is not null"):
                live_stems.setdefault(still, []).append(Path(name).stem)
    except sqlite3.DatabaseError:
        pass
    return {k: len(v) for k, v in live_stems.items()}


def tracked_count(stems: list[str]) -> int:
    total = 0
    for stem in stems:
        tracked = FRAMES / stem / "windows.json"
        if tracked.exists():
            total += len(json.loads(tracked.read_text()).get("frames", {}))
    return total


def video_entries() -> dict:
    try:
        return {k: v for k, v in json.loads(VIDEOS.read_text()).items() if not k.startswith("_")}
    except (OSError, ValueError):
        return {}


def video_labels() -> dict:
    try:
        return json.loads(VIDEO_LABELS.read_text())
    except (OSError, ValueError):
        return {}


def video_record(stem: str) -> dict:
    """A running-display video as one record: its tracked frames, the
    per-frame labels (arithmetic or owner) merged into each frame's windows,
    the reader's raw reading of every frame as a pre-fill (source `reader`,
    never a label until saved), and the RUNS - consecutive frames the reader
    read as the same value - so a label is typed once per value."""
    tracked = FRAMES / stem / "windows.json"
    frames = json.loads(tracked.read_text()).get("frames", {}) if tracked.exists() else {}
    labels = video_labels().get(stem, {})
    readings_path = FRAMES / stem / "readings.json"
    readings = json.loads(readings_path.read_text()) if readings_path.exists() else {}
    order = sorted(frames, key=lambda n: int(n[:-4]))
    for name, frame in frames.items():
        lab = labels.get(name, {})
        rd = readings.get(name, {})
        for w in frame["windows"]:
            if w["field"] in lab:
                w["text"] = lab[w["field"]]
            elif w["field"] in ("total", "liters") and rd.get(w["field"]) and "?" not in rd[w["field"]]:
                w["prefill"] = rd[w["field"]]
        frame["source"] = lab.get("source")
    runs: list[list[str]] = []
    prev = None
    for name in order:
        rd = readings.get(name)
        key = (rd["total"], rd["liters"]) if rd else None
        if key is None or key != prev or not runs:
            runs.append([name])
        else:
            runs[-1].append(name)
        prev = key
    return {"movie": stem, "tracked": order, "frames": frames, "runs": runs,
            "extracted": len(list((FRAMES / stem).glob("*.jpg"))) if (FRAMES / stem).exists() else 0,
            "labelled": sum(1 for n in frames if n in labels)}


def records_for(still: str) -> list[dict]:
    """The Live records paired to a still (corpus.sqlite media table) with
    their tracked-frame files, when pump_reader.track has run."""
    import sqlite3  # noqa: PLC0415
    try:
        with sqlite3.connect(DB) as con:
            names = [r[0] for r in con.execute(
                "select name from media where kind = 'live' and paired_fixture = ? order by name", (still,))]
    except sqlite3.DatabaseError:
        names = []
    out = []
    for name in names:
        stem = Path(name).stem
        tracked = FRAMES / stem / "windows.json"
        frames = {}
        if tracked.exists():
            frames = json.loads(tracked.read_text()).get("frames", {})
        out.append({"movie": stem, "tracked": sorted(frames), "frames": frames,
                    "extracted": len(list((FRAMES / stem).glob("*.jpg"))) if (FRAMES / stem).exists() else 0})
    return out


def propagate_texts(record: str, windows: list[dict]) -> None:
    """A still's texts (and legibility) onto every frame of its Live record,
    then the record's file dumped - what a retrack would carry, without the
    registration."""
    with corpus_db.transaction(None) as con:
        # By window index, not field: two `board` cells carry two texts.
        for ord_, w in enumerate(windows):
            con.execute("update frame_windows set text = ?, legibility = ? where record = ? and ord = ?",
                        (w.get("text", ""), w.get("legibility"), record, ord_))
    corpus_db.dump([FRAMES / record / "windows.json"])


# One retrack per video at a time, in the background; the page polls /api/retrack/<name>.
# With `read`, the tracked frames are then read again by the app's reader
# (PumpVideoReadTests regenerates the `arithmetic` labels); frames the owner
# labelled or anchored, and a video marked reviewed, are the test's own skips.
retracks: dict[str, dict] = {}


def start_retrack(name: str, read: bool = False) -> None:
    import threading  # noqa: PLC0415
    current = retracks.get(name)
    if current and current.get("running"):
        current["again"] = True   # a save during a run queues one more run
        current["read"] = current.get("read", False) or read
        return
    retracks[name] = {"running": True, "again": False, "read": read, "phase": "track", "result": None}

    def run() -> None:
        while True:
            ml = ROOT / "ml" / "pump-reader"
            python = ml / ".venv" / "bin" / "python"
            retracks[name]["phase"] = "track"
            mode = ["--videos"] if name.startswith("video-") else []
            result = subprocess.run([str(python), "-m", "pump_reader.track", *mode, "--only", name],
                                    cwd=ml, env={**os.environ, "PYTHONPATH": "src"}, capture_output=True, text=True)
            lines = (result.stdout + result.stderr).strip().splitlines()
            retracks[name]["result"] = lines[-1] if lines else f"exit {result.returncode}"
            # The tracker writes the database itself and dumps the record's file.
            if retracks[name].get("read"):
                retracks[name]["read"] = False
                retracks[name]["phase"] = "read"
                test = subprocess.run(["swift", "test", "--filter", "PumpVideoReadTests"], cwd=ROOT / "ios",
                                      env={**os.environ, "PUMP_VIDEO_READ": "1", "PUMP_VIDEO_READ_ONLY": name},
                                      capture_output=True, text=True)
                out = (test.stdout + test.stderr).strip().splitlines()
                summary = next((ln for ln in reversed(out) if "Test run" in ln or "error:" in ln), None)
                retracks[name]["result"] = (summary or f"exit {test.returncode}").strip()
            if retracks[name].get("again"):
                retracks[name]["again"] = False
                continue
            retracks[name]["running"] = False
            return

    threading.Thread(target=run, daemon=True).start()


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
            live = live_counts()
            labels = video_labels()
            out = [{
                "name": n,
                "inCsv": n in rows,
                "windows": len(ann.get(n, {}).get("windows", [])),
                "reviewed": bool(ann.get(n, {}).get("reviewed")),
                "tracking": ann.get(n, {}).get("tracking"),
                "live": live.get(n, 0),
                "tracked": tracked_count(live_stems.get(n, [])),
            } for n in names]
            for stem, v in video_entries().items():
                out.append({"name": stem, "video": True, "inCsv": True, "windows": len(v["windows"]),
                            "reviewed": bool(v.get("reviewed")), "tracking": None, "live": 1,
                            "tracked": tracked_count([stem]), "labelled": len(labels.get(stem, {}))})
            return self.send_json(out)
        if path.startswith("/api/entry/"):
            name = unquote(path[len("/api/entry/"):])
            videos = video_entries()
            if name in videos:
                v = videos[name]
                return self.send_json({"video": True, "entry": {"windows": [dict(w, text=v["unitPrice"] if w["field"] == "unitPrice" else "") for w in v["windows"]],
                                                                "reference": v["reference"], "reviewed": bool(v.get("reviewed"))},
                                       "row": {"liters": "", "unitPrice": v["unitPrice"], "total": "", "currency": v["currency"]}})
            ann, rows = load_windows(), load_rows()
            return self.send_json({"entry": ann.get(name, {"windows": []}), "row": rows.get(name)})
        if path.startswith("/api/retrack/"):
            name = unquote(path[len("/api/retrack/"):])
            return self.send_json(retracks.get(name, {"running": False, "result": None}))
        if path.startswith("/api/records/"):
            name = unquote(path[len("/api/records/"):])
            if name in video_entries():
                return self.send_json([video_record(name)])
            return self.send_json(records_for(name))
        if path.startswith("/frame/"):
            rel = unquote(path[len("/frame/"):])
            stem, _, file = rel.partition("/")
            target = FRAMES / stem / file
            if "/" in stem or "/" in file or not target.exists():
                return self.send_error(HTTPStatus.NOT_FOUND)
            return self.send_bytes(target.read_bytes(), "image/jpeg")
        if path.startswith("/image/"):
            name = unquote(path[len("/image/"):])
            if "/" in name or not (FIX / name).exists():
                return self.send_error(HTTPStatus.NOT_FOUND)
            try:
                return self.send_bytes(oriented_jpeg(name), "image/jpeg")
            except Exception:  # noqa: BLE001 - logged, then the raw file is served
                traceback.print_exc()
                suffix = name.rsplit(".", 1)[-1].lower()
                ctype = {"jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "heic": "image/heic"}.get(suffix, "application/octet-stream")
                return self.send_bytes((FIX / name).read_bytes(), ctype)
        return self.send_error(HTTPStatus.NOT_FOUND)

    def do_PUT(self):
        path = urlparse(self.path).path
        if path.startswith("/api/video-anchor/"):
            # /api/video-anchor/<stem>/<frame>: the owner's corrected quads on one
            # frame become an anchor the tracker registers its neighbours to.
            rel = unquote(path[len("/api/video-anchor/"):])
            stem, _, frame = rel.partition("/")
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length))
            videos = json.loads(VIDEOS.read_text())
            windows = [{"field": w["field"], "quad": [[round(float(x), 4), round(float(y), 4)] for x, y in w["quad"]]}
                       for w in body.get("windows", []) if w["field"] in ("total", "liters", "unitPrice", "board")]
            if stem.startswith("live-"):
                # A Live record's anchor is kept on its still's entry (windows.json);
                # the record's own tracked file is derived from it.
                tracked = FRAMES / stem / "windows.json"
                still = json.loads(tracked.read_text()).get("_still") if tracked.exists() else None
                if not still:
                    return self.send_error(HTTPStatus.NOT_FOUND)
                with WRITE_LOCK:
                    with corpus_db.transaction() as con:
                        anchors = corpus_db.save_live_anchor(still, stem, frame, windows, con=con)
                        if not anchors:
                            return self.send_error(HTTPStatus.NOT_FOUND)
                        corpus_db.pin_frame(stem, frame, windows, con=con)
                    corpus_db.dump([WINDOWS, tracked, corpus_db.CORRECTIONS_FILE])
                if body.get("retrack"):
                    start_retrack(stem)
                return self.send_json({"ok": True, "anchors": [a["frame"] for a in anchors if a["record"] == stem],
                                       "liveAnchors": anchors, "retrack": bool(body.get("retrack"))})
            if stem not in videos:
                return self.send_error(HTTPStatus.NOT_FOUND)
            with WRITE_LOCK:
                with corpus_db.transaction() as con:
                    anchors = corpus_db.save_video_anchor(stem, frame, windows, con=con)
                    corpus_db.pin_frame(stem, frame, windows, {"unitPrice": videos[stem].get("unitPrice", "")}, con=con)
                corpus_db.dump([VIDEOS, FRAMES / stem / "windows.json", corpus_db.CORRECTIONS_FILE])
            if body.get("retrack"):
                start_retrack(stem)
            return self.send_json({"ok": True, "anchors": anchors, "retrack": bool(body.get("retrack"))})
        if path.startswith("/api/video-label/"):
            # /api/video-label/<stem>/<frame>: the owner's texts for one frame.
            rel = unquote(path[len("/api/video-label/"):])
            stem, _, frame = rel.partition("/")
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length))
            labels = video_labels()
            entry = {k: body[k] for k in ("total", "liters", "unitPrice") if k in body}
            readings_path = FRAMES / stem / "readings.json"
            readings = json.loads(readings_path.read_text()) if readings_path.exists() else {}
            proposed = dict(readings.get(frame, {}))
            prior = labels.get(stem, {}).get(frame, {})
            corrections = []
            for field, final in entry.items():
                if field == "unitPrice":
                    continue
                # Who proposed the value being changed: the reader (an arithmetic
                # label or a pre-fill), a copy from the previous frame or a run
                # propagation (`via`), or the operator's own earlier judgement.
                if prior.get("source") == "owner":
                    before, by = prior.get(field), ("copied" if prior.get("via") in ("copied", "run") else "operator")
                elif prior.get("source") == "arithmetic":
                    before, by = prior.get(field), "reader"
                else:
                    before, by = proposed.get(field), "reader"
                if before is not None and before != "" and before != final:
                    corrections.append({"kind": "text", "video": stem, "frame": frame, "field": field,
                                        "proposedBy": by, "proposed": before, "final": final})
            # `frames` lists every frame of the run the label applies to.
            # The frame itself always takes the label; the rest of its run only
            # where no human label exists yet - a glitched frame inside a run
            # that the owner labelled by hand keeps its own reading.
            targets = body.get("frames") or [frame]
            per = labels.setdefault(stem, {})
            written = []
            for target in targets:
                if target != frame and per.get(target, {}).get("source") == "owner":
                    continue
                if any(entry.values()):
                    via = "copied" if body.get("copied") else ("run" if target != frame else None)
                    per[target] = dict(entry, source="owner", **({"via": via} if via else {}))
                else:
                    per.pop(target, None)
                written.append(target)
            with WRITE_LOCK:
                with corpus_db.transaction() as con:
                    corpus_db.add_corrections(corrections, con=con)
                    corpus_db.save_labels(stem, per, con=con)
                corpus_db.dump([VIDEO_LABELS, corpus_db.CORRECTIONS_FILE])
            return self.send_json({"ok": True, "written": written})
        if not path.startswith("/api/entry/"):
            return self.send_error(HTTPStatus.NOT_FOUND)
        name = unquote(path[len("/api/entry/"):])
        length = int(self.headers.get("Content-Length", "0"))
        entry = json.loads(self.rfile.read(length))
        videos = json.loads(VIDEOS.read_text()) if VIDEOS.exists() else {}
        if name in videos:
            # The reference quads of a video: skew them to the display's tilt,
            # then re-run pump_reader.track --videos to carry them into the frames.
            new_windows = [{"field": w["field"], "quad": [[round(float(x), 4), round(float(y), 4)] for x, y in w["quad"]]}
                           for w in entry.get("windows", []) if w["field"] in ("total", "liters", "unitPrice")]
            quads_changed = new_windows != videos[name].get("windows")
            reviewed = bool(entry.get("reviewed"))
            with WRITE_LOCK:
                with corpus_db.transaction() as con:
                    corpus_db.save_video(name, new_windows, reviewed, con=con)
                corpus_db.dump([VIDEOS])
            if quads_changed:
                start_retrack(name)
            return self.send_json({"ok": True,
                                   "entry": {"windows": new_windows, "reference": videos[name]["reference"], "reviewed": reviewed},
                                   "retrack": "started" if quads_changed else "unchanged"})
        ann = load_windows()
        prefilled = entry.pop("prefilled", None) or {}
        corrections = []
        for w in entry.get("windows", []):
            field, final = w["field"], w.get("text", "")
            if field in prefilled and prefilled[field] != final:
                corrections.append({"kind": "text", "still": name, "field": field, "proposedBy": "reader",
                                    "proposed": prefilled[field], "final": final})
        if entry.get("tracking") and entry.get("tracking") != ann.get(name, {}).get("tracking"):
            corrections.append({"kind": "tracking", "still": name, "final": entry["tracking"]})
        before = ann.get(name, {})
        # The anchors are owned by the anchor route (a drag on a Live frame); a
        # still save carries whatever the database holds so a page loaded before
        # the drag cannot drop them (save_entry does this when the body omits them).
        with WRITE_LOCK:
            with corpus_db.transaction() as con:
                corpus_db.add_corrections(corrections, con=con)
                saved = corpus_db.save_entry(name, entry, con=con)
            corpus_db.dump([WINDOWS, corpus_db.CORRECTIONS_FILE])
        # A still's windows are what the tracker carries into its Live record:
        # a record with no tracked frames yet, or one whose still's quads just
        # changed, is (re)tracked in the background so the frames view opens
        # without a shell step.
        tracked = []
        if saved["windows"]:
            quads_changed = [w["quad"] for w in before.get("windows", [])] != [w["quad"] for w in saved["windows"]]
            texts_changed = [(w["field"], w.get("text", ""), w.get("legibility")) for w in before.get("windows", [])] \
                != [(w["field"], w.get("text", ""), w.get("legibility")) for w in saved["windows"]]
            for rec in records_for(name):
                if not (FRAMES / rec["movie"]).exists():
                    continue
                if quads_changed or not rec["tracked"]:
                    start_retrack(rec["movie"])
                    tracked.append(rec["movie"])
                elif texts_changed:
                    # The texts are the still's, carried into every frame; a text
                    # edit needs no homography, so the frames take it directly.
                    propagate_texts(rec["movie"], saved["windows"])
                    tracked.append(rec["movie"] + " (texts)")
        return self.send_json({"ok": True, "entry": saved, "tracking": tracked})

    def do_POST(self):
        path = urlparse(self.path).path
        if path.startswith("/api/retrack-now/"):
            # /api/retrack-now/<stem>: re-register every non-anchored frame to the
            # reference and the anchors - the owner's call after pinning frames.
            stem = unquote(path[len("/api/retrack-now/"):])
            if not (FRAMES / stem).exists():
                return self.send_error(HTTPStatus.NOT_FOUND)
            start_retrack(stem)
            return self.send_json({"ok": True})
        if path.startswith("/api/rerun/"):
            # /api/rerun/<stem>: retrack the clip from its anchors, then read every
            # tracked frame again. Owner labels, anchored frames and a reviewed
            # video are left as they are.
            stem = unquote(path[len("/api/rerun/"):])
            videos = json.loads(VIDEOS.read_text())
            if stem not in videos:
                return self.send_error(HTTPStatus.NOT_FOUND)
            start_retrack(stem, read=True)
            return self.send_json({"ok": True, "reviewed": bool(videos[stem].get("reviewed"))})
        if path == "/api/dump":
            # Every corpus file written from the database (`corpus_db.py dump`),
            # then the staleness check; the reply says what changed on disk.
            import time  # noqa: PLC0415
            started = time.time()
            written = corpus_db.dump()
            check = subprocess.run([sys.executable, str(ROOT / "scripts" / "corpus_db.py"), "check"],
                                   capture_output=True, text=True)
            changed = subprocess.run(["git", "status", "--short", "--", "Spike/ReceiptSpike/fixtures"], cwd=ROOT,
                                     capture_output=True, text=True).stdout.strip().splitlines()
            return self.send_json({"files": len(written), "ms": int((time.time() - started) * 1000),
                                   "check": check.returncode, "changed": changed[:40], "changedCount": len(changed)})
        if path == "/api/check":
            r = subprocess.run([sys.executable, str(CHECK), "--check"], capture_output=True, text=True)
            return self.send_json({"exit": r.returncode, "output": (r.stdout + r.stderr).strip()})
        if path == "/api/read":
            # The reader on the current still or frame: with the page's windows it
            # slices and classifies each and lets the law commit; with `live` it
            # runs the app's path (detector -> verify -> assign -> law) instead.
            # A prefill for the owner to accept or correct - nothing is written.
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length) or b"{}")
            image = body.get("image", "")
            if image.startswith("frame/"):
                _, stem, file = image.split("/", 2)
                target = FRAMES / stem / file
            else:
                target = FIX / image
            if "/" in target.name or not target.exists():
                return self.send_json({"error": f"no such image: {image}"}, HTTPStatus.NOT_FOUND)
            if not READ_TOOL.exists():
                build = subprocess.run(["swift", "build", "--product", "pump-read"], cwd=ROOT / "ios",
                                       capture_output=True, text=True)
                if build.returncode:
                    return self.send_json({"error": "pump-read did not build", "output": build.stderr[-2000:]}, HTTPStatus.INTERNAL_SERVER_ERROR)
            request = {"rotationCW": body.get("rotationCW", 0), "currency": body.get("currency") or None,
                       "windows": None if body.get("live") else body.get("windows") or None}
            r = subprocess.run([str(READ_TOOL), str(target), "--classifier", str(CLASSIFIER), "--detector", str(DETECTOR)],
                               input=json.dumps(request), capture_output=True, text=True, timeout=120)
            if r.returncode or not r.stdout.strip():
                return self.send_json({"error": "pump-read failed", "output": (r.stderr or r.stdout)[-2000:]}, HTTPStatus.INTERNAL_SERVER_ERROR)
            return self.send_json(json.loads(r.stdout))
        return self.send_error(HTTPStatus.NOT_FOUND)


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    corpus_db.ensure_schema()
    print(f"pump annotator: http://127.0.0.1:{port}/  ({WINDOWS.relative_to(ROOT)}; writes go through corpus.sqlite)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()

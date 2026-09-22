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

import base64
import csv
import hashlib
import io
import json
import os
import subprocess
import sys
import threading
import traceback
from datetime import datetime
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import corpus_db  # noqa: E402
from slicer import ResidentSlicer  # noqa: E402

FIX = ROOT / "Spike" / "ReceiptSpike" / "fixtures" / "pump"
WINDOWS = FIX / "windows.json"
EXPECTED = FIX / "expected.csv"
CHECK = ROOT / "scripts" / "pump-windows-check.py"
HERE = Path(__file__).resolve().parent
CACHE = Path.home() / "Library" / "Caches" / "tankbook-pump-annotate"
IMAGE_EDGE = 2000
FRAMES = ROOT / "Spike" / "ReceiptSpike" / "fixtures" / "pump-live" / "frames"
DB = Path(os.environ.get("PUMP_ANNOTATE_DB") or (ROOT / "Spike" / "ReceiptSpike" / "fixtures" / "corpus.sqlite"))
# A test run points the server at a copy of the database and must leave the
# checkout alone: the database is redirected and the JSON dump is skipped.
REDIRECTED_DB = "PUMP_ANNOTATE_DB" in os.environ
LIVE = ROOT / "Spike" / "ReceiptSpike" / "fixtures" / "pump-live"
VIDEOS = LIVE / "videos.json"
VIDEO_LABELS = LIVE / "video-labels.json"
READ_TOOL = ROOT / "ios" / ".build" / "debug" / "pump-read"
# The optimised build the live overlay uses: the debug configuration keeps
# `@testable import` working, `-O` makes the slicer's pixel loops ~30x faster
# (17 ms against 630 ms for three windows). Built here on first use.
SLICE_TOOL = ROOT / "ios" / ".build" / "opt" / "debug" / "pump-read"


def build_slice_tool() -> bool:
    r = subprocess.run(["swift", "build", "--product", "pump-read", "-Xswiftc", "-O", "--scratch-path", ".build/opt"],
                       cwd=ROOT / "ios", capture_output=True, text=True)
    return r.returncode == 0 and SLICE_TOOL.exists()


SLICER = ResidentSlicer(SLICE_TOOL, build=build_slice_tool, cwd=ROOT)
CLASSIFIER = ROOT / "ios" / "App" / "Resources" / "PumpSegments.mlpackage"
DETECTOR = ROOT / "ios" / "App" / "Resources" / "DigitRows.mlmodel"
# Every row detector on this machine: the one in the bundle, the dev copy the
# Swift tests read, and the candidates a training round left behind. The live
# path (⇧R) can be run against any of them, which is the only way to judge a
# candidate by looking rather than by its committed count.
DETECTOR_DIRS = [ROOT / "ios" / "App" / "Resources", ROOT / "ml" / "pump-reader" / ".out" / "det",
                 ROOT / "ml" / "pump-reader" / ".out" / "det" / "pu48"]


def detectors() -> list[dict]:
    """Every row detector on this machine, each with a VERSION that is unique
    even when two files share a name: the folder's tag, the corpus generation
    the export beside it was built from (`counts.json`'s train stills, which is
    what actually changes between rounds), the date it was written, and the
    first eight of its sha256. `DigitRows` appears three times on this machine
    and only the version tells them apart."""
    shipped = hashlib.sha256(DETECTOR.read_bytes()).hexdigest() if DETECTOR.exists() else None
    tags = {"ios/App/Resources": "bundle", "ml/pump-reader/.out/det": "dev"}
    out, seen = [], set()
    for folder in DETECTOR_DIRS:
        where = str(folder.relative_to(ROOT))
        tag = tags.get(where, folder.name)
        counts = {}
        counts_file = folder / "counts.json"
        if counts_file.exists():
            try:
                counts = json.loads(counts_file.read_text())
            except json.JSONDecodeError:
                counts = {}
        for path in sorted(folder.glob("*.mlmodel")) if folder.exists() else []:
            key = str(path.resolve())
            if key in seen:
                continue
            seen.add(key)
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            written = datetime.fromtimestamp(path.stat().st_mtime).strftime("%Y-%m-%d %H:%M")
            stills = counts.get("train_stills")
            out.append({"path": str(path.relative_to(ROOT)),
                        "name": path.stem,
                        "where": where,
                        "tag": tag,
                        "trainStills": stills,
                        "boxes": counts.get("boxes"),
                        "modified": written,
                        "version": f"{tag} · {written[:10]}" + (f" · {stills} stills" if stills else "") + f" · {digest[:8]}",
                        "mb": round(path.stat().st_size / 1e6, 1),
                        "sha": digest[:8],
                        "shipped": digest == shipped})
    return out

CLASSIFIER_DIRS = [ROOT / "ios" / "App" / "Resources", ROOT / "ml" / "pump-reader" / ".out"]


def package_sha(package: Path) -> str:
    """The mlpackage's own identity: the compiled model inside it, hashed, so two
    packages both named PumpSegments can be told apart."""
    model = package / "Data" / "com.apple.CoreML" / "model.mlmodel"
    if model.exists():
        return hashlib.sha256(model.read_bytes()).hexdigest()
    manifest = package / "Manifest.json"
    return hashlib.sha256(manifest.read_bytes()).hexdigest() if manifest.exists() else ""


def classifier_packages() -> list[Path]:
    """Every segment classifier on this machine: the bundle's, and each training
    round's candidate under `.out/<round>/`."""
    found: list[Path] = []
    for folder in CLASSIFIER_DIRS:
        if not folder.exists():
            continue
        found += sorted(folder.glob("*.mlpackage")) + sorted(folder.glob("*/*.mlpackage"))
    return found


def classifiers() -> list[dict]:
    """Every segment classifier on this machine, versioned the way the detectors
    are: the folder's tag, the corpus generation its sibling export was built
    from (`counts.json`'s train stills), the date it was written, and the first
    eight of its model sha. The bundle's is marked shipped; a candidate is not."""
    shipped_pkg = CLASSIFIER
    shipped = package_sha(shipped_pkg) if shipped_pkg.exists() else None
    out, seen = [], set()
    for package in classifier_packages():
        key = str(package.resolve())
        if key in seen:
            continue
        seen.add(key)
        digest = package_sha(package)
        if not digest:
            continue
        parent = package.parent
        counts_file = parent / "counts.json"
        counts = {}
        if counts_file.exists():
            try:
                counts = json.loads(counts_file.read_text())
            except json.JSONDecodeError:
                counts = {}
        written = datetime.fromtimestamp(package.stat().st_mtime).strftime("%Y-%m-%d %H:%M")
        stills = counts.get("train_stills")
        tag = "bundle" if parent == CLASSIFIER_DIRS[0] else parent.name
        out.append({"path": str(package.relative_to(ROOT)), "name": package.stem,
                    "where": str(parent.relative_to(ROOT)), "tag": tag,
                    "trainStills": stills, "boxes": counts.get("boxes"), "modified": written,
                    "version": f"{tag} · {written[:10]}" + (f" · {stills} stills" if stills else "") + f" · {digest[:8]}",
                    "sha": digest[:8], "shipped": digest == shipped})
    return out


# The compare view's cache: one pump-read reply per (image content, detector sha,
# classifier sha), so a disagreement sweep never runs a pair twice. Scratch only.
COMPARE_CACHE = Path(os.environ.get("PUMP_COMPARE_CACHE") or (ROOT / "ml" / "pump-reader" / ".out" / "compare-cache"))
COMPARE_RUNS = Path(os.environ.get("PUMP_COMPARE_RUNS") or (ROOT / "ml" / "pump-reader" / "runs"))


def image_target(image: str) -> Path | None:
    """The file behind a compare request's `image`: a still name or `frame/<stem>/<file>`."""
    if image.startswith("frame/"):
        _, stem, file = image.split("/", 2)
        target = FRAMES / stem / file
    else:
        target = FIX / image
    if not target.name or "/" in target.name or not target.exists():
        return None
    return target


def model_key(detector: Path, classifier: Path) -> str:
    det = hashlib.sha256(detector.read_bytes()).hexdigest()[:8] if detector.exists() else "00000000"
    cls = package_sha(classifier)[:8] if classifier.exists() else "00000000"
    return f"{det}-{cls}"


def read_binary() -> Path:
    """The optimised build when the resident slicer has made one (about 30x faster
    pixel work), else the debug product, built on first use."""
    if SLICE_TOOL.exists():
        return SLICE_TOOL
    if not READ_TOOL.exists():
        subprocess.run(["swift", "build", "--product", "pump-read"], cwd=ROOT / "ios", capture_output=True, text=True)
    return READ_TOOL


def image_currency(image: str) -> str | None:
    """The still's currency from `expected.csv`. The reader's pair tier needs
    the currency's price band (decision 11); without it a total + volume pair
    refuses, and the compare view would under-report what the app commits.
    A video frame has no row, so it runs without one, as the app does."""
    if image.startswith("frame/"):
        return None
    return (load_rows().get(image) or {}).get("currency") or None


DESKEW_MODES = ("off", "onRefusal", "always", "level")


def read_model(image: str, detector: Path, classifier: Path, cache: bool = True, deskew: str = "off") -> dict:
    """One live-path pump-read reply for an image and a model pair, cached by
    (image content, model pair, currency, tool build) so a sweep never runs a
    pair twice and a rebuilt tool never serves a reply missing its new fields."""
    target = image_target(image)
    if target is None:
        return {"error": f"no such image: {image}"}
    binary = read_binary()
    if not binary.exists():
        return {"error": "pump-read did not build"}
    currency = image_currency(image)
    deskew = deskew if deskew in DESKEW_MODES else "off"
    key = model_key(detector, classifier)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()[:16]
    tool = f"{int(binary.stat().st_mtime)}-{currency or 'none'}-{deskew}"
    cached = COMPARE_CACHE / key / f"{digest}-{tool}.json"
    if cache and cached.exists():
        try:
            return json.loads(cached.read_text())
        except json.JSONDecodeError:
            pass
    r = subprocess.run([str(binary), str(target), "--classifier", str(classifier), "--detector", str(detector)],
                       input=json.dumps({**({"currency": currency} if currency else {}), "deskew": deskew}),
                       capture_output=True, text=True, timeout=900)
    if r.returncode or not r.stdout.strip():
        return {"error": "pump-read failed", "output": (r.stderr or r.stdout)[-2000:]}
    try:
        reply = json.loads(r.stdout)
    except json.JSONDecodeError:
        return {"error": "pump-read replied with something that is not JSON"}
    if cache:
        cached.parent.mkdir(parents=True, exist_ok=True)
        cached.write_text(json.dumps(reply))
    return reply


def committed_triple(reply: dict) -> list:
    c = reply.get("committed") or {}
    return [c.get(f) for f in ("total", "liters", "unitPrice")]


def _match(value, expected) -> str:
    """`✓` when the model's value equals the truth row, `✗` when it is present and
    differs, `–` when either side is missing (the law abstained)."""
    if value is None or expected in (None, ""):
        return "–"
    try:
        return "✓" if abs(float(str(value).replace(",", ".")) - float(str(expected).replace(",", "."))) < 0.005 else "✗"
    except (TypeError, ValueError):
        return "✓" if str(value) == str(expected) else "✗"


def compare_verdict(expected: dict | None, a: dict, b: dict) -> dict:
    """Per field: the truth row, A's commit, B's commit, and each side's verdict."""
    out = {}
    for field in ("total", "liters", "unitPrice"):
        exp = (expected or {}).get(field)
        av = (a.get("committed") or {}).get(field)
        bv = (b.get("committed") or {}).get(field)
        out[field] = {"expected": exp, "a": av, "b": bv,
                      "aVerdict": _match(av, exp), "bVerdict": _match(bv, exp)}
    return out


# One disagreement sweep at a time: a background thread reads each still with
# both models and keeps the rows whose committed triples differ.
sweeps: dict[str, dict] = {}

PRESENCE_IOU = 0.3
TRANSACTION_FIELDS = ("total", "liters", "unitPrice")


def _box(quad):
    xs, ys = [p[0] for p in quad], [p[1] for p in quad]
    return min(xs), min(ys), max(xs), max(ys)


def _iou(a, b) -> float:
    ax0, ay0, ax1, ay1 = _box(a)
    bx0, by0, bx1, by1 = _box(b)
    w, h = min(ax1, bx1) - max(ax0, bx0), min(ay1, by1) - max(ay0, by0)
    if w <= 0 or h <= 0:
        return 0.0
    inter = w * h
    return inter / ((ax1 - ax0) * (ay1 - ay0) + (bx1 - bx0) * (by1 - by0) - inter)


def presence_counts(hand: list[dict], reply: dict) -> dict:
    """What the pipeline did to each hand transaction window: kept (a kept
    candidate over it), dropped (only candidates the verifier dropped), or
    missed (no candidate at all) - the same rule the compare view colours by."""
    counts = {"kept": 0, "dropped": 0, "missed": 0}
    if not isinstance(reply.get("candidates"), list):
        return counts  # a reply from an older tool build carries no presence
    cands = reply["candidates"]
    for w in hand:
        if w.get("field") not in TRANSACTION_FIELDS or not w.get("quad"):
            continue
        over = [c for c in cands if _iou(w["quad"], c["quad"]) >= PRESENCE_IOU]
        counts["kept" if any(c.get("kept") for c in over) else "dropped" if over else "missed"] += 1
    return counts


def start_sweep(stills: list[str], detector_a: Path, classifier_a: Path,
                detector_b: Path, classifier_b: Path, deskew_a: str = "off", deskew_b: str = "off") -> None:
    sweeps["default"] = {"running": True, "done": 0, "total": len(stills), "current": None, "rows": [],
                         "presence": []}
    job = sweeps["default"]
    windows = load_windows()

    def run() -> None:
        try:
            for name in stills:
                job["current"] = name
                ra = read_model(name, detector_a, classifier_a, deskew=deskew_a)
                rb = read_model(name, detector_b, classifier_b, deskew=deskew_b)
                if committed_triple(ra) != committed_triple(rb):
                    job["rows"].append({"still": name, "a": committed_triple(ra), "b": committed_triple(rb)})
                hand = (windows.get(name) or {}).get("windows") or []
                pa, pb = presence_counts(hand, ra), presence_counts(hand, rb)
                if pa["missed"] or pa["dropped"] or pb["missed"] or pb["dropped"]:
                    job["presence"].append({"still": name, "a": pa, "b": pb})
                job["done"] += 1
        finally:
            job["running"] = False
            job["current"] = None

    threading.Thread(target=run, daemon=True).start()


# Writes go database-first: one transaction and one dump per request, and no
# two requests interleave between the two.
WRITE_LOCK = threading.Lock()

corpus_db.DB = DB


def dump_files(paths: list[Path] | None = None) -> list[Path]:
    """Write the database's corpus files. A redirected (test) run writes
    nothing into the checkout - the database copy is the only store it touches."""
    if REDIRECTED_DB:
        return []
    return corpus_db.dump(paths)


def windows_differ(a: list[dict], b: list[dict]) -> bool:
    """True when two window lists differ in field, text or quad, in order."""
    key = lambda w: (w.get("field"), w.get("text", ""), [tuple(p) for p in w.get("quad", [])])
    return [key(w) for w in a] != [key(w) for w in b]


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
    if REDIRECTED_DB:
        return corpus_db.labels()
    try:
        return json.loads(VIDEO_LABELS.read_text())
    except (OSError, ValueError):
        return {}


def _num(text) -> float | None:
    try:
        return float(str(text).replace(",", "."))
    except (TypeError, ValueError):
        return None


# `PumpReader.minimumMeanMargin` - the classifier's verify floor, the mean cell
# margin below which a row is not digits. Read from the Swift source that defines
# it so the page compares against the constant and never copies the number.
PUMP_READER_SWIFT = (ROOT / "ios" / "Sources" / "TankbookCore" / "Extraction"
                     / "PumpReader" / "PumpReader.swift")


def _read_verify_margin() -> float | None:
    import re  # noqa: PLC0415
    try:
        text = PUMP_READER_SWIFT.read_text()
    except OSError:
        return None
    m = re.search(r"minimumMeanMargin\s*=\s*([0-9]+(?:\.[0-9]+)?)", text)
    return float(m.group(1)) if m else None


VERIFY_MARGIN = _read_verify_margin()


def interpolate_frames(order: list[str], prev_name: str, prev_label: dict,
                       cur_name: str, cur_label: dict, price: float | None,
                       step: float = 0.01, tolerance: float = 0.02) -> dict[str, dict]:
    """The frames strictly between two keyframes, filled by linear interpolation
    of liters and total snapped to the nearest closing pair
    (`total == round(liters x price, 2)`), monotone non-decreasing in both. A
    frame with no closing pair within `tolerance` litres of its interpolation is
    left out, so it stays unlabelled and `frameStates` marks it attention."""
    try:
        i0, i1 = order.index(prev_name), order.index(cur_name)
    except ValueError:
        return {}
    if i1 <= i0 + 1 or not price:
        return {}
    l0, t0 = _num(prev_label.get("liters")), _num(prev_label.get("total"))
    l1, t1 = _num(cur_label.get("liters")), _num(cur_label.get("total"))
    if None in (l0, t0, l1, t1):
        return {}
    out: dict[str, dict] = {}
    last_l, last_t = l0, t0
    span = i1 - i0
    for k in range(i0 + 1, i1):
        l_lin = l0 + (l1 - l0) * (k - i0) / span
        base = round(l_lin / step) * step
        best = None
        for d in range(-3, 4):
            l = round(base + d * step, 2)
            if abs(l - l_lin) > tolerance + 1e-9:
                continue
            t = round(l * price, 2)
            if l < last_l - 1e-9 or t < last_t - 1e-9:
                continue
            dist = abs(l - l_lin)
            if best is None or dist < best[0]:
                best = (dist, l, t)
        if best is None:
            continue
        last_l, last_t = best[1], best[2]
        out[order[k]] = {"liters": f"{best[1]:.2f}", "total": f"{best[2]:.2f}"}
    return out


def _owner(per: dict, name: str) -> bool:
    return per.get(name, {}).get("source") == "owner"


def _nearest_owner(per: dict, run: list[str], frame: str, direction: int) -> str | None:
    """The nearest owner-labelled frame before (direction -1) or after (+1) the
    given frame, within the run. `frame` itself is never returned."""
    if frame not in run:
        return None
    i = run.index(frame)
    rng = range(i - 1, -1, -1) if direction < 0 else range(i + 1, len(run))
    for j in rng:
        if _owner(per, run[j]):
            return run[j]
    return None


def invalidate_interpolated(per: dict, run: list[str], frame: str,
                            cleared: list[str]) -> None:
    """A label write to `frame` invalidates the interpolations it bounds: every
    `interpolated` label strictly between the nearest owner frames on either side
    is removed, so a stale middle is never left claiming an old keyframe pair."""
    if frame not in run:
        return
    i = run.index(frame)
    prev = _nearest_owner(per, run, frame, -1)
    nxt = _nearest_owner(per, run, frame, +1)
    lo = run.index(prev) if prev else i
    hi = run.index(nxt) if nxt else i
    for k in range(lo + 1, hi):
        if per.get(run[k], {}).get("source") == "interpolated":
            per.pop(run[k], None)
            cleared.append(run[k])


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
        # The reading's confidence: the lowest cell margin of the window that
        # produced the label, as the reader staged it. Never from the label.
        if rd.get("margin") is not None:
            frame["margin"] = _num(rd.get("margin"))
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
            "labelled": sum(1 for n in frames if n in labels),
            "verifyMargin": VERIFY_MARGIN}


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
    dump_files([FRAMES / record / "windows.json"])


# One retrack per video at a time, in the background; the page polls /api/retrack/<name>.
# With `read`, the tracked frames are then read again by the app's reader
# (PumpVideoReadTests regenerates the `arithmetic` labels); frames the owner
# labelled or anchored, and a video marked reviewed, are the test's own skips.
retracks: dict[str, dict] = {}


def start_retrack(name: str, read: bool = False, from_frame: str | None = None) -> None:
    import threading  # noqa: PLC0415
    current = retracks.get(name)
    if current and current.get("running"):
        current["again"] = True   # a save during a run queues one more run
        current["read"] = current.get("read", False) or read
        return
    retracks[name] = {"running": True, "again": False, "read": read, "phase": "track", "result": None,
                      "from": from_frame}

    def run() -> None:
        while True:
            ml = ROOT / "ml" / "pump-reader"
            python = ml / ".venv" / "bin" / "python"
            retracks[name]["phase"] = "track"
            mode = ["--videos"] if name.startswith("video-") else []
            start = retracks[name].pop("from", None)
            scope = ["--from", start] if start else []
            result = subprocess.run([str(python), "-m", "pump_reader.track", *mode, "--only", name, *scope],
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
        if path == "/api/ping":
            # The page's heartbeat: no database, no disk - a dead server must
            # answer nothing, not answer slowly, or the dot lies.
            return self.send_json({"ok": True})
        if path in ("/", "/index.html"):
            return self.send_bytes((HERE / "index.html").read_bytes(), "text/html; charset=utf-8")
        if path == "/api/detectors":
            return self.send_json(detectors())
        if path == "/api/classifiers":
            return self.send_json(classifiers())
        if path == "/api/compare/sweep":
            return self.send_json(sweeps.get("default", {"running": False, "done": 0, "total": 0, "rows": []}))
        if path == "/api/fixtures":
            ann, rows = load_windows(), load_rows()
            names = list(rows) + [n for n in ann if not n.startswith("_") and n not in rows]
            live = live_counts()
            labels = video_labels()
            splits = corpus_db.split()
            out = [{
                "name": n,
                "inCsv": n in rows,
                "windows": len(ann.get(n, {}).get("windows", [])),
                "reviewed": bool(ann.get(n, {}).get("reviewed")),
                "tracking": ann.get(n, {}).get("tracking"),
                "live": live.get(n, 0),
                "tracked": tracked_count(live_stems.get(n, [])),
                "split": splits.get(n, "train"),
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
        if path.startswith("/api/convention/"):
            # The pad key's oracle: the modal digit count and separator per
            # transaction field over the reviewed entries of the still's make,
            # derived from the corpus (`corpus_db.convention`), never a table.
            name = unquote(path[len("/api/convention/"):])
            make = corpus_db.make_of(name)
            return self.send_json({"make": make, "fields": corpus_db.convention(make)})
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
        if path.startswith("/api/frame-skip/"):
            # /api/frame-skip/<stem>/<frame> {skipped: bool}: the frame shows no
            # display; the extractor, the detector export and the video read
            # leave it out. A ledger row records the verdict.
            rel = unquote(path[len("/api/frame-skip/"):])
            stem, _, frame = rel.partition("/")
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length) or b"{}")
            with WRITE_LOCK:
                with corpus_db.transaction() as con:
                    ok = corpus_db.set_frame_skipped(stem, frame, bool(body.get("skipped")), con=con)
                dump_files([FRAMES / stem / "windows.json", corpus_db.CORRECTIONS_FILE])
            if not ok:
                return self.send_json({"error": f"no such frame: {stem}/{frame}"}, HTTPStatus.NOT_FOUND)
            return self.send_json({"ok": True, "skipped": bool(body.get("skipped"))})
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
                    dump_files([WINDOWS, tracked, corpus_db.CORRECTIONS_FILE])
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
                dump_files([VIDEOS, FRAMES / stem / "windows.json", corpus_db.CORRECTIONS_FILE])
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
            # `run` is the ordered frames of the run the label belongs to - the
            # context for interpolation and invalidation. `frames` (a list) is the
            # set to write owner in one go (the confirm-all shortcut); `keyframe`
            # writes this frame owner and fills the gap to the previous owner;
            # `confirm` writes just this frame owner, one step of the loop.
            per = labels.setdefault(stem, {})
            run = body.get("run") or body.get("frames") or [frame]
            keyframe = bool(body.get("keyframe"))
            written: list[str] = []
            interpolated: list[str] = []
            cleared: list[str] = []
            if keyframe:
                if any(entry.values()):
                    per[frame] = dict(entry, source="owner")
                else:
                    per.pop(frame, None)
                written.append(frame)
                invalidate_interpolated(per, run, frame, cleared)
                prev_name = _nearest_owner(per, run, frame, -1)
                price = _num(video_entries().get(stem, {}).get("unitPrice"))
                if prev_name is not None:
                    filled = interpolate_frames(run, prev_name, per[prev_name], frame, per[frame], price)
                    for name, fields in filled.items():
                        per[name] = {**fields, "unitPrice": body.get("unitPrice", ""),
                                     "source": "interpolated"}
                        interpolated.append(name)
            else:
                targets = body.get("frames") if body.get("frames") else [frame]
                for target in targets:
                    if target != frame and per.get(target, {}).get("source") == "owner":
                        continue
                    if any(entry.values()):
                        via = "copied" if body.get("copied") else (
                            "run" if (body.get("confirm") or target != frame) else None)
                        per[target] = dict(entry, source="owner", **({"via": via} if via else {}))
                    else:
                        per.pop(target, None)
                    written.append(target)
                invalidate_interpolated(per, run, frame, cleared)
            # A run write's ledger line says how many frames the owner confirmed
            # and how many the arithmetic filled, so `via: run` volume can be read
            # against `interpolated` (PU.42 item A3/B6).
            if len(run) > 1 or keyframe:
                corrections.append({"kind": "label", "video": stem, "frame": frame,
                                    "confirmed": len(written), "interpolated": len(interpolated)})
            with WRITE_LOCK:
                with corpus_db.transaction() as con:
                    corpus_db.add_corrections(corrections, con=con)
                    corpus_db.save_labels(stem, per, con=con)
                dump_files([VIDEO_LABELS, corpus_db.CORRECTIONS_FILE])
            return self.send_json({"ok": True, "written": written,
                                   "interpolated": interpolated, "cleared": cleared})
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
                dump_files([VIDEOS])
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
        before = corpus_db.entry(name) or ann.get(name, {})
        # Every window the save moves, adds or deletes is a ledger row too (the
        # text corrections above cover only what the reader pre-filled).
        corrections += corpus_db.window_corrections(name, before.get("windows", []), entry.get("windows", []))
        corrections += corpus_db.negative_corrections(name, before.get("negatives", []), entry.get("negatives", []))
        # Decision 9: a heldout still measures only once reviewed, so editing a
        # reviewed heldout entry's windows clears reviewed - a changed heldout
        # still never measures silently. Identical windows keep it.
        reviewed_cleared = False
        if (before.get("reviewed") and name in corpus_db.heldout_names()
                and windows_differ(entry.get("windows", []), before.get("windows", []))):
            entry["reviewed"] = False
            reviewed_cleared = True
        # The anchors are owned by the anchor route (a drag on a Live frame); a
        # still save carries whatever the database holds so a page loaded before
        # the drag cannot drop them (save_entry does this when the body omits them).
        with WRITE_LOCK:
            with corpus_db.transaction() as con:
                corpus_db.add_corrections(corrections, con=con)
                saved = corpus_db.save_entry(name, entry, con=con)
            dump_files([WINDOWS, corpus_db.CORRECTIONS_FILE])
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
        return self.send_json({"ok": True, "entry": saved, "tracking": tracked, "reviewedCleared": reviewed_cleared})

    def compare_models(self, body: dict):
        """Resolve the two sides' (detector, classifier) from a request body,
        validating each against the machine's listings. A missing classifier
        falls back to the shipped one."""
        dets = {d["path"]: d for d in detectors()}
        clss = {c["path"]: c for c in classifiers()}
        shipped_cls = next((c for c in clss.values() if c["shipped"]), None)
        sides = {}
        for side in ("a", "b"):
            det_path = body.get(f"detector{side.upper()}") or body.get("detector")
            det = dets.get(det_path)
            if det is None:
                return None, f"unknown detector: {det_path}"
            cls_path = body.get(f"classifier{side.upper()}") or body.get("classifier")
            cls = clss.get(cls_path) if cls_path else shipped_cls
            if cls is None:
                return None, f"unknown classifier: {cls_path}"
            sides[side] = (det, cls)
        return sides, None

    def compare_route(self, path: str):
        length = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(length) or b"{}")
        if path == "/api/compare/disagree":
            rows = []
            for pair in body.get("pairs", []):
                a, b = pair.get("a") or {}, pair.get("b") or {}
                if committed_triple(a) != committed_triple(b):
                    rows.append({"still": pair.get("still"), "a": committed_triple(a), "b": committed_triple(b)})
            return self.send_json({"rows": rows})
        sides, error = self.compare_models(body)
        if error:
            return self.send_json({"error": error}, HTTPStatus.BAD_REQUEST)
        if path == "/api/compare/sweep":
            stills = [s for s in body.get("stills", []) if image_target(s) is not None]
            start_sweep(stills, ROOT / sides["a"][0]["path"], ROOT / sides["a"][1]["path"],
                        ROOT / sides["b"][0]["path"], ROOT / sides["b"][1]["path"],
                        deskew_a=str(body.get("deskewA") or "off"), deskew_b=str(body.get("deskewB") or "off"))
            return self.send_json({"running": True, "total": len(stills)})
        image = body.get("image", "")
        if image_target(image) is None:
            return self.send_json({"error": f"no such image: {image}"}, HTTPStatus.NOT_FOUND)
        cache = body.get("cache", True)
        a = {"detector": sides["a"][0], "classifier": sides["a"][1],
             "reply": read_model(image, ROOT / sides["a"][0]["path"], ROOT / sides["a"][1]["path"], cache=cache,
                                 deskew=str(body.get("deskewA") or "off"))}
        b = {"detector": sides["b"][0], "classifier": sides["b"][1],
             "reply": read_model(image, ROOT / sides["b"][0]["path"], ROOT / sides["b"][1]["path"], cache=cache,
                                 deskew=str(body.get("deskewB") or "off"))}
        if path == "/api/compare":
            expected = None if image.startswith("frame/") else load_rows().get(image)
            return self.send_json({"image": image, "expected": expected, "a": a, "b": b,
                                   "verdict": compare_verdict(expected, a["reply"], b["reply"])})
        if path == "/api/compare/save":
            return self.save_compare(image, a, b, body.get("png", ""))
        return self.send_error(HTTPStatus.NOT_FOUND)

    def save_compare(self, image: str, a: dict, b: dict, png: str):
        """Both replies and a PNG of the two panes under
        `runs/<date>/compare/<still>/`, so a report carries the evidence."""
        if image.startswith("frame/"):
            _, stem, file = image.split("/", 2)
            still = f"{stem}__{Path(file).stem}"
        else:
            still = Path(image).stem
        outdir = COMPARE_RUNS / datetime.now().strftime("%Y-%m-%d") / "compare" / still
        outdir.mkdir(parents=True, exist_ok=True)
        (outdir / "a.json").write_text(json.dumps({"detector": a["detector"]["path"],
                                                   "classifier": a["classifier"]["path"],
                                                   "reply": a["reply"]}, indent=1))
        (outdir / "b.json").write_text(json.dumps({"detector": b["detector"]["path"],
                                                   "classifier": b["classifier"]["path"],
                                                   "reply": b["reply"]}, indent=1))
        (outdir / "meta.json").write_text(json.dumps({"image": image, "saved": datetime.now().isoformat(timespec="seconds")}, indent=1))
        written = ["a.json", "b.json", "meta.json"]
        wrote_png = False
        if isinstance(png, str) and png.startswith("data:image/png;base64,"):
            (outdir / "panes.png").write_bytes(base64.b64decode(png.split(",", 1)[1]))
            written.append("panes.png")
            wrote_png = True
        return self.send_json({"dir": str(outdir.relative_to(ROOT)), "files": written, "png": wrote_png})

    def do_POST(self):
        path = urlparse(self.path).path
        if path.startswith("/api/compare"):
            return self.compare_route(path)
        if path.startswith("/api/retrack-now/"):
            # /api/retrack-now/<stem>: re-register every non-anchored frame to the
            # reference and the anchors - the owner's call after pinning frames.
            stem = unquote(path[len("/api/retrack-now/"):])
            if not (FRAMES / stem).exists():
                return self.send_error(HTTPStatus.NOT_FOUND)
            # ?from=NNN.jpg re-registers only that frame and the ones after it.
            query = dict(p.split("=", 1) for p in urlparse(self.path).query.split("&") if "=" in p)
            from_frame = unquote(query.get("from", "")) or None
            start_retrack(stem, from_frame=from_frame)
            return self.send_json({"ok": True, "from": from_frame})
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
            written = dump_files()
            check = subprocess.run([sys.executable, str(ROOT / "scripts" / "corpus_db.py"), "check"],
                                   capture_output=True, text=True)
            changed = subprocess.run(["git", "status", "--short", "--", "Spike/ReceiptSpike/fixtures"], cwd=ROOT,
                                     capture_output=True, text=True).stdout.strip().splitlines()
            return self.send_json({"files": len(written), "ms": int((time.time() - started) * 1000),
                                   "check": check.returncode, "changed": changed[:40], "changedCount": len(changed)})
        if path == "/api/check":
            r = subprocess.run([sys.executable, str(CHECK), "--check"], capture_output=True, text=True)
            return self.send_json({"exit": r.returncode, "output": (r.stdout + r.stderr).strip()})
        if path == "/api/slice":
            # The live overlay: the slicer's cells for the given windows, from
            # the resident process - no model, no write. A drag sends one of
            # these per mouse move; stale ones are superseded, never queued.
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
            # Board cells slice like any window: the resident slicer has no law
            # to feed, so nothing is gained by withholding them (the /api/read
            # path below still leaves boards out - the law never reads one).
            reply = SLICER.slice({"image": str(target), "rotationCW": body.get("rotationCW", 0),
                                  "windows": body.get("windows", [])})
            return self.send_json(reply)
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
            # A detector the page picked, checked against the listing so a
            # request cannot name an arbitrary file.
            detector = DETECTOR
            if body.get("detector"):
                match = next((d for d in detectors() if d["path"] == body["detector"]), None)
                if match is None:
                    return self.send_json({"error": f"unknown detector: {body['detector']}"}, HTTPStatus.BAD_REQUEST)
                detector = ROOT / match["path"]
            r = subprocess.run([str(READ_TOOL), str(target), "--classifier", str(CLASSIFIER), "--detector", str(detector)],
                               input=json.dumps(request), capture_output=True, text=True, timeout=120)
            if r.returncode or not r.stdout.strip():
                return self.send_json({"error": "pump-read failed", "output": (r.stderr or r.stdout)[-2000:]}, HTTPStatus.INTERNAL_SERVER_ERROR)
            return self.send_json(json.loads(r.stdout))
        return self.send_error(HTTPStatus.NOT_FOUND)


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    # A redirected run is a copy of the live database, already current: it is
    # not migrated or re-imported, so the run cannot write to the checkout.
    if not REDIRECTED_DB:
        corpus_db.ensure_schema()
    print(f"pump annotator: http://127.0.0.1:{port}/  ({WINDOWS.relative_to(ROOT)}; writes go through corpus.sqlite)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()

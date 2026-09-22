"""CLI: ``python -m pump_reader.realglyphs [--out .out/real]``.

Turns the Swift export of the train split (`PumpTrainSliceExportTests`,
``ios/.build/pump-reader-out/train/train-slices.json``: every train window
of the stills and their tracked Live frames, warped to the strip and cut by
the production slicer) into labelled 32x48 glyph cells for the classifier.

The database says which windows are real training material - TRAIN stills and
records whose still is not ``tracking = bad``, and labelled video frames (never
a ``skip``). The export supplies only the strips and the slicer's cell boxes;
the label text comes from the database.

A window is used only when the slicer's cell count equals the label's glyph
count - then cell *i* carries label *i* (``score.parse_cells``: digits, the
dp bit on the cell before a separator, blanks for spaces). A window the
slicer miscounts is skipped whole: aligning a wrong count to the text would
label cells with their neighbours' digits, which is worse than no label.

Sampler levers (`ml/pump-reader/CORRECTIONS.md` section 3):

* ``--cap-fixture`` - no single still, record or video contributes more than
  this share of the pool; cells beyond the cap are dropped by uniform
  subsampling with ``--seed``.
* ``--hard-weight`` - a frame or still with a ``corrections`` row of kind
  ``text`` and ``proposedBy = reader`` (a pre-fill the operator corrected) has
  its cells repeated this many times in the pool.
* ``--centred`` - keep a cell only when its column-ink centroid lies within
  this fraction of the cell width from the centre (default off). The slicer
  sometimes cuts a cell half a pitch off phase, so cell *i* carries label *i*
  over its neighbour's pixels; the centroid is the cheap geometric tell.
* ``--dp-crop`` - ``off`` (the original framing: keep the labelled dp bit),
  ``gap`` (widen every crop to the right by 0.4 x pitch so a decimal mark in
  the inter-cell gap is inside the pixels the bit is trained on) or ``none``
  (clear every dp bit - the slicer owns the mark, PU.34b).

Output: ``<out>/cells.npz`` (uint8 ``x`` of shape ``[n, 3, 48, 32]``, uint8
``y`` of the 8-bit segment labels) and ``<out>/manifest.json`` (per cell:
fixture, frame, field, window index, cell index, label, weight; per fixture:
windows offered / used) - the record that every source is train.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
from PIL import Image

from .glyph import CELL_H, CELL_W, SegmentLabel
from .score import make_of, parse_cells

ROOT = Path(__file__).resolve().parents[4]
EXPORT = ROOT / "ios" / ".build" / "pump-reader-out" / "train"
sys.path.insert(0, str(ROOT / "scripts"))
import corpus_db  # noqa: E402


def token(name: str) -> str:
    """The fixture's stable id: ``pump-241-wayne-…`` -> ``pump-241``. A still
    renamed after an export was cut is the same fixture, so its windows match."""
    parts = name.split("-")
    return parts[0] + "-" + parts[1] if len(parts) > 1 else name


def db_windows(con) -> dict[tuple, str]:
    """(fixture, frame, field) -> text for every TRAIN, labelled window.

    ``frame`` is None for a still, ``<record>/<frame>`` for a tracked frame and
    ``<video>/<frame>`` for a video frame. The still/record keys use the stable
    fixture token so a rename does not lose the windows."""
    out: dict[tuple, str] = {}
    for r in con.execute(
            "select e.fixture, w.field, w.text from entries e join fixtures f on f.name = e.fixture "
            "join windows w on w.fixture = e.fixture "
            "where f.split = 'train' and (e.tracking is null or e.tracking != 'bad')"):
        out[(token(r["fixture"]), None, r["field"])] = r["text"]
    for r in con.execute(
            "select fr.still, fr.record, fr.frame, fw.field, fw.text from frames fr "
            "join frame_windows fw on fw.record = fr.record and fw.frame = fr.frame "
            "join entries e on e.fixture = fr.still "
            "where fr.frame != '' and fr.split = 'train' and (e.tracking is null or e.tracking != 'bad')"):
        out[(token(r["still"]), f"{r['record']}/{r['frame']}", r["field"])] = r["text"]
    skip = {(r["video"], r["frame"]) for r in
            con.execute("select video, frame from labels where field = 'total' and text = 'skip'")}
    for r in con.execute("select video, frame, field, text from labels where frame != ''"):
        if (r["video"], r["frame"]) in skip or r["text"] is None:
            continue
        out[(r["video"], f"{r['video']}/{r['frame']}", r["field"])] = r["text"]
    return out


def hard_keys(con) -> set[tuple]:
    """(fixture, frame) of every frame or still the operator corrected a reader
    pre-fill on - the hard examples CORRECTIONS.md section 3 weights."""
    out: set[tuple] = set()
    for r in con.execute("select * from corrections where kind = 'text' and proposedBy = 'reader'"):
        frame = r["frame"] or None
        if r["video"]:
            out.add((r["video"], f"{r['video']}/{frame}" if frame else None))
        elif r["record"]:
            meta = con.execute("select still from frames where record = ? and frame = ''", (r["record"],)).fetchone()
            if meta is None:
                continue
            out.add((token(meta["still"]), f"{r['record']}/{frame}" if frame else None))
        elif r["still"]:
            out.add((token(r["still"]), None))
    return out


def expand_hard(cells: list[dict], weight: int) -> list[dict]:
    """Repeat a hard frame's or still's cells ``weight`` times; the rest once.
    Every copy records the weight it was given in the manifest."""
    if weight <= 1:
        return [dict(c, weight=1) for c in cells]
    out: list[dict] = []
    for c in cells:
        n = weight if c["hard"] else 1
        for _ in range(n):
            out.append(dict(c, weight=n))
    return out


def cap_sources(cells: list[dict], cap: float, seed: int) -> list[dict]:
    """Drop cells so no source (still, record or video) exceeds ``cap`` of the
    pool, by uniform subsampling under a fixed seed. Water-filling finds the
    largest per-source count ``T`` whose kept pool still satisfies the cap, so
    the smallest number of cells is dropped; the result keeps the input order."""
    if cap <= 0 or not cells:
        return list(cells)
    counts = Counter(c["source"] for c in cells)
    lo, hi = 0.0, float(max(counts.values()))
    for _ in range(64):
        mid = (lo + hi) / 2
        total = sum(min(c, mid) for c in counts.values())
        if mid <= cap * total:
            lo = mid
        else:
            hi = mid
    keep = {s: min(c, int(lo)) for s, c in counts.items()}
    by_source: dict[str, list[int]] = defaultdict(list)
    for i, c in enumerate(cells):
        by_source[c["source"]].append(i)
    rng = np.random.default_rng(seed)
    chosen: set[int] = set()
    for s in sorted(by_source):
        idxs = by_source[s]
        k = min(len(idxs), keep[s])
        if k < len(idxs):
            for j in sorted(rng.choice(len(idxs), size=k, replace=False)):
                chosen.add(idxs[j])
        else:
            chosen.update(idxs)
    return [c for i, c in enumerate(cells) if i in chosen]


def composition(cells: list[dict]) -> dict:
    total = len(cells) or 1
    makes = Counter(c["make"] for c in cells)
    sources = Counter(c["source"] for c in cells)
    fixtures = Counter(token(c["fixture"]) if not c["fixture"].startswith("video-")
                       else c["fixture"] for c in cells)
    return {
        "cells": len(cells),
        "by_make": dict(sorted(makes.items())),
        "top_sources": [(s, round(n / total, 4)) for s, n in sources.most_common(10)],
        "top_fixtures": [(f, round(n / total, 4)) for f, n in fixtures.most_common(10)],
    }


def heldout_names(con) -> set[str]:
    return corpus_db.heldout_names(con)


# A decimal mark sits in the gap after its glyph (PU.17/34b), so a crop that
# stops at the cell's right edge never shows it. ``--dp-crop gap`` extends the
# crop by this fraction of the cell's width (one pitch) before the resample.
DP_GAP_FRACTION: float = 0.4


def ink_centroid(cell_lum: np.ndarray) -> float | None:
    """The column-ink centroid of a crop, as a fraction of its width.

    Ink is the deviation from the crop's median in the strip's ink direction -
    the slicer's polarity rule (``PumpGlyphSlicer.prepare``): dark-on-light when
    the spread below the median exceeds the spread above, light-on-dark
    otherwise. ``None`` when the crop holds no ink (nothing to judge)."""
    p05, p50, p95 = np.percentile(cell_lum, [5, 50, 95])
    dark_on_light = (p50 - p05) > (p95 - p50)
    ink = (p50 - cell_lum) if dark_on_light else (cell_lum - p50)
    col = np.clip(ink, 0.0, None).sum(axis=0)
    total = float(col.sum())
    if total <= 0.0:
        return None
    x = np.arange(col.size, dtype=np.float64)
    return float((x * col).sum() / total / col.size)


def crop_cell(
    strip: Image.Image, box: dict, *, dp_crop: str = "off", measure: bool = False
) -> tuple[np.ndarray, float | None]:
    """Crop one cell to 32x48 and, when asked, its column-ink centroid.

    ``dp_crop="gap"`` widens the crop to the right by ``DP_GAP_FRACTION`` of the
    cell width; the centroid is always measured on the un-widened cell, so it
    judges the digit's alignment, not the mark's."""
    sw, sh = strip.size
    x0 = max(0, min(sw - 1, int(round(box["x0"] * sw))))
    x1 = max(x0 + 1, min(sw, int(round(box["x1"] * sw))))
    y0 = max(0, min(sh - 1, int(round(box["y0"] * sh))))
    y1 = max(y0 + 1, min(sh, int(round(box["y1"] * sh))))
    base = strip.crop((x0, y0, x1, y1))
    if dp_crop == "gap":
        xw = min(sw, x1 + max(1, int(round(DP_GAP_FRACTION * (x1 - x0)))))
        region = strip.crop((x0, y0, xw, y1))
    else:
        region = base
    resized = region.resize((CELL_W, CELL_H), Image.BILINEAR)
    pixels = np.asarray(resized.convert("RGB"), dtype=np.uint8).transpose(2, 0, 1)
    centroid = ink_centroid(np.asarray(base.convert("L"), dtype=np.float32)) if measure else None
    return pixels, centroid


def glitch_frames(con) -> list[tuple[str, str]]:
    """(video, frame) of every labelled frame whose ``total`` differs from both
    neighbours in its run - a running display that glitched for a frame or two.
    The frame carries its own reading, so it is a label of its own, not the
    run's (the product owner's reason for round 11)."""
    rows = con.execute(
        "select video, frame, text from labels where field = 'total' and text is not null "
        "order by video, frame").fetchall()
    by_video: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for r in rows:
        by_video[r["video"]].append((r["frame"], r["text"]))
    out: list[tuple[str, str]] = []
    for video, seq in by_video.items():
        for i in range(1, len(seq) - 1):
            if seq[i][1] != seq[i - 1][1] and seq[i][1] != seq[i + 1][1]:
                out.append((video, seq[i][0]))
    return out


def build_cells(export: dict, text: dict, hard: set[tuple]) -> tuple[list[dict], dict]:
    """One entry per (window, cell) the database holds as TRAIN and labelled and
    the slicer counted right. Returns the cells and the per-fixture stats."""
    cells: list[dict] = []
    per_fixture: dict[str, dict] = defaultdict(lambda: {"offered": 0, "used": 0, "frames": 0})
    for wi, window in enumerate(export["windows"]):
        fixture = window["fixture"]
        frame = window["frame"]
        fixture_key = fixture if fixture.startswith("video-") else token(fixture)
        stats = per_fixture[fixture]
        stats["offered"] += 1
        if frame:
            stats["frames"] += 1
        label = text.get((fixture_key, frame, window["field"]))
        if label is None:
            continue
        expected = parse_cells(label)
        if not expected or len(expected) != len(window["cells"]):
            continue
        source = frame.split("/")[0] if frame else fixture
        is_hard = (fixture_key, frame) in hard or (fixture_key, None) in hard
        for ci, (box, cell_label) in enumerate(zip(window["cells"], expected)):
            cells.append({"fixture": fixture, "source": source, "make": make_of(fixture), "frame": frame,
                          "field": window["field"], "window": wi, "cell": ci, "strip": window["strip"],
                          "box": box, "bits": int(cell_label.bits), "hard": is_hard})
        stats["used"] += 1
    return cells, dict(per_fixture)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="pump_reader.realglyphs")
    parser.add_argument("--export", type=Path, default=EXPORT / "train-slices.json")
    parser.add_argument("--also", type=Path, action="append", default=[],
                        help="further export manifests to merge (the videos': train-videos.json)")
    parser.add_argument("--out", type=Path, default=ROOT / "ml" / "pump-reader" / ".out" / "real")
    parser.add_argument("--db", type=Path, default=None, help="corpus database (default: the committed one)")
    parser.add_argument("--cap-fixture", type=float, default=0.0,
                        help="max share of the pool any one still, record or video may contribute (0 = off)")
    parser.add_argument("--hard-weight", type=int, default=1,
                        help="repeat a corrected reader pre-fill's cells this many times (1 = off)")
    parser.add_argument("--seed", type=int, default=0, help="the cap's subsampling seed")
    parser.add_argument("--centred", type=float, default=0.0,
                        help="keep a cell only when its column-ink centroid is within this "
                             "fraction of the cell width from the centre (0 = off)")
    parser.add_argument("--dp-crop", choices=["off", "gap", "none"], default="none",
                        help="off: original framing, keep the dp label; gap: widen the crop "
                             "right by 0.4 x pitch; none: clear every dp bit (the slicer owns it)")
    args = parser.parse_args(argv)
    if not args.export.exists():
        print(f"{args.export} missing - run PUMP_TRAIN_EXPORT=1 swift test --filter PumpTrainSliceExportTests")
        return 1
    export = json.loads(args.export.read_text())
    for extra in args.also:
        export["windows"].extend(json.loads(extra.read_text())["windows"])
    con = corpus_db.connect(args.db)
    try:
        heldout = heldout_names(con)
        for window in export["windows"]:
            if window["fixture"] in heldout:
                raise SystemExit(f"heldout fixture in the train export: {window['fixture']}")
        text = db_windows(con)
        hard = hard_keys(con)
        glitches = glitch_frames(con)
    finally:
        con.close()

    raw, per_fixture = build_cells(export, text, hard)

    # One crop pass over the raw cells: it measures the centred filter and keeps
    # the resized pixels, so a cell the cap later drops is never cropped twice.
    xs: list[np.ndarray] = []
    ys: list[int] = []
    kept: list[dict] = []
    dropped: Counter = Counter()
    dropped_fixture: Counter = Counter()
    current_strip: str | None = None
    strip: Image.Image | None = None
    for c in raw:
        if c["strip"] != current_strip:
            strip = Image.open(args.export.parent / c["strip"])
            current_strip = c["strip"]
        pixels, centroid = crop_cell(strip, c["box"], dp_crop=args.dp_crop, measure=args.centred > 0)
        if args.centred > 0 and centroid is not None and abs(centroid - 0.5) > args.centred:
            label = SegmentLabel(c["bits"])
            dropped[label.digit or ("dp" if label.dp else "blank")] += 1
            dropped_fixture[c["fixture"]] += 1
            continue
        bits = c["bits"] & 0x7F if args.dp_crop == "none" else c["bits"]
        kept.append(dict(c, pixels=pixels, bits=bits))

    before = composition(kept)
    weighted = expand_hard(kept, args.hard_weight)
    pool = cap_sources(weighted, args.cap_fixture, args.seed)
    after = composition(pool)

    cells_meta: list[dict] = []
    for c in pool:
        xs.append(c["pixels"])
        ys.append(c["bits"])
        cells_meta.append({"fixture": c["fixture"], "frame": c["frame"], "field": c["field"],
                           "window": c["window"], "cell": c["cell"], "bits": c["bits"], "weight": c["weight"]})

    args.out.mkdir(parents=True, exist_ok=True)
    x = np.stack(xs) if xs else np.zeros((0, 3, CELL_H, CELL_W), np.uint8)
    np.savez_compressed(args.out / "cells.npz", x=x, y=np.asarray(ys, dtype=np.uint8))
    label_counts: Counter = Counter()
    for b in ys:
        lab = SegmentLabel(b)
        label_counts[lab.digit or ("dp" if lab.dp else "blank")] += 1
    try:
        source = str(args.export.relative_to(ROOT))
    except ValueError:
        source = str(args.export)
    manifest = {
        "source": source,
        "cells": len(ys),
        "windows_offered": len(export["windows"]),
        "windows_used": sum(s["used"] for s in per_fixture.values()),
        "cap_fixture": args.cap_fixture,
        "hard_weight": args.hard_weight,
        "seed": args.seed,
        "centred": args.centred,
        "dp_crop": args.dp_crop,
        "centred_dropped": dict(sorted(dropped.items())),
        "centred_dropped_total": sum(dropped.values()),
        "centred_dropped_fixtures": dict(sorted(dropped_fixture.items())),
        "labels": dict(sorted(label_counts.items())),
        "composition_before": before,
        "composition_after": after,
        "fixtures": dict(sorted(per_fixture.items())),
        "cell_meta": cells_meta,
    }
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=1))
    used = manifest["windows_used"]
    print(f"{len(ys)} real glyphs from {used}/{len(export['windows'])} windows "
          f"({len(per_fixture)} train fixtures); labels {dict(sorted(label_counts.items()))}")
    print(f"  centred {args.centred}: dropped {sum(dropped.values())} cells "
          f"by class {dict(sorted(dropped.items()))}")
    if dropped_fixture:
        print(f"  centred drops top fixtures: {dropped_fixture.most_common(10)}")
    print(f"  glitch-labelled frames: {len(glitches)}")
    print(f"  pool before: {before['cells']} cells by make {before['by_make']}")
    print(f"  pool before top sources: {before['top_sources']}")
    print(f"  pool before top fixtures: {before['top_fixtures']}")
    print(f"  pool after:  {after['cells']} cells by make {after['by_make']}")
    print(f"  pool after top sources: {after['top_sources']}")
    print(f"  pool after top fixtures: {after['top_fixtures']}")
    low = [(f, s) for f, s in per_fixture.items() if s["offered"] >= 10 and s["used"] / s["offered"] < 0.5]
    for f, s in sorted(low):
        print(f"  low acceptance {f[:40]}: {s['used']}/{s['offered']} windows (slicer count disagrees)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

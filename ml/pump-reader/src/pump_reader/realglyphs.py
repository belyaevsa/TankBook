"""CLI: ``python -m pump_reader.realglyphs [--out .out/real]``.

Turns the Swift export of the train split (`PumpTrainSliceExportTests`,
``ios/.build/pump-reader-out/train/train-slices.json``: every train window
of the stills and their tracked Live frames, warped to the strip and cut by
the production slicer) into labelled 32x48 glyph cells for the classifier.

A window is used only when the slicer's cell count equals the label's glyph
count - then cell *i* carries label *i* (``score.parse_cells``: digits, the
dp bit on the cell before a separator, blanks for spaces). A window the
slicer miscounts is skipped whole: aligning a wrong count to the text would
label cells with their neighbours' digits, which is worse than no label.

Output: ``<out>/cells.npz`` (uint8 ``x`` of shape ``[n, 3, 48, 32]``, uint8
``y`` of the 8-bit segment labels) and ``<out>/manifest.json`` (per cell:
fixture, frame, field, window index, cell index, label; per fixture:
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

from .glyph import CELL_H, CELL_W
from .score import parse_cells

ROOT = Path(__file__).resolve().parents[4]
EXPORT = ROOT / "ios" / ".build" / "pump-reader-out" / "train"
SPLIT = ROOT / "Spike" / "ReceiptSpike" / "fixtures" / "pump" / "split.csv"


def heldout_names() -> set[str]:
    names = set()
    for line in SPLIT.read_text().splitlines()[1:]:
        name, _, split = line.partition(",")
        if split.strip() == "heldout":
            names.add(name)
    return names


def crop_cell(strip: Image.Image, box: dict) -> np.ndarray:
    sw, sh = strip.size
    x0 = max(0, min(sw - 1, int(round(box["x0"] * sw))))
    x1 = max(x0 + 1, min(sw, int(round(box["x1"] * sw))))
    y0 = max(0, min(sh - 1, int(round(box["y0"] * sh))))
    y1 = max(y0 + 1, min(sh, int(round(box["y1"] * sh))))
    cell = strip.crop((x0, y0, x1, y1)).resize((CELL_W, CELL_H), Image.BILINEAR)
    return np.asarray(cell.convert("RGB"), dtype=np.uint8).transpose(2, 0, 1)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="pump_reader.realglyphs")
    parser.add_argument("--export", type=Path, default=EXPORT / "train-slices.json")
    parser.add_argument("--out", type=Path, default=ROOT / "ml" / "pump-reader" / ".out" / "real")
    args = parser.parse_args(argv)
    if not args.export.exists():
        print(f"{args.export} missing - run PUMP_TRAIN_EXPORT=1 swift test --filter PumpTrainSliceExportTests")
        return 1
    export = json.loads(args.export.read_text())
    heldout = heldout_names()
    xs: list[np.ndarray] = []
    ys: list[int] = []
    cells_meta: list[dict] = []
    per_fixture: dict[str, dict] = defaultdict(lambda: {"offered": 0, "used": 0, "frames": 0})
    labels = Counter()
    for wi, window in enumerate(export["windows"]):
        fixture = window["fixture"]
        if fixture in heldout:
            raise SystemExit(f"heldout fixture in the train export: {fixture}")
        stats = per_fixture[fixture]
        stats["offered"] += 1
        if window["frame"]:
            stats["frames"] += 1
        expected = parse_cells(window["text"])
        if len(expected) != len(window["cells"]) or not expected:
            continue
        strip = Image.open(args.export.parent / window["strip"])
        for ci, (box, label) in enumerate(zip(window["cells"], expected)):
            xs.append(crop_cell(strip, box))
            ys.append(label.bits)
            labels[label.digit or ("dp" if label.dp else "blank")] += 1
            cells_meta.append({"fixture": fixture, "frame": window["frame"], "field": window["field"],
                               "window": wi, "cell": ci, "bits": label.bits})
        stats["used"] += 1
    args.out.mkdir(parents=True, exist_ok=True)
    x = np.stack(xs) if xs else np.zeros((0, 3, CELL_H, CELL_W), np.uint8)
    np.savez_compressed(args.out / "cells.npz", x=x, y=np.asarray(ys, dtype=np.uint8))
    manifest = {
        "source": str(args.export.relative_to(ROOT)),
        "cells": len(ys),
        "windows_offered": len(export["windows"]),
        "windows_used": sum(s["used"] for s in per_fixture.values()),
        "labels": dict(sorted(labels.items())),
        "fixtures": dict(sorted(per_fixture.items())),
        "cell_meta": cells_meta,
    }
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=1))
    used = manifest["windows_used"]
    print(f"{len(ys)} real glyphs from {used}/{len(export['windows'])} windows "
          f"({len(per_fixture)} train fixtures); labels {dict(sorted(labels.items()))}")
    low = [(f, s) for f, s in per_fixture.items() if s["offered"] >= 10 and s["used"] / s["offered"] < 0.5]
    for f, s in sorted(low):
        print(f"  low acceptance {f[:40]}: {s['used']}/{s['offered']} windows (slicer count disagrees)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

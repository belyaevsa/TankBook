"""Render a contact sheet of a real pool: 18 random cells per class, labelled
from ``SegmentLabel(bits).digit`` - the recipe the orchestrator looks at.

    python runs/2026-09-22/cells_sheet.py <pool-dir> <out.png> [per-class]

The cells are upscaled 4x so the segment shapes and the panel contrast are
visible; the sheet is a diagnosis aid, never a metric.
"""

from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from pump_reader.glyph import SegmentLabel  # noqa: E402

SCALE = 4
LABEL_W = 80
PAD = 6


def class_of(bits: int) -> str:
    label = SegmentLabel(int(bits))
    return str(label.digit) if label.digit is not None else "?"


def main(argv: list[str]) -> int:
    pool = Path(argv[1])
    out = Path(argv[2])
    per_class = int(argv[3]) if len(argv) > 3 else 18
    data = np.load(pool / "cells.npz")
    x, y = data["x"], data["y"]
    manifest = json.loads((pool / "manifest.json").read_text())

    by_class: dict[str, list[int]] = defaultdict(list)
    for i, bits in enumerate(y):
        by_class[class_of(int(bits))].append(i)
    classes = sorted(by_class)
    rng = np.random.default_rng(0)

    cw, ch = x.shape[3] * SCALE, x.shape[2] * SCALE
    width = LABEL_W + per_class * (cw + PAD) + PAD
    height = len(classes) * (ch + PAD) + PAD
    sheet = Image.new("RGB", (width, height), (24, 24, 28))
    draw = ImageDraw.Draw(sheet)
    for row, cls in enumerate(classes):
        idx = by_class[cls]
        take = rng.choice(len(idx), size=min(per_class, len(idx)), replace=False)
        y0 = PAD + row * (ch + PAD)
        draw.text((PAD, y0 + ch // 2 - 6), f"{cls} ({len(idx)})", fill=(230, 230, 230))
        for col, j in enumerate(sorted(take)):
            cell = Image.fromarray(x[idx[j]].transpose(1, 2, 0), "RGB").resize(
                (cw, ch), Image.NEAREST)
            sheet.paste(cell, (LABEL_W + col * (cw + PAD), y0))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(f"{out}  {width}x{height}  classes {classes}  "
          f"cells {int(y.shape[0])}  pool {manifest.get('dp_crop')}/{manifest.get('centred')}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

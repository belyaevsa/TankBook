"""Render a contact sheet of the synthetic renderer, 18 cells per class.

    python runs/2026-09-22/synth_sheet.py <out.png> [per-class] [seed]

The counterpart to ``cells_sheet.py``: the same grid and upscale, so the
orchestrator can put the synthetic pool beside the real one.
"""

from __future__ import annotations

import sys
from collections import defaultdict
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from pump_reader.dataset import SyntheticDataset, target_to_bits  # noqa: E402
from pump_reader.glyph import SegmentLabel  # noqa: E402

SCALE = 4
LABEL_W = 80
PAD = 6


def class_of(bits: int) -> str:
    label = SegmentLabel(int(bits))
    return str(label.digit) if label.digit is not None else "?"


def main(argv: list[str]) -> int:
    out = Path(argv[1])
    per_class = int(argv[2]) if len(argv) > 2 else 18
    seed = int(argv[3]) if len(argv) > 3 else 20260922
    ds = SyntheticDataset(seed=seed, length=4000, cache=False)
    by_class: dict[str, list[np.ndarray]] = defaultdict(list)
    for i in range(len(ds)):
        tensor, target = ds[i]
        cls = class_of(target_to_bits(target))
        if len(by_class[cls]) < per_class:
            by_class[cls].append((np.asarray(tensor * 255, dtype=np.uint8).transpose(1, 2, 0)))
        if len(by_class) == 10 and all(len(v) >= per_class for v in by_class.values()):
            break
    classes = sorted(by_class)
    cw, ch = 32 * SCALE, 48 * SCALE
    width = LABEL_W + per_class * (cw + PAD) + PAD
    height = len(classes) * (ch + PAD) + PAD
    sheet = Image.new("RGB", (width, height), (24, 24, 28))
    draw = ImageDraw.Draw(sheet)
    for row, cls in enumerate(classes):
        y0 = PAD + row * (ch + PAD)
        draw.text((PAD, y0 + ch // 2 - 6), f"{cls} ({len(by_class[cls])})", fill=(230, 230, 230))
        for col, arr in enumerate(by_class[cls][:per_class]):
            cell = Image.fromarray(arr, "RGB").resize((cw, ch), Image.NEAREST)
            sheet.paste(cell, (LABEL_W + col * (cw + PAD), y0))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(f"{out}  {width}x{height}  classes {classes}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

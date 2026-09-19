"""CLI: ``python -m pump_reader.render``.

Writes ``DIR/glyphs/NNNNNN.png`` plus ``DIR/labels.csv``, and with ``--rows``
also ``DIR/rows/NNNNNN.png`` plus ``DIR/rows.json``. ``--seed`` makes the whole
run reproducible.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

from .glyph import label_class, render_glyph, sample_label
from .profiles import PROFILES, sample_make
from .row import render_row, sample_row_text

CSV_HEADER = "file,label,digit,make,technology\n"


def _csv_digit(label) -> str:
    d = label.digit
    return d if d is not None else ""


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="pump_reader.render")
    parser.add_argument("--count", type=int, required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--make", type=str, default=None)
    parser.add_argument("--rows", action="store_true")
    args = parser.parse_args(argv)

    rng = np.random.default_rng(args.seed)

    glyphs_dir = args.out / "glyphs"
    rows_dir = args.out / "rows"
    glyphs_dir.mkdir(parents=True, exist_ok=True)

    csv_lines = [CSV_HEADER]
    for i in range(args.count):
        make = sample_make(rng, args.make)
        profile = PROFILES[make]
        label = sample_label(rng)
        img = render_glyph(label, profile, rng)
        filename = f"{i:06d}.png"
        img.save(glyphs_dir / filename)
        csv_lines.append(
            f"glyphs/{filename},{label.bits},{_csv_digit(label)},{make},{profile.technology}\n"
        )

    (args.out / "labels.csv").write_text("".join(csv_lines), encoding="utf-8")

    if args.rows:
        rows_dir.mkdir(parents=True, exist_ok=True)
        n_rows = max(5, args.count // 10)
        rows_json = []
        for i in range(n_rows):
            make = sample_make(rng, args.make)
            profile = PROFILES[make]
            text = sample_row_text(rng)
            img, boxes = render_row(text, profile, rng)
            filename = f"{i:06d}.png"
            img.save(rows_dir / filename)
            rows_json.append(
                {
                    "file": f"rows/{filename}",
                    "text": text,
                    "make": make,
                    "technology": profile.technology,
                    "boxes": [
                        {
                            "label": b.label.bits,
                            "digit": _csv_digit(b.label),
                            "class": label_class(b.label),
                            "x": round(b.x, 3),
                            "y": round(b.y, 3),
                            "w": round(b.w, 3),
                            "h": round(b.h, 3),
                        }
                        for b in boxes
                    ],
                }
            )
        (args.out / "rows.json").write_text(
            json.dumps(rows_json, indent=2), encoding="utf-8"
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())

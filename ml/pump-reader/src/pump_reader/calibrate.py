"""CLI: ``python -m pump_reader.calibrate --slices … --windows … --out …``.

Measures the corpus's aggregate cell geometry and label statistics and writes a
``calibration.json`` the renderer samples from. Sources are ``slices.json`` cell
rects (normalised over the 96px strip) crossed with ``windows.json`` window
quads and strings - aggregate statistics only, never pixels, never per-fixture
labels (product owner, 2026-09-19, ``docs/EXTRACTION.md`` -> Decisions). Only
transaction windows (total / liters / unitPrice) are measured; the grade-price
board is out of the ship gate.

Measured quantities, each stored as quantiles (p5/p25/p50/p75/p95) plus a count:

- ``aspect``: cell aspect before the 32x48 resize, pitch / band height, computed
  as ``(x1-x0)/(y1-y0) * quad_aspect`` (the strip width is ``96 * quad_aspect``).
- ``phase.right_margin_frac``: the ink's right-edge margin as a fraction of the
  pitch. The Swift slicer anchors the grid on run ENDS (``PumpGlyphSlicer``), so
  the ink's right edge sits at the cell's right edge: 0 by construction.
- ``phase.left_margin_frac``: the ink's left-edge margin as a fraction of the
  pitch - the full pitch slack, since the grid is right-aligned. Estimated as
  ``1 - BODY_RATIO / aspect`` with ``BODY_RATIO = 0.55``, the nominal
  seven-segment body-to-height ratio the review measured ("~0.5-0.6 of band
  height"). The renderer does not consume this; it right-aligns and lets the
  profile pitch carry the slack.
- ``digit_frequency``: per field, counts of digits 0-9 across the window strings.
- ``leading_zero_run_length``: per field, the distribution of leading ``0`` runs
  at the start of each window string (zero padding), quantiles plus count.
- ``dp_rate``: per field, the fraction of digit cells whose decimal mark is
  drawn on them (a ``.`` or ``,`` follows the digit) - the presence rate the
  dataset samples dp at.
- ``dp_comma_rate``: per field, the fraction of decimal marks that are commas
  (``,``) rather than dots (``.``).
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "scripts"))
import corpus_db  # noqa: E402

TX_FIELDS: tuple[str, ...] = ("total", "liters", "unitPrice")
QUANTILES: tuple[float, ...] = (0.05, 0.25, 0.50, 0.75, 0.95)
Q_KEYS: tuple[str, ...] = ("p5", "p25", "p50", "p75", "p95")
STRIP_HEIGHT: int = 96
# Nominal seven-segment glyph body width as a fraction of the band height, from
# the corpus review ("glyph BODY (~0.5-0.6 of band height)", PU.12 finding 1).
BODY_RATIO: float = 0.55


def _quantiles(values: list[float]) -> dict:
    arr = np.asarray(values, dtype=np.float64)
    out = {k: float(np.percentile(arr, 100.0 * q)) for k, q in zip(Q_KEYS, QUANTILES)}
    out["count"] = len(values)
    return out


def _quad_aspect(quad: np.ndarray) -> float:
    """Width/height of a quad (mean of opposite edges), matching ``score._quad_size``."""
    tl, tr, br, bl = quad
    w = (np.linalg.norm(tr - tl) + np.linalg.norm(br - bl)) / 2.0
    h = (np.linalg.norm(bl - tl) + np.linalg.norm(br - tr)) / 2.0
    return float(w / h) if h > 0 else 1.0


def _digits(text: str) -> list[str]:
    return [ch for ch in text if ch in "0123456789"]


def _leading_zero_run(text: str) -> int:
    """Consecutive ``0`` characters at the very start of a window string."""
    n = 0
    for ch in text:
        if ch == "0":
            n += 1
        else:
            break
    return n


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="pump_reader.calibrate")
    parser.add_argument("--slices", type=Path, required=True)
    parser.add_argument("--windows", type=Path, default=None,
                        help="a windows.json file; omit to read the stills from the database")
    parser.add_argument("--db", type=Path, default=None, help="corpus database (default: the committed one)")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)

    if args.windows is not None:
        windows = json.loads(args.windows.read_text(encoding="utf-8"))
    else:
        con = corpus_db.connect(args.db)
        try:
            windows = corpus_db.entries(con)
        finally:
            con.close()
    slices = json.loads(args.slices.read_text(encoding="utf-8"))

    aspects: list[float] = []
    left_margins: list[float] = []
    window_count = 0
    cell_count = 0
    per_field: dict[str, dict] = {f: {"windows": 0, "cells": 0} for f in TX_FIELDS}
    digit_freq: dict[str, Counter] = {f: Counter() for f in TX_FIELDS}
    zero_runs: dict[str, list[int]] = {f: [] for f in TX_FIELDS}
    dp_digits: dict[str, int] = {f: 0 for f in TX_FIELDS}
    digit_total: dict[str, int] = {f: 0 for f in TX_FIELDS}
    commas: dict[str, int] = {f: 0 for f in TX_FIELDS}
    dps: dict[str, int] = {f: 0 for f in TX_FIELDS}

    for filename, ann in windows.items():
        if filename == "_about":
            continue
        fixture_slices = slices.get(filename)
        if not fixture_slices:
            continue
        for wi, win in enumerate(ann.get("windows", [])):
            field = win.get("field")
            if field not in TX_FIELDS:
                continue
            text = win.get("text", "")
            if not text:
                continue
            quad = np.asarray(win["quad"], dtype=np.float64)
            aspect_q = _quad_aspect(quad)
            window_count += 1
            per_field[field]["windows"] += 1

            digits = _digits(text)
            digit_freq[field].update(digits)
            zero_runs[field].append(_leading_zero_run(text))

            # dp presence and comma rate from the string.
            chars = list(text)
            for i, ch in enumerate(chars):
                if ch not in "0123456789":
                    continue
                digit_total[field] += 1
                if i + 1 < len(chars) and chars[i + 1] in ".,":
                    dp_digits[field] += 1
                    dps[field] += 1
                    if chars[i + 1] == ",":
                        commas[field] += 1

            if wi >= len(fixture_slices) or fixture_slices[wi] is None:
                continue
            for cell in fixture_slices[wi].get("cells", []):
                if cell.get("isBlank"):
                    continue
                x0, x1 = cell["x0"], cell["x1"]
                y0, y1 = cell["y0"], cell["y1"]
                band = y1 - y0
                if band <= 0:
                    continue
                aspect = ((x1 - x0) * aspect_q) / band
                aspects.append(aspect)
                left_margins.append(min(1.0, max(0.0, 1.0 - BODY_RATIO / aspect)))
                cell_count += 1
                per_field[field]["cells"] += 1

    def _field_rate(num: dict[str, int], den: dict[str, int]) -> dict:
        rates = {f: round(num[f] / den[f], 4) if den[f] else 0.0 for f in TX_FIELDS}
        rates["all"] = round(sum(num.values()) / sum(den.values()), 4) if sum(den.values()) else 0.0
        return rates

    digit_frequency: dict[str, dict] = {
        f: {d: digit_freq[f][d] for d in "0123456789"} for f in TX_FIELDS
    }
    leading_zero = {f: _quantiles([float(v) for v in zero_runs[f]]) for f in TX_FIELDS}

    out = {
        "_about": (
            "Aggregate corpus geometry and label statistics for the synthetic renderer, "
            "measured over transaction windows only (total/liters/unitPrice) from "
            "slices.json cell rects crossed with windows.json quads and strings. Never "
            "pixels, never per-fixture labels (product owner, 2026-09-19)."
        ),
        "sources": {"slices": str(args.slices),
                    "windows": str(args.windows) if args.windows is not None else str(args.db or corpus_db.DB)},
        "strip_height": STRIP_HEIGHT,
        "body_ratio": BODY_RATIO,
        "counts": {
            "windows": window_count,
            "cells": cell_count,
            "per_field": per_field,
        },
        "aspect": _quantiles(aspects),
        "phase": {
            # The slicer anchors cells on run ends, so the ink right edge is the
            # cell right edge: right margin 0 by construction.
            "right_margin_frac": _quantiles([0.0] * cell_count),
            "left_margin_frac": _quantiles(left_margins),
        },
        "digit_frequency": digit_frequency,
        "leading_zero_run_length": leading_zero,
        "dp_rate": _field_rate(dp_digits, digit_total),
        "dp_comma_rate": _field_rate(commas, dps),
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(f"wrote {args.out}: {window_count} windows, {cell_count} cells")
    print(f"aspect p50={out['aspect']['p50']:.3f} dp_rate={out['dp_rate']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

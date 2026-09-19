"""The comma: the decimal mark is drawn where displays draw it (PU.17).

Oracle: the row's boxes. A comma follows its host glyph below the digit baseline
(in the gap after the glyph), and its short tail crosses into the NEXT cell's
left edge - so a cell cut from the next position carries the comma's tail with
dp = 0. LED heads keep the plain corner dot, so only LCD/VFD heads are measured.
The named mutation clamps the comma back inside the glyph box (the old dot) and
turns both assertions red.
"""

from __future__ import annotations

import numpy as np

from pump_reader.glyph import CELL_H, CELL_W, MARGIN, SegmentLabel
from pump_reader.profiles import PROFILES
from pump_reader.row import render_row_of_labels

_N = 60


def _lit_mask(img, profile) -> np.ndarray:
    arr = np.asarray(img, dtype=np.float32)
    lum = arr.mean(axis=2)
    on = sum(profile.on_color.midpoint()) / 3.0
    ground = sum(profile.ground_color.midpoint()) / 3.0
    threshold = (on + ground) / 2.0
    return lum < threshold if on < ground else lum > threshold


def _comma_profiles():
    return [p for p in PROFILES.values() if p.technology != "led"]


def test_comma_below_baseline_and_tail_in_next_cell() -> None:
    rng = np.random.default_rng(20260919)
    checked = 0
    for profile in _comma_profiles():
        for _ in range(_N):
            cells = [
                SegmentLabel.from_digit("2"),
                SegmentLabel.from_digit("8", dp=True),
                SegmentLabel.from_digit("2"),
            ]
            row, boxes = render_row_of_labels(
                cells, profile, rng, augment=False, strip_h=96, comma=True
            )
            host, nxt = boxes[1], boxes[2]
            baseline = int(round(host.y + CELL_H - MARGIN))
            mask = _lit_mask(row, profile)
            # strictly below the baseline: segment d's bottom edge sits ON the
            # baseline, the comma (clearance >= 0.05 x CELL_H) below it
            below = mask[baseline + 1:, :]
            # the comma sits below the digit's baseline
            assert below.any(), f"{profile.name}: no comma ink below the baseline"
            # the tail's rightmost column lands inside the NEXT cell's box
            rightmost = int(np.where(below.any(axis=0))[0].max())
            assert nxt.x <= rightmost < nxt.x + nxt.w, (
                f"{profile.name}: tail column {rightmost} not inside next box "
                f"[{nxt.x:.1f}, {nxt.x + nxt.w:.1f}]"
            )
            checked += 1
    assert checked == len(_comma_profiles()) * _N


def test_comma_host_digit_keeps_its_ink_above_baseline() -> None:
    # The host digit's own segments stay above the baseline: only the comma
    # occupies the below-baseline rows, which is what makes the dp cell's digit
    # sit in the top ~85% and the comma in the bottom band.
    rng = np.random.default_rng(20260920)
    for profile in _comma_profiles():
        cells = [
            SegmentLabel.from_digit("4"),
            SegmentLabel.from_digit("8", dp=True),
            SegmentLabel.from_digit("4"),
        ]
        row, boxes = render_row_of_labels(
            cells, profile, rng, augment=False, strip_h=96, comma=True
        )
        host = boxes[1]
        baseline = int(round(host.y + CELL_H - MARGIN))
        mask = _lit_mask(row, profile)
        above = mask[:baseline, int(host.x):int(host.x + CELL_W)]
        assert above.any(), f"{profile.name}: host digit ink missing above the baseline"

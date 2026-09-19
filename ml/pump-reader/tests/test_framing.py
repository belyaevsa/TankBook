"""Slicer framing: the cell is cut the way PumpGlyphSlicer hands it over.

Oracle: the slicer's geometry. An ``8`` spans the full glyph height, so the
ink-band y-crop (top of the highest lit pixel to the bottom of the lowest, no
vertical margin) must leave lit pixels within 2 px of both the top and bottom
canvas edges after the resize; the old margin framing left ``MARGIN`` of empty
space instead. A ``1`` is segments b and c - the right-side verticals - so its
lit columns must land in the right half of the canvas, not be centred by the
framing. Each test draws 300 samples (60 per make) and demands >= 95 % pass.
"""

from __future__ import annotations

import numpy as np

from pump_reader.dataset import render_slicer_cell
from pump_reader.glyph import SegmentLabel
from pump_reader.profiles import PROFILES

_N = 60  # samples per make (5 makes -> 300)


def _lit_mask(img, profile) -> np.ndarray:
    """The lit-pixel mask, mirroring ``MakeProfile.is_lit`` (midpoint threshold)."""
    arr = np.asarray(img, dtype=np.float32)
    lum = arr.mean(axis=2)
    on = sum(profile.on_color.midpoint()) / 3.0
    ground = sum(profile.ground_color.midpoint()) / 3.0
    threshold = (on + ground) / 2.0
    return lum < threshold if on < ground else lum > threshold


def test_slicer_framing_8_touches_top_and_bottom() -> None:
    rng = np.random.default_rng(20260919)
    fails = 0
    for profile in PROFILES.values():
        for _ in range(_N):
            img = render_slicer_cell(SegmentLabel.from_digit("8"), profile, rng, augment=False)
            rows = np.where(_lit_mask(img, profile).any(axis=1))[0]
            if rows.size == 0 or rows.min() > 2 or rows.max() < 45:
                fails += 1
    assert fails / (5 * _N) <= 0.05, f"8 band trim failed {fails}/{5 * _N}"


def test_slicer_framing_1_sits_in_the_right_half() -> None:
    rng = np.random.default_rng(20260920)
    fails = 0
    for profile in PROFILES.values():
        for _ in range(_N):
            img = render_slicer_cell(SegmentLabel.from_digit("1"), profile, rng, augment=False)
            cols = np.where(_lit_mask(img, profile).any(axis=0))[0]
            if cols.size == 0 or cols.min() < 16:
                fails += 1
    assert fails / (5 * _N) <= 0.05, f"1 right-half failed {fails}/{5 * _N}"

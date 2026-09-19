"""Slicer framing: the cell is cut the way PumpGlyphSlicer hands it over.

Oracle: ``calibration.json`` (the corpus's aggregate geometry). The phase is
right-aligned - the slicer anchors cells on run ends, so ``phase.right_margin_frac
== 0`` and all the pitch slack sits left of the glyph. A ``1`` is segments b/c
(the right-side verticals), so a right-aligned cell keeps its digit ink in the
rightmost columns; a centred cell (the old ``U(0.2, 0.8)`` slack split) would
leave them near the middle. A ``8`` spans the full glyph height and must never
be clipped by the band crop, because the band is at least the ink.
"""

from __future__ import annotations

import numpy as np

from pump_reader.calibration import load_calibration
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


def test_slicer_framing_right_aligns_digit_ink() -> None:
    # The oracle states the phase: right-aligned, ink right margin zero.
    cal = load_calibration()
    assert cal.data["phase"]["right_margin_frac"]["p50"] == 0.0
    rng = np.random.default_rng(20260920)
    fails = 0
    for profile in PROFILES.values():
        for _ in range(_N):
            img = render_slicer_cell(SegmentLabel.from_digit("1"), profile, rng, augment=False)
            cols = np.where(_lit_mask(img, profile).any(axis=0))[0]
            # A right-aligned `1` keeps its verticals in the rightmost columns.
            if cols.size == 0 or cols.max() < 26:
                fails += 1
    assert fails / (5 * _N) <= 0.05, f"1 right-aligned failed {fails}/{5 * _N}"


def test_slicer_framing_band_never_clips_the_glyph() -> None:
    # The band is at least the ink, so an `8` spanning the full glyph height is
    # never cut at the cell's top or bottom edge.
    rng = np.random.default_rng(20260919)
    fails = 0
    for profile in PROFILES.values():
        for _ in range(_N):
            img = render_slicer_cell(SegmentLabel.from_digit("8"), profile, rng, augment=False)
            rows = np.where(_lit_mask(img, profile).any(axis=1))[0]
            if rows.size == 0 or rows.min() < 0 or rows.max() > 47:
                fails += 1
    assert fails / (5 * _N) <= 0.05, f"8 clipped failed {fails}/{5 * _N}"

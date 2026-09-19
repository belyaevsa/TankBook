"""Profiles differ in GEOMETRY, not only in colour.

Oracle: the profile geometry constants (ratio, gap, slant, dp). Every make's
``8`` is rendered as a lit-segment mask (no colour, bloom or augmentation) with
the same seed, and every pair of masks must disagree on more than
``GEOMETRY_FLOOR`` of the canvas. The named mutation - copying ``gilbarco``'s
``segment_ratio``, ``segment_gap`` and ``slant_deg`` onto ``scheidt`` - sends
this red even though the two palettes still differ, which is the gap the
colour-driven test in ``test_profiles_differ.py`` cannot see.
"""

from __future__ import annotations

import numpy as np

from pump_reader.glyph import SegmentLabel, render_glyph_mask
from pump_reader.profiles import PROFILES

# One percent of the 32x48 canvas is 15 pixels: less than a single segment's
# thickness change, so any geometry constant that moves clears it.
GEOMETRY_FLOOR = 0.01


def _mask(name: str) -> np.ndarray:
    rng = np.random.default_rng(0)
    return np.asarray(render_glyph_mask(SegmentLabel.from_digit("8"), PROFILES[name], rng)) > 127


def test_every_make_differs_in_geometry() -> None:
    names = list(PROFILES)
    masks = {n: _mask(n) for n in names}
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            a, b = names[i], names[j]
            d = float(np.mean(masks[a] != masks[b]))
            assert d > GEOMETRY_FLOOR, f"{a} vs {b}: masks differ on {d:.4f} of the canvas"

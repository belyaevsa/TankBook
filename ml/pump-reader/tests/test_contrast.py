"""Contrast collapse: the augment maps the on/ground colours toward each other so
a sample's on/ground difference is at most 25% of the original, at the configured
probability.

Oracle: the config - ``DEFAULT_PROBS["contrast_collapse"]`` (the 10-20% the brief
sets) and the 10-25% target range inside ``apply_contrast_collapse``.
"""

from __future__ import annotations

import numpy as np

from pump_reader.augment import DEFAULT_PROBS, apply_contrast_collapse
from pump_reader.glyph import SegmentLabel, render_glyph
from pump_reader.profiles import PROFILES


def test_contrast_collapse_lands_below_25_percent() -> None:
    rng = np.random.default_rng(0)
    profile = PROFILES["gilbarco"]
    img = np.asarray(
        render_glyph(SegmentLabel.from_digit("8"), profile, rng, augment=False),
        dtype=np.float32,
    )
    lum = img.mean(axis=2)
    original = float(lum.max() - lum.min())
    assert original > 0.0

    collapsed = apply_contrast_collapse(img, profile, rng)
    clum = collapsed.mean(axis=2)
    new_diff = float(clum.max() - clum.min())
    assert new_diff <= 0.25 * original, f"{new_diff:.2f} > 0.25 * {original:.2f}"


def test_contrast_collapse_probability_is_configured() -> None:
    assert 0.10 <= DEFAULT_PROBS["contrast_collapse"] <= 0.20, (
        f"contrast_collapse probability {DEFAULT_PROBS['contrast_collapse']} outside 10-20%"
    )

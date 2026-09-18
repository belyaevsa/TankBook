"""Boxes are true: after perspective, every non-blank box centre is lit.

Oracle: the row's own labels. A row of ``8`` glyphs (with a leading blank) is
rendered with perspective forced on and every other augmentation off, so a box
whose centre does not land on a lit segment is a genuine error in the
box-transform, not an augmentation artefact.
"""

from __future__ import annotations

import numpy as np

from pump_reader.profiles import PROFILES
from pump_reader.row import render_row

_OVERIDES = {
    "perspective": 1.0,
    "ghosting": 0.0,
    "blur": 0.0,
    "glare": 0.0,
    "canopy": 0.0,
    "noise_exposure": 0.0,
    "occlusion": 0.0,
}


def test_box_centres_land_on_lit_pixels() -> None:
    rng = np.random.default_rng(7)
    for make, profile in PROFILES.items():
        img, boxes = render_row(" 8888", profile, rng, overrides=_OVERIDES)
        arr = np.asarray(img)
        assert boxes[0].label.digit == "blank"
        for b in boxes[1:]:
            assert b.label.digit == "8"
            rgb = tuple(int(c) for c in arr[int(b.cy), int(b.cx)])
            assert profile.is_lit(rgb), f"{make}: box centre {rgb} not lit"

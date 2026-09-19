"""Coverage: a 1 000-glyph draw covers all twelve classes and all makes.

Oracle: the class list in ``glyph.py`` and the make registry in ``profiles.py``.
The draw samples classes uniformly (never stratified); at 1 000 draws the chance
of missing any of the 12 classes is negligible, so a correct renderer passes and
a renderer that only ever emits a few classes fails.
"""

from __future__ import annotations

import numpy as np

from pump_reader.glyph import CLASSES, label_class, render_glyph, sample_label
from pump_reader.profiles import PROFILES, sample_make

N = 1_000


def test_thousand_glyph_draw_covers_every_class_and_make() -> None:
    rng = np.random.default_rng(20260918)
    classes_seen: set[str] = set()
    makes_seen: set[str] = set()
    for _ in range(N):
        make = sample_make(rng)
        profile = PROFILES[make]
        label = sample_label(rng)
        render_glyph(label, profile, rng)
        classes_seen.add(label_class(label))
        makes_seen.add(make)

    assert classes_seen == set(CLASSES), f"missing classes: {set(CLASSES) - classes_seen}"
    assert makes_seen == set(PROFILES), f"missing makes: {set(PROFILES) - makes_seen}"

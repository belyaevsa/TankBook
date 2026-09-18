"""Profiles differ: each make renders a visibly different glyph.

Oracle: the profile constants. ``render_glyph("8", augment=False)`` is drawn for
every make (each with a fresh, identically-seeded rng so two clones render
identically), and every pair must differ by more than
``compute_profile_separation_floor()``, a positive per-pixel floor computed from
the colour ranges. The named mutation - making ``scheidt`` a clone of
``gilbarco`` - must send this test red: the pair's pixel diff collapses to zero.
"""

from __future__ import annotations

import numpy as np

from pump_reader.glyph import SegmentLabel, render_glyph
from pump_reader.profiles import PROFILES, compute_profile_separation_floor


def _render(name: str) -> np.ndarray:
    rng = np.random.default_rng(0)
    img = render_glyph(SegmentLabel.from_digit("8"), PROFILES[name], rng, augment=False)
    return np.asarray(img, dtype=np.float32)


def test_every_make_differs_above_the_floor() -> None:
    names = list(PROFILES)
    renders = {n: _render(n) for n in names}
    floor = compute_profile_separation_floor()

    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            a, b = names[i], names[j]
            d = float(np.abs(renders[a] - renders[b]).mean())
            print(f"  {a} vs {b}: mean|pixel| = {d:.3f}")

    assert floor > 0, f"separation floor must be positive, got {floor:.3f}"

    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            a, b = names[i], names[j]
            d = float(np.abs(renders[a] - renders[b]).mean())
            assert d > floor, f"{a} vs {b}: {d:.3f} <= floor {floor:.3f}"

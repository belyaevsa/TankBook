"""An LCD ghost lies between the ground and the ink, never beyond either.

Oracle: the resolved profile's own ``ground`` and ``on``. Sampling the ghost
from its own colour range let it land LIGHTER than the ground, which drew an
off segment as a bright outline - visible on the training sheets, and the
likeliest cause of the d/g confusions on the held-out cells.
"""

from __future__ import annotations

import numpy as np

from pump_reader.dataset import LCD_PALETTES, with_technology
from pump_reader.profiles import PROFILES


def test_lcd_ghost_between_ground_and_ink() -> None:
    rng = np.random.default_rng(7)
    bad = 0
    for _ in range(400):
        base = PROFILES[str(rng.choice(list(PROFILES)))]
        res = with_technology(base, "lcd", rng).resolve(rng)
        for c in range(3):
            lo, hi = sorted((res.ground[c], res.on[c]))
            if not lo <= res.ghost[c] <= hi:
                bad += 1
                break
    assert bad == 0, f"{bad} of 400 LCD ghosts fell outside [ground, ink]"
    assert len(LCD_PALETTES) >= 5

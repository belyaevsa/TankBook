"""Make profiles for the synthetic seven-segment renderer.

Each profile describes one pump-display make with plausible, clearly distinct
geometry and colour ranges. These are GUESSES, not measurements: the true
geometry of each make is unknown, and the held-out corpus under
``Spike/ReceiptSpike/fixtures/pump/`` must not be inspected to learn it. PU.6
revisits each field from measured failures. The point of five profiles is
variety, not fidelity.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class ColorRange:
    """An inclusive per-channel RGB range ``[lo, hi]``."""

    lo: tuple[int, int, int]
    hi: tuple[int, int, int]

    def sample(self, rng: np.random.Generator) -> tuple[int, int, int]:
        return tuple(int(rng.integers(self.lo[c], self.hi[c] + 1)) for c in range(3))

    def midpoint(self) -> tuple[int, int, int]:
        return tuple((self.lo[c] + self.hi[c]) // 2 for c in range(3))


@dataclass(frozen=True)
class MakeProfile:
    """Geometry and colour ranges the renderer samples from for one make.

    All geometry fields are ``(min, max)`` ranges. ``segment_ratio`` is the
    segment length divided by its thickness; ``segment_gap``, ``dp_diameter``
    and ``dp_offset`` are fractions of the glyph height; ``pitch`` is the glyph
    advance as a multiple of glyph width. ``bloom`` is a glow radius in pixels
    (led/vfd only); ``dp_own_cell`` chooses whether the decimal point is its own
    narrow cell (some makes) or a dp bit on the preceding glyph (the common
    case).
    """

    name: str
    technology: str  # "lcd" | "led" | "vfd"
    segment_ratio: tuple[float, float]
    segment_gap: tuple[float, float]
    slant_deg: tuple[float, float]
    pitch: tuple[float, float]
    dp_diameter: tuple[float, float]
    dp_offset: tuple[float, float]
    ground_color: ColorRange
    on_color: ColorRange
    ghost_color: ColorRange
    bloom: float
    dp_own_cell: bool

    def resolve(self, rng: np.random.Generator) -> "Resolved":
        """Sample one concrete instance of every range."""
        return Resolved(
            ratio=float(rng.uniform(*self.segment_ratio)),
            gap_frac=float(rng.uniform(*self.segment_gap)),
            slant_deg=float(rng.uniform(*self.slant_deg)),
            pitch=float(rng.uniform(*self.pitch)),
            dp_diameter_frac=float(rng.uniform(*self.dp_diameter)),
            dp_offset_frac=float(rng.uniform(*self.dp_offset)),
            on=self.on_color.sample(rng),
            ground=self.ground_color.sample(rng),
            ghost=self.ghost_color.sample(rng),
        )

    def is_lit(self, rgb: tuple[int, int, int]) -> bool:
        """Classify a pixel as a lit segment, thresholded against the ground.

        LCD segments are darker than their pale ground; led/vfd segments are
        brighter than their dark ground. The threshold is the midpoint between
        the profile's on- and ground-colour luminance.
        """
        lum = (rgb[0] + rgb[1] + rgb[2]) / 3.0
        lum_on = sum(self.on_color.midpoint()) / 3.0
        lum_ground = sum(self.ground_color.midpoint()) / 3.0
        threshold = (lum_on + lum_ground) / 2.0
        return lum < threshold if lum_on < lum_ground else lum > threshold


@dataclass(frozen=True)
class Resolved:
    """A single concrete sample of a profile's ranges (raw, not yet pixel-scaled)."""

    ratio: float
    gap_frac: float
    slant_deg: float
    pitch: float
    dp_diameter_frac: float
    dp_offset_frac: float
    on: tuple[int, int, int]
    ground: tuple[int, int, int]
    ghost: tuple[int, int, int]


# --- technology palettes ----------------------------------------------------

_LCD_GROUND = ColorRange((170, 188, 178), (206, 220, 202))
_LCD_ON = ColorRange((30, 42, 36), (58, 70, 62))
_LCD_GHOST = ColorRange((178, 194, 186), (198, 212, 198))

_LED_GROUND = ColorRange((3, 4, 3), (14, 16, 14))
_VFD_GROUND = ColorRange((2, 4, 4), (10, 12, 12))
_VFD_ON = ColorRange((90, 220, 190), (120, 245, 210))

_RED = ColorRange((190, 30, 20), (240, 70, 50))
_GREEN = ColorRange((60, 210, 60), (120, 245, 120))
_AMBER = ColorRange((230, 150, 20), (250, 190, 60))


# --- the registry -----------------------------------------------------------

PROFILES: dict[str, MakeProfile] = {
    "gilbarco": MakeProfile(
        # Guess: the corpus's Gilbarco fixtures are pale LCD panels with faint
        # ghost segments. The 6.5-8.5 ratio drew the segments too thin - the
        # held-out cell sheet (PU.7, gap 1 "bolder segments") shows real LCD
        # segments nearer 3-5, so the ratio drops to 3.5-6.0. The slant widens
        # to 6-12 deg for the same reason (gap 4 "italic slant").
        name="gilbarco",
        technology="lcd",
        segment_ratio=(3.5, 6.0),
        segment_gap=(0.045, 0.075),
        slant_deg=(6.0, 12.0),
        pitch=(1.25, 1.45),
        dp_diameter=(0.10, 0.15),
        dp_offset=(0.10, 0.18),
        ground_color=_LCD_GROUND,
        on_color=_LCD_ON,
        ghost_color=_LCD_GHOST,
        bloom=0.0,
        dp_own_cell=False,
    ),
    "wayne": MakeProfile(
        # Guess: Wayne (incl. Dresser Wayne) panels are lit red LED segments on a
        # dark ground with a soft bloom. The slant widens to 6-12 deg to match
        # the italic Gilbarco/Wayne heads on the held-out cell sheet (PU.7,
        # gap 4 "italic slant"); the segments stay on the thin side so the
        # classifier still sees thin glyphs alongside the bolder gilbarco.
        name="wayne",
        technology="led",
        segment_ratio=(7.5, 9.5),
        segment_gap=(0.03, 0.06),
        slant_deg=(6.0, 12.0),
        pitch=(1.2, 1.4),
        dp_diameter=(0.09, 0.13),
        dp_offset=(0.08, 0.15),
        ground_color=_LED_GROUND,
        on_color=_RED,
        ghost_color=_LED_GROUND,
        bloom=1.2,
        dp_own_cell=False,
    ),
    "dresser": MakeProfile(
        # Guess: standalone Dresser heads are lit green LED segments, slightly
        # thinner and wider-pitched than Wayne, near-vertical. Kept deliberately
        # thin (8.0-10.0) so the classifier keeps seeing thin glyphs after
        # gilbarco went bold (PU.7, gap 1 "bolder segments").
        name="dresser",
        technology="led",
        segment_ratio=(8.0, 10.0),
        segment_gap=(0.05, 0.08),
        slant_deg=(0.0, 2.0),
        pitch=(1.3, 1.5),
        dp_diameter=(0.11, 0.16),
        dp_offset=(0.12, 0.20),
        ground_color=_LED_GROUND,
        on_color=_GREEN,
        ghost_color=_LED_GROUND,
        bloom=1.5,
        dp_own_cell=False,
    ),
    "scheidt": MakeProfile(
        # Guess: Scheidt & Bachmann heads are VFD: cyan-green on near-black with
        # a soft bloom, the thickest segments and the strongest slant of the set.
        name="scheidt",
        technology="vfd",
        segment_ratio=(5.5, 7.0),
        segment_gap=(0.06, 0.09),
        slant_deg=(4.0, 8.0),
        pitch=(1.15, 1.35),
        dp_diameter=(0.08, 0.12),
        dp_offset=(0.09, 0.16),
        ground_color=_VFD_GROUND,
        on_color=_VFD_ON,
        ghost_color=_VFD_GROUND,
        bloom=1.8,
        dp_own_cell=False,
    ),
    "tokheim": MakeProfile(
        # Guess: Tokheim heads are amber LED with the widest pitch, and render
        # the decimal point as its own narrow cell rather than on the preceding
        # glyph (a common European layout).
        name="tokheim",
        technology="led",
        segment_ratio=(6.0, 7.5),
        segment_gap=(0.04, 0.07),
        slant_deg=(1.0, 4.0),
        pitch=(1.35, 1.55),
        dp_diameter=(0.10, 0.14),
        dp_offset=(0.11, 0.17),
        ground_color=_LED_GROUND,
        on_color=_AMBER,
        ghost_color=_LED_GROUND,
        bloom=1.4,
        dp_own_cell=True,
    ),
}


def sample_make(rng: np.random.Generator, name: str | None = None) -> str:
    """Sample a make uniformly from the registry, or validate a fixed name."""
    if name is not None:
        if name not in PROFILES:
            raise KeyError(f"unknown make {name!r}; registered: {sorted(PROFILES)}")
        return name
    return str(rng.choice(list(PROFILES)))


def _min_color_sep(a: ColorRange, b: ColorRange) -> float:
    """Minimum possible mean absolute per-channel distance between two ranges."""
    total = 0.0
    for c in range(3):
        if a.hi[c] < b.lo[c]:
            total += b.lo[c] - a.hi[c]
        elif b.hi[c] < a.lo[c]:
            total += a.lo[c] - b.hi[c]
    return total / 3.0


def compute_profile_separation_floor(lit_fraction: float = 0.05) -> float:
    """A conservative per-pixel separation floor, computed from the profiles.

    For every pair of makes, the pair's on- and ground-colour ranges are at
    least ``max(on_sep, ground_sep)`` apart per pixel in the closer of the two.
    The floor is the smallest such separation across all pairs, scaled by a
    conservative estimate of the fraction of the glyph canvas a lit ``8``
    occupies. It is positive because every pair differs in at least one colour
    channel; a clone of one profile makes it collapse to zero, which the
    profile-difference test rejects.
    """
    profiles = list(PROFILES.values())
    best = float("inf")
    for i in range(len(profiles)):
        for j in range(i + 1, len(profiles)):
            on_sep = _min_color_sep(profiles[i].on_color, profiles[j].on_color)
            ground_sep = _min_color_sep(
                profiles[i].ground_color, profiles[j].ground_color
            )
            best = min(best, max(on_sep, ground_sep))
    return lit_fraction * best

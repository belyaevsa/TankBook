"""Synthetic training data for the segment classifier (PU.3).

``SyntheticDataset`` renders glyphs on the fly from PU.1's ``render_glyph`` with
a rng seeded per index, so every sample is reproducible and the validation split
is a fixed, disjoint seed range. Each sample is a ``3x48x32`` float tensor in
``[0, 1]`` plus the 8 segment bits (a-g, dp) of its ``SegmentLabel``.

Two facts the renderer alone does not model, and which this dataset therefore
adds:

- **Technology is sampled independently of make.** PU.1 binds display technology
  to make by guess (wayne/dresser = led, scheidt = vfd, gilbarco = lcd). But
  technology is a palette, not a geometry: the digit is carried by the segment
  geometry, which the make controls. Binding the two would let the classifier
  lean on colour as a proxy for the wrong reason. Here the make supplies
  geometry and a technology palette (LCD 0.6 / LED 0.3 / VFD 0.1) supplies the
  colours, so a make appears in every technology across the draw.
- **Crop jitter.** The real slicer (PU.4) cuts cells slightly off, so a training
  glyph is shifted by up to +-20 % of the cell width and +-10 % of the height and
  scaled by 0.8-1.2. At least 70 % of the glyph is kept inside the canvas, so the
  label stays decodable.
"""

from __future__ import annotations

import dataclasses

import numpy as np
from PIL import Image

from . import augment as _augment
from .glyph import CELL_H, CELL_W, MARGIN, BLANK, DP_ONLY, SegmentLabel, render_glyph
from .profiles import PROFILES, MakeProfile
from .row import render_row_of_labels

# LCD-heavy technology prior: LCD is the common pump panel, LED and VFD the less
# common. A uniform prior would over-represent VFD far beyond its corpus share.
TECHNOLOGIES: tuple[str, ...] = ("lcd", "led", "vfd")
TECHNOLOGY_PRIORS: dict[str, float] = {"lcd": 0.6, "led": 0.3, "vfd": 0.1}

# Blank and dp-only are their own classes (the slicer feeds leading-space and
# decimal cells too); the ten digits share the remainder uniformly.
BLANK_PRIOR: float = 0.08
DP_ONLY_PRIOR: float = 0.08

_MIN_VISIBLE_FRAC: float = 0.7

# gap 2 (neighbour spill): a real slicer's cells overlap, so a cell carries the
# edge of the glyph either side, which PU.3's lone-glyph crop jitter never did.
# SPILL_PROB is the fraction of samples rendered with a random neighbour on each
# side; SPILL_OVERLAP_PX is how far each neighbour overlaps the centre cell. The
# centre glyph and the neighbour are each inset by MARGIN, so an overlap of
# MARGIN + 2 lands only a 2px sliver of the neighbour's edge in the centre cell's
# outer margin columns - the thin edge a real slice carries, not a full segment.
SPILL_PROB: float = 0.4
SPILL_OVERLAP_PX: int = MARGIN + 2
_SPILL_ADVANCE: float = CELL_W - SPILL_OVERLAP_PX

# Slicer framing (PU.9): the cell is cut the way PumpGlyphSlicer hands it over,
# not the way a lone glyph is drawn. The x crop is the target's own tight box
# (one glyph wide, CELL_W), shifted by +-8 % of the profile's advance; the y
# crop is the whole row's ink band (top of the highest lit pixel to the bottom
# of the lowest, no vertical margin), shifted by +-6 % of the band height.
SLICER_X_JITTER: float = 0.08
SLICER_Y_JITTER: float = 0.06


def _sample_technology(rng: np.random.Generator) -> str:
    return str(rng.choice(TECHNOLOGIES, p=[TECHNOLOGY_PRIORS[t] for t in TECHNOLOGIES]))


def _resolve_technology_palette(
    tech: str, rng: np.random.Generator
) -> tuple[object, object, object, float]:
    """Colour fields (ground, on, ghost) and bloom for one technology.

    The ranges are the profiles' own palette constants, borrowed so this file
    introduces no colour numbers of its own. LED on-colour is one of the three
    makes' LED colours (red / green / amber); LCD and VFD each have one.
    """
    if tech == "lcd":
        p = PROFILES["gilbarco"]
        return p.ground_color, p.on_color, p.ghost_color, 0.0
    if tech == "vfd":
        p = PROFILES["scheidt"]
        return p.ground_color, p.on_color, p.ghost_color, p.bloom
    led_ons = (
        PROFILES["wayne"].on_color,
        PROFILES["dresser"].on_color,
        PROFILES["tokheim"].on_color,
    )
    ground = PROFILES["wayne"].ground_color
    on = led_ons[int(rng.integers(0, len(led_ons)))]
    bloom = float(rng.uniform(1.2, 1.5))
    return ground, on, ground, bloom


def with_technology(profile: MakeProfile, tech: str, rng: np.random.Generator) -> MakeProfile:
    """A copy of ``profile`` whose colour fields are ``tech``'s palette.

    Geometry (segment ratio, gap, slant, pitch, dp, own-cell flag) is the make's
    and is unchanged; only the palette and the technology flag (which drives
    bloom and LCD ghosting) move. No PU.1 profile constant is edited.
    """
    ground, on, ghost, bloom = _resolve_technology_palette(tech, rng)
    return dataclasses.replace(
        profile,
        technology=tech,
        ground_color=ground,
        on_color=on,
        ghost_color=ghost,
        bloom=bloom,
    )


def _sample_dataset_label(rng: np.random.Generator) -> SegmentLabel:
    """Sample a class with the blank/dp-only floor and uniform digits over the rest."""
    r = float(rng.random())
    if r < BLANK_PRIOR:
        return BLANK
    if r < BLANK_PRIOR + DP_ONLY_PRIOR:
        return DP_ONLY
    digit = str(int(rng.integers(0, 10)))
    return SegmentLabel.from_digit(digit, dp=bool(rng.integers(0, 2)))


def _sample_neighbour_label(rng: np.random.Generator) -> SegmentLabel:
    """A random digit neighbour (never blank or dp-only, so it always has edge ink)."""
    digit = str(int(rng.integers(0, 10)))
    return SegmentLabel.from_digit(digit, dp=bool(rng.integers(0, 2)))


def _spill_crop(
    label: SegmentLabel, profile: MakeProfile, rng: np.random.Generator
) -> Image.Image:
    """Draw the target with a neighbour on each side and crop the centre cell.

    The neighbours are drawn at a tightened advance (``_SPILL_ADVANCE``) so each
    overlaps the centre cell by ``SPILL_OVERLAP_PX``; the centre cell then carries
    a neighbour's edge in its outer margin columns the way a real slice does. No
    augmentation here, so the crop is clean for measurement.
    """
    left = _sample_neighbour_label(rng)
    right = _sample_neighbour_label(rng)
    advances = [_SPILL_ADVANCE, _SPILL_ADVANCE, _SPILL_ADVANCE]
    row, boxes = render_row_of_labels(
        [left, label, right], profile, rng, augment=False, advances=advances
    )
    b = boxes[1]
    crop = row.crop((int(b.x), int(b.y), int(b.x + b.w), int(b.y + b.h)))
    return crop.resize((CELL_W, CELL_H), Image.BILINEAR)


def render_cell(
    label: SegmentLabel,
    profile: MakeProfile,
    rng: np.random.Generator,
    *,
    augment: bool = True,
    spill_prob: float | None = None,
    overrides: dict[str, float] | None = None,
) -> Image.Image:
    """Render one glyph cell, with neighbour spill (gap 2) at ``spill_prob``.

    This is the renderer ``SyntheticDataset`` drives. With probability
    ``spill_prob`` (default ``SPILL_PROB``) the target is drawn with a neighbour
    on each side so the centre cell carries their edge; otherwise the target is
    drawn alone. ``augment`` runs the full augmentation pipeline (the dataset
    path keeps it on; tests turn it off for clean measurement).
    """
    p = SPILL_PROB if spill_prob is None else spill_prob
    if rng.random() < p:
        crop = _spill_crop(label, profile, rng)
        if augment:
            arr, _ = _augment.augment(
                np.asarray(crop, dtype=np.uint8), profile, rng, ghost_mask=None,
                overrides=overrides,
            )
            return Image.fromarray(arr, "RGB")
        return crop
    return render_glyph(label, profile, rng, augment=augment, overrides=overrides)


def _row_ink_band(row: Image.Image, profile: MakeProfile) -> tuple[int, int]:
    """The whole row's lit-pixel band: top of the highest to bottom of the lowest.

    Mirrors the slicer's ``bandTop``/``bandBottom`` (the row profile thresholded
    against the panel's on/ground split), so the cell crop carries no vertical
    margin. Blank or dp-only targets still get the neighbours' band, exactly as
    the slicer cuts a blank cell at the strip's band.
    """
    arr = np.asarray(row, dtype=np.float32)
    lum = arr.mean(axis=2)
    lum_on = sum(profile.on_color.midpoint()) / 3.0
    lum_ground = sum(profile.ground_color.midpoint()) / 3.0
    threshold = (lum_on + lum_ground) / 2.0
    lit = lum < threshold if lum_on < lum_ground else lum > threshold
    rows = np.where(lit.any(axis=1))[0]
    if rows.size == 0:
        return 0, arr.shape[0] - 1
    return int(rows.min()), int(rows.max())


def render_slicer_cell(
    label: SegmentLabel,
    profile: MakeProfile,
    rng: np.random.Generator,
    *,
    augment: bool = True,
    overrides: dict[str, float] | None = None,
) -> Image.Image:
    """Render the target the way the slicer hands it over (PU.9).

    A short row of the target plus 1-2 digit neighbours on each side is drawn
    clean (no augmentation) so the band and boxes are exact. The target's cell
    is then cut tight: horizontally its own box (``CELL_W`` wide - the slicer's
    cells are tight on the pitch, not advance-wide), vertically the whole row's
    ink band (no vertical margin). Both crops jitter, then the crop is resized
    to 32x48 with the same ``BILINEAR`` resampling ``score.py`` uses. The
    neighbours contribute the band and a realistic pitch; they do not bleed into
    the tight cell. Augmentation runs on the resized cell, as it does for the
    glyph framing.
    """
    n_left = int(rng.integers(1, 3))
    n_right = int(rng.integers(1, 3))
    left = [_sample_neighbour_label(rng) for _ in range(n_left)]
    right = [_sample_neighbour_label(rng) for _ in range(n_right)]
    row, boxes = render_row_of_labels(left + [label] + right, profile, rng, augment=False)

    band_top, band_bottom = _row_ink_band(row, profile)
    band_h = band_bottom - band_top + 1
    b = boxes[n_left]
    # The left neighbour is always a digit, so its advance is one full pitch.
    pitch_px = boxes[n_left].x - boxes[n_left - 1].x
    dx = float(rng.uniform(-SLICER_X_JITTER, SLICER_X_JITTER)) * pitch_px
    dy = float(rng.uniform(-SLICER_Y_JITTER, SLICER_Y_JITTER)) * band_h
    x0 = b.x + dx
    y0 = band_top + dy
    crop = row.crop(
        (int(round(x0)), int(round(y0)), int(round(x0 + CELL_W)), int(round(y0 + band_h)))
    )
    resized = crop.resize((CELL_W, CELL_H), Image.BILINEAR)
    if augment:
        arr, _ = _augment.augment(
            np.asarray(resized, dtype=np.uint8), profile, rng, ghost_mask=None, overrides=overrides
        )
        return Image.fromarray(arr, "RGB")
    return resized


def _clamp_shift(dx: float, size: float, canvas: float, min_frac: float) -> float:
    """Clamp a paste offset so at least ``min_frac`` of the pasted image stays visible."""
    min_dx = min_frac * size - size
    max_dx = canvas - min_frac * size
    return float(min(max(dx, min_dx), max_dx))


def _jitter(img: Image.Image, rng: np.random.Generator, ground: tuple[int, int, int]) -> Image.Image:
    """Scale (0.8-1.2) and shift a glyph within its 32x48 cell, clipped to stay >= 70% visible."""
    w, h = img.size
    scale = float(rng.uniform(0.8, 1.2))
    W = max(1, int(round(w * scale)))
    H = max(1, int(round(h * scale)))
    scaled = img.resize((W, H), Image.BILINEAR)
    dx = _clamp_shift(float(rng.uniform(-0.2 * w, 0.2 * w)), W, w, _MIN_VISIBLE_FRAC)
    dy = _clamp_shift(float(rng.uniform(-0.1 * h, 0.1 * h)), H, h, _MIN_VISIBLE_FRAC)
    canvas = Image.new("RGB", (w, h), ground)
    canvas.paste(scaled, (int(round(dx)), int(round(dy))))
    return canvas


def bits_to_target(bits: int) -> np.ndarray:
    """The 8 segment bits as a float vector (bit 0 = a ... bit 6 = g, bit 7 = dp)."""
    return np.array([float((bits >> i) & 1) for i in range(8)], dtype=np.float32)


def target_to_bits(vec: np.ndarray, threshold: float = 0.5) -> int:
    bits = 0
    for i in range(8):
        if float(vec[i]) >= threshold:
            bits |= 1 << i
    return bits


class SyntheticDataset:
    """A map-style dataset of rendered glyphs, reproducible under a seed.

    ``__getitem__`` seeds a rng from ``seed + index`` and returns a
    ``(3, 48, 32)`` float tensor in ``[0, 1]`` and an ``(8,)`` float target. When
    ``cache`` is set, each sample is rendered once and stored as uint8, so epochs
    re-read rather than re-render.
    """

    def __init__(
        self,
        seed: int,
        length: int,
        *,
        cache: bool = True,
        spill_prob: float = 0.0,
        contrast_prob: float = 0.0,
        framing: str = "slicer",
    ) -> None:
        # Neighbour spill and contrast collapse are both real on the corpus and
        # both LOWER the held-out score when trained on (REPORT.md, the PU.7
        # ablation), so the shipped recipe leaves them off; the knobs stay so
        # the ablation can be re-run when the slicer or the profiles change.
        # ``framing`` picks the cell renderer: "slicer" cuts the cell as the
        # slicer hands it over (PU.9), "glyph" keeps the lone-glyph renderer
        # with its crop jitter, so the ablation can re-run the old framing.
        self.seed = seed
        self.length = length
        self.spill_prob = spill_prob
        self.framing = framing
        self.overrides = {"contrast_collapse": contrast_prob}
        self._cache: list[tuple[np.ndarray, np.ndarray] | None] = (
            [None] * length if cache else []
        )

    def __len__(self) -> int:
        return self.length

    def meta(self, index: int) -> tuple[str, str]:
        """The (make, technology) of sample ``index``, without rendering.

        Replays the same seeded rng draws ``_render`` performs first, so it
        always agrees with the sample ``__getitem__`` returns for that index.
        """
        rng = np.random.default_rng(self.seed + index)
        make = str(rng.choice(list(PROFILES)))
        tech = _sample_technology(rng)
        return make, tech

    def _render(self, index: int) -> tuple[np.ndarray, np.ndarray]:
        rng = np.random.default_rng(self.seed + index)
        make = str(rng.choice(list(PROFILES)))
        tech = _sample_technology(rng)
        label = _sample_dataset_label(rng)
        profile = with_technology(PROFILES[make], tech, rng)
        if self.framing == "slicer":
            img = render_slicer_cell(label, profile, rng, augment=True, overrides=self.overrides)
        else:
            img = render_cell(
                label, profile, rng, augment=True,
                spill_prob=self.spill_prob, overrides=self.overrides,
            )
            ground = img.getpixel((0, 0))
            img = _jitter(img, rng, ground)
        arr = np.asarray(img, dtype=np.uint8).transpose(2, 0, 1)  # CHW uint8
        return arr, bits_to_target(label.bits)

    def __getitem__(self, index: int) -> tuple[np.ndarray, np.ndarray]:
        if self._cache:
            cached = self._cache[index]
            if cached is not None:
                arr, target = cached
                return arr.astype(np.float32) / 255.0, target
            arr, target = self._render(index)
            self._cache[index] = (arr, target)
            return arr.astype(np.float32) / 255.0, target
        arr, target = self._render(index)
        return arr.astype(np.float32) / 255.0, target

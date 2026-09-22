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
  geometry and a technology palette (``TECHNOLOGY_PRIORS``) supplies the
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
from .calibration import Calibration, load_calibration
from .glyph import CELL_H, CELL_W, MARGIN, BLANK, DP_ONLY, SegmentLabel, render_glyph
from .profiles import ColorRange, PROFILES, MakeProfile
from .row import render_row_of_labels

# LCD-heavy technology prior: LCD is the common pump panel, LED and VFD the less
# common. A uniform prior would over-represent VFD far beyond its corpus share.
TECHNOLOGIES: tuple[str, ...] = ("lcd", "led", "vfd")
# The corpus is almost entirely LCD (every Gilbarco, Wayne, Dresser, Scheidt and
# Tokheim head in it); LED and VFD are kept as a minority so the reader does not
# forget them. The real pool measures ~90 % grey LCD, so LCD dominates.
TECHNOLOGY_PRIORS: dict[str, float] = {"lcd": 0.80, "led": 0.15, "vfd": 0.05}

# The real pool's ink-vs-panel luminance contrast, measured on the 40 755 real
# cells of the train split (`.out/real-r11`, the round-10 export): p10 28,
# p25 37, p50 52, p75 91, p90 121. The synthetic palettes' own ranges sit at
# 80-165, far above the corpus median, so the grey-panel palette draws its
# contrast from these quantiles instead.
REAL_CONTRAST_QUANTILES: tuple[float, ...] = (28.0, 37.0, 52.0, 91.0, 121.0)
# Share of LCD samples drawn from the grey, corpus-contrast band rather than
# the named hue families below; the corpus is mostly grey panels.
GREY_PALETTE_PROB: float = 0.75
# The fraction of real cells whose ink is darker than its panel (the slicer's
# polarity rule, measured on the same pool: 0.944).
DARK_ON_LIGHT_PROB: float = 0.94

# LCD palette families, by eye from the cell sheets (never fitted to a fixture):
# (ground, on, ghost). Grey-blue transflective (Gilbarco), dark olive with black
# ink (Wayne/Dresser), yellow-green (Scheidt/Tokheim), white-blue backlit, amber
# backlit, and the pale mint PU.1 started with.
LCD_PALETTES: tuple[tuple[ColorRange, ColorRange, ColorRange], ...] = (
    (ColorRange((165, 172, 180), (215, 222, 232)), ColorRange((40, 44, 52), (85, 90, 98)),
     ColorRange((150, 158, 168), (200, 208, 218))),
    (ColorRange((85, 92, 78), (135, 142, 125)), ColorRange((12, 14, 12), (45, 48, 42)),
     ColorRange((70, 78, 66), (120, 128, 112))),
    (ColorRange((175, 185, 120), (225, 232, 175)), ColorRange((35, 42, 30), (80, 88, 70)),
     ColorRange((160, 170, 110), (210, 218, 160))),
    (ColorRange((200, 212, 225), (240, 246, 252)), ColorRange((30, 50, 80), (80, 100, 130)),
     ColorRange((190, 202, 216), (232, 238, 246))),
    (ColorRange((215, 170, 70), (245, 205, 120)), ColorRange((45, 30, 15), (95, 70, 40)),
     ColorRange((205, 160, 65), (238, 198, 112))),
    (ColorRange((170, 188, 178), (206, 220, 202)), ColorRange((30, 42, 36), (58, 70, 62)),
     ColorRange((178, 194, 186), (198, 212, 198))),
)

# Blank and dp-only are their own classes (the slicer feeds leading-space and
# decimal cells too); the ten digits share the remainder uniformly.
BLANK_PRIOR: float = 0.08
DP_ONLY_PRIOR: float = 0.08


def grey_lcd_palette(
    rng: np.random.Generator,
) -> tuple[ColorRange, ColorRange, ColorRange]:
    """A grey LCD panel whose ink-vs-panel contrast is drawn from the real pool.

    Panel luminance is grey (70-215) with a small per-channel tint; the contrast
    is one of ``REAL_CONTRAST_QUANTILES`` and the polarity is dark-on-light on
    ~94 % of samples, the corpus's own split. The returned ranges are narrow
    (a +-6 band) so the resolved colours sit on the sampled pair. The ghost is
    the third element but LCD ``resolve`` derives it from ground and on.
    """
    panel = float(rng.uniform(70.0, 215.0))
    contrast = float(REAL_CONTRAST_QUANTILES[int(rng.integers(0, len(REAL_CONTRAST_QUANTILES)))])
    on_level = panel - contrast if rng.random() < DARK_ON_LIGHT_PROB else panel + contrast
    tint = rng.integers(-10, 11, size=3)

    def band(level: float) -> ColorRange:
        lo = tuple(int(v) for v in np.clip(level + tint - 6, 0, 255))
        hi = tuple(int(v) for v in np.clip(level + tint + 6, 0, 255))
        return ColorRange(lo, hi)

    ground = band(panel)
    on = band(on_level)
    return ground, on, ground


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
SLICER_X_JITTER: float = 0.03
SLICER_Y_JITTER: float = 0.03


def _sample_technology(rng: np.random.Generator, priors: dict[str, float] | None = None) -> str:
    p = priors or TECHNOLOGY_PRIORS
    return str(rng.choice(TECHNOLOGIES, p=[p[t] for t in TECHNOLOGIES]))


def _resolve_technology_palette(
    tech: str, rng: np.random.Generator
) -> tuple[object, object, object, float]:
    """Colour fields (ground, on, ghost) and bloom for one technology.

    The ranges are the profiles' own palette constants, borrowed so this file
    introduces no colour numbers of its own. LED on-colour is one of the three
    makes' LED colours (red / green / amber); LCD and VFD each have one.
    """
    if tech == "lcd":
        if rng.random() < GREY_PALETTE_PROB:
            ground, on, ghost = grey_lcd_palette(rng)
            return ground, on, ghost, 0.0
        ground, on, ghost = LCD_PALETTES[int(rng.integers(0, len(LCD_PALETTES)))]
        return ground, on, ghost, 0.0
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
    return SegmentLabel.from_digit(digit, dp=_sample_dp(rng))


def _sample_dp(rng: np.random.Generator) -> bool:
    """Whether a digit carries a decimal point, at the calibrated corpus rate.

    The corpus puts a decimal mark on ~21% of digit cells (``calibration.json``
    ``dp_rate.all``), not the uniform 50% the renderer used to draw - which
    double-counted added-dp reads (PU.12 finding 4).
    """
    return bool(rng.random() < load_calibration().dp_rate())


def _sample_neighbour_label(rng: np.random.Generator) -> SegmentLabel:
    """A random digit neighbour (never blank or dp-only, so it always has edge ink)."""
    digit = str(int(rng.integers(0, 10)))
    return SegmentLabel.from_digit(digit, dp=_sample_dp(rng))


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


def _region_ink_columns(
    row: Image.Image, profile: MakeProfile, x0: int, x1: int, y0: int, y1: int
) -> tuple[int | None, int | None]:
    """Leftmost/rightmost lit column inside a region, or ``(None, None)`` if empty."""
    arr = np.asarray(row, dtype=np.float32)
    lum = arr.mean(axis=2)
    lum_on = sum(profile.on_color.midpoint()) / 3.0
    lum_ground = sum(profile.ground_color.midpoint()) / 3.0
    threshold = (lum_on + lum_ground) / 2.0
    lit = lum < threshold if lum_on < lum_ground else lum > threshold
    cols = np.where(lit[y0:y1, x0:x1].any(axis=0))[0]
    if cols.size == 0:
        return None, None
    return int(x0 + cols.min()), int(x0 + cols.max())


def render_slicer_cell(
    label: SegmentLabel,
    profile: MakeProfile,
    rng: np.random.Generator,
    *,
    augment: bool = True,
    overrides: dict[str, float] | None = None,
    calibration: Calibration | None = None,
    record: dict | None = None,
) -> Image.Image:
    """Render the target the way the slicer hands it over (PU.9, calibrated PU.18).

    A short row of the target plus 1-2 digit neighbours on each side is drawn
    clean on the 96px strip, so the band and boxes are exact. The target's cell
    is then cut the slicer's way: horizontally one pitch wide with the glyph
    right-aligned (the slicer anchors cells on run ends, so the ink's right edge
    is the cell's right edge and the slack is on the left), vertically the whole
    row's ink band inflated to a cell aspect sampled from the corpus's calibrated
    quantiles (``calibration.json``). The crop is resized to 32x48 with the same
    ``BILINEAR`` resampling ``score.py`` uses at its 96px strip. The neighbours
    contribute the band and a realistic pitch; their commas (drawn below the
    baseline) bleed their tails into the target's left edge with dp = 0 on the
    target. Augmentation runs on the resized cell.
    """
    cal = calibration if calibration is not None else load_calibration()
    strip_h = cal.strip_height
    n_left = int(rng.integers(1, 3))
    n_right = int(rng.integers(1, 3))
    left = [_sample_neighbour_label(rng) for _ in range(n_left)]
    right = [_sample_neighbour_label(rng) for _ in range(n_right)]
    row, boxes = render_row_of_labels(
        left + [label] + right, profile, rng, augment=False, strip_h=strip_h, comma=True
    )

    band_top, band_bottom = _row_ink_band(row, profile)
    tight_h = band_bottom - band_top + 1
    b = boxes[n_left]
    # The left neighbour is always a digit, so its advance is one full pitch.
    pitch_px = boxes[n_left].x - boxes[n_left - 1].x
    slack = max(0.0, pitch_px - CELL_W)
    # Cell aspect (pitch / band) is sampled from the calibrated quantiles; the
    # band grows (never shrinks below the ink) to reach it, capped at the strip.
    aspect = cal.sample_aspect(rng)
    band_h = int(round(min(float(strip_h), max(float(tight_h), pitch_px / aspect))))
    # Horizontal phase: the slicer anchors cells on run ENDS, so the ink's right
    # edge is the cell's right edge and all pitch slack sits on the left
    # (calibration.json phase.right_margin_frac == 0). Right-aligning to the
    # segment ink - not the glyph box - also keeps a slanted glyph's leaned-over
    # top segments inside the crop instead of clipping them at the box edge.
    glyph_y = (strip_h - CELL_H) // 2
    baseline = glyph_y + CELL_H - MARGIN
    # The segment ink right edge across the full pitch slot (a slanted glyph
    # leans past its own box into the gap), above the baseline so the comma tail
    # - which belongs to the next cell - is not counted.
    _, ink_right = _region_ink_columns(
        row, profile, int(round(b.x)), int(round(b.x + pitch_px)), int(band_top), int(baseline)
    )
    if ink_right is None:
        ink_right = int(round(b.x + CELL_W - MARGIN))
    # A 2px right margin leaves room for the +-phase jitter, so the leaned-over
    # segment ink is never clipped at the cell's right edge.
    lead = max(0.0, (b.x + pitch_px) - (ink_right + 2.0))
    dx = float(rng.uniform(-SLICER_X_JITTER, SLICER_X_JITTER)) * pitch_px
    dy = float(rng.uniform(-SLICER_Y_JITTER, SLICER_Y_JITTER)) * band_h
    # The band slack above the ink is one-sided (a threshold band grows above OR
    # below, not both) - a comma extends below, a second row or loose quad above.
    extra = band_h - tight_h
    above = extra if rng.random() < 0.5 else 0
    x0 = b.x - lead + dx
    y0 = band_top - above + dy
    x0 = max(0.0, min(x0, float(row.width - pitch_px)))
    # Keep the tight ink band inside the crop despite the phase jitter: the
    # band is at least the ink, so the glyph must never be clipped vertically.
    y0 = max(float(band_top - extra), min(float(band_top), y0))
    if record is not None:
        record["pitch_px"] = pitch_px
        record["band_h"] = band_h
        record["aspect"] = pitch_px / band_h
    crop = row.crop(
        (int(round(x0)), int(round(y0)), int(round(x0 + pitch_px)), int(round(y0 + band_h)))
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
        technology_priors: dict[str, float] | None = None,
        dp_bits: bool = True,
    ) -> None:
        # Both knobs were ablated against the held-out corpus (REPORT.md): with
        # cells framed like the slicer's, contrast collapse HELPS and is on in
        # `train.py`'s defaults; neighbour spill still hurts and stays off.
        # ``framing`` picks the cell renderer: "slicer" cuts the cell as the
        # slicer hands it over (PU.9), "glyph" keeps the lone-glyph renderer
        # with its crop jitter, so the ablation can re-run the old framing.
        # ``technology_priors`` overrides the LCD-heavy prior for the ablation
        # control, which reproduces the round-10 (lcd 0.85) profile.
        self.seed = seed
        self.length = length
        self.spill_prob = spill_prob
        self.framing = framing
        self.priors = technology_priors
        self.dp_bits = dp_bits
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
        tech = _sample_technology(rng, self.priors)
        return make, tech

    def _render(self, index: int) -> tuple[np.ndarray, np.ndarray]:
        rng = np.random.default_rng(self.seed + index)
        make = str(rng.choice(list(PROFILES)))
        tech = _sample_technology(rng, self.priors)
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
        target = bits_to_target(label.bits)
        if not self.dp_bits:
            target[7] = 0.0
        return arr, target

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

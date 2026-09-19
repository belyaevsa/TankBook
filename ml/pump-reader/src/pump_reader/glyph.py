"""The seven-segment glyph model and single-glyph renderer.

A glyph is an 8-bit ``SegmentLabel``: bit 0 = a ... bit 6 = g (``SEGMENTS``
order), bit 7 = decimal point. The digit is a lookup over the a-g pattern, never
a stored class, so a ``9`` whose segment ``e`` is uncertain is a ``4`` candidate
with a known posterior rather than a confident wrong digit.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from . import augment as _augment
from .profiles import PROFILES, MakeProfile, Resolved

CELL_W: int = 32
CELL_H: int = 48
MARGIN: int = 4
_SPAN: int = CELL_W - 2 * MARGIN

SEGMENTS: str = "abcdefg"

DIGIT_SEGMENTS: dict[str, str] = {
    "0": "abcdef",
    "1": "bc",
    "2": "abged",
    "3": "abgcd",
    "4": "fgbc",
    "5": "afgcd",
    "6": "afgedc",
    "7": "abc",
    "8": "abcdefg",
    "9": "abcdfg",
}

# The twelve classes the renderer draws: ten digits plus blank and dp-only.
CLASSES: list[str] = [str(i) for i in range(10)] + ["blank", "dp-only"]


@dataclass(frozen=True)
class SegmentLabel:
    """An 8-bit segment mask: bit 0 = a ... bit 6 = g, bit 7 = decimal point."""

    bits: int

    def __post_init__(self) -> None:
        if not 0 <= self.bits <= 255:
            raise ValueError(f"SegmentLabel bits out of range: {self.bits}")

    @property
    def dp(self) -> bool:
        return bool(self.bits & 0x80)

    @property
    def segments(self) -> str:
        """The a-g segments that are on, in ``SEGMENTS`` order (dp excluded)."""
        return "".join(ch for i, ch in enumerate(SEGMENTS) if self.bits & (1 << i))

    @property
    def digit(self) -> str | None:
        """Decode to ``"0"``-``"9"``, ``"blank"``, or ``None`` for a non-digit pattern."""
        if self.bits == 0:
            return "blank"
        on = frozenset(self.segments)
        for digit, segs in DIGIT_SEGMENTS.items():
            if on == frozenset(segs):
                return digit
        return None

    @staticmethod
    def from_digit(digit: str, dp: bool = False) -> "SegmentLabel":
        if digit not in DIGIT_SEGMENTS:
            raise ValueError(f"not a digit: {digit!r}")
        bits = 0
        for ch in DIGIT_SEGMENTS[digit]:
            bits |= 1 << SEGMENTS.index(ch)
        if dp:
            bits |= 0x80
        return SegmentLabel(bits)


BLANK: SegmentLabel = SegmentLabel(0)
DP_ONLY: SegmentLabel = SegmentLabel(0x80)


def label_class(label: SegmentLabel) -> str:
    """Map a label to its class name in ``CLASSES``."""
    if label.bits == 0:
        return "blank"
    if label.bits == 0x80:
        return "dp-only"
    digit = label.digit
    assert digit is not None and digit != "blank", f"unclassifiable label {label.bits}"
    return digit


def sample_label(rng: np.random.Generator) -> SegmentLabel:
    """Sample one of the twelve classes uniformly (never stratified)."""
    k = int(rng.integers(0, len(CLASSES)))
    if k < 10:
        return SegmentLabel.from_digit(str(k), dp=bool(rng.integers(0, 2)))
    if k == 10:
        return BLANK
    return DP_ONLY


# --- geometry ---------------------------------------------------------------


def _thickness(res: Resolved) -> float:
    return _SPAN / res.ratio


def _gap(res: Resolved) -> float:
    return res.gap_frac * CELL_H


def _slant_px(res: Resolved) -> float:
    return float(np.tan(np.deg2rad(res.slant_deg)) * CELL_H)


def _dp_diameter(res: Resolved) -> float:
    return res.dp_diameter_frac * CELL_H


def _hseg(cx: float, cy: float, length: float, t: float) -> list[tuple[float, float]]:
    x0 = cx - length / 2
    x1 = cx + length / 2
    return [
        (x0 + t / 2, cy - t / 2),
        (x1 - t / 2, cy - t / 2),
        (x1, cy),
        (x1 - t / 2, cy + t / 2),
        (x0 + t / 2, cy + t / 2),
        (x0, cy),
    ]


def _vseg(cx: float, cy: float, length: float, t: float) -> list[tuple[float, float]]:
    y0 = cy - length / 2
    y1 = cy + length / 2
    return [
        (cx, y0),
        (cx + t / 2, y0 + t / 2),
        (cx + t / 2, y1 - t / 2),
        (cx, y1),
        (cx - t / 2, y1 - t / 2),
        (cx - t / 2, y0 + t / 2),
    ]


def segment_polygons(res: Resolved) -> dict[str, list[tuple[float, float]]]:
    """Pixel-space polygons for segments a-g, in glyph-local coordinates."""
    t = _thickness(res)
    g = _gap(res)
    m = MARGIN
    cx = CELL_W / 2
    length = _SPAN
    top = m + t / 2
    mid = CELL_H / 2
    bot = CELL_H - m - t / 2
    cxl = m + t / 2
    cxr = CELL_W - m - t / 2
    y_t0 = m + t
    y_t1 = mid - g / 2
    y_b0 = mid + g / 2
    y_b1 = CELL_H - m - t
    return {
        "a": _hseg(cx, top, length, t),
        "g": _hseg(cx, mid, length, t),
        "d": _hseg(cx, bot, length, t),
        "f": _vseg(cxl, (y_t0 + y_t1) / 2, y_t1 - y_t0, t),
        "b": _vseg(cxr, (y_t0 + y_t1) / 2, y_t1 - y_t0, t),
        "e": _vseg(cxl, (y_b0 + y_b1) / 2, y_b1 - y_b0, t),
        "c": _vseg(cxr, (y_b0 + y_b1) / 2, y_b1 - y_b0, t),
    }


def _shear(
    pts: list[tuple[float, float]], slant_px: float, x0: float, y0: float
) -> list[tuple[float, float]]:
    """Horizontal shear: the top of a glyph shifts by ``slant_px``, the bottom stays."""
    return [
        (x0 + x + slant_px * (CELL_H - (y - y0)) / CELL_H, y0 + y) for x, y in pts
    ]


def _draw_glyph(
    rgb: Image.Image,
    on_mask: Image.Image,
    ghost_mask: Image.Image,
    label: SegmentLabel,
    profile: MakeProfile,
    res: Resolved,
    x0: float,
    y0: float,
    comma: bool = False,
) -> None:
    """Draw one glyph's segments into the canvases at ``(x0, y0)``."""
    draw = ImageDraw.Draw(rgb)
    on_draw = ImageDraw.Draw(on_mask)
    ghost_draw = ImageDraw.Draw(ghost_mask)
    polys = segment_polygons(res)
    slant = _slant_px(res)
    on_set = set(label.segments)
    for seg, pts in polys.items():
        sheared = _shear(pts, slant, x0, y0)
        if seg in on_set:
            draw.polygon(sheared, fill=res.on)
            on_draw.polygon(sheared, fill=255)
        elif profile.technology == "lcd":
            # faint ghost segment for the off state (lcd only)
            draw.polygon(sheared, fill=res.ghost)
            ghost_draw.polygon(sheared, fill=255)
    if label.dp:
        _draw_dp(draw, on_draw, res, x0, y0, comma=comma)


def _draw_dp(
    draw: ImageDraw.ImageDraw,
    on_draw: ImageDraw.ImageDraw,
    res: Resolved,
    x0: float,
    y0: float,
    comma: bool = False,
) -> None:
    """Draw the decimal mark.

    ``comma=False`` is the plain dot in the glyph box's bottom-right corner
    (LED heads). ``comma=True`` draws the corpus's comma: a dot below the digit
    baseline in the gap after the glyph, with a short tail whose rightmost ink
    crosses into the next cell's left edge. The dp bit stays on the host glyph
    (``label.dp``), so a cell cut from the NEXT position carries the tail at its
    left edge with dp = 0.
    """
    d = _dp_diameter(res)
    if not comma:
        cx = x0 + CELL_W - d - 1
        cy = y0 + CELL_H - d - 1
        box = [cx, cy, cx + d, cy + d]
        draw.ellipse(box, fill=res.on)
        on_draw.ellipse(box, fill=255)
        return
    baseline = y0 + CELL_H - MARGIN
    next_x = x0 + res.pitch * CELL_W
    cx = x0 + CELL_W + res.dp_offset_frac * CELL_H
    cy = baseline + res.dp_vertical_frac * CELL_H + d / 2.0
    dot = [cx - d / 2.0, cy - d / 2.0, cx + d / 2.0, cy + d / 2.0]
    draw.ellipse(dot, fill=res.on)
    on_draw.ellipse(dot, fill=255)
    overhang = 2.0
    tail_end_x = max(cx + d, next_x + overhang)
    tail_drop = d * 0.8
    tail = [
        (cx + d / 2.0, cy - d * 0.25),
        (tail_end_x, cy + tail_drop),
        (cx + d / 2.0, cy + d * 0.25),
    ]
    draw.polygon(tail, fill=res.on)
    on_draw.polygon(tail, fill=255)


def _apply_bloom(rgb: Image.Image, on_mask: Image.Image, profile: MakeProfile, res: Resolved) -> Image.Image:
    if profile.technology not in ("led", "vfd") or profile.bloom <= 0:
        return rgb
    blurred = on_mask.filter(ImageFilter.GaussianBlur(profile.bloom))
    b = np.asarray(blurred, dtype=np.float32)[..., None] / 255.0
    arr = np.asarray(rgb, dtype=np.float32)
    on = np.asarray(res.on, dtype=np.float32)
    arr = arr + b * (on - arr) * 0.6
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")


def render_glyph(
    label: SegmentLabel,
    profile: MakeProfile,
    rng: np.random.Generator,
    *,
    augment: bool = True,
    overrides: dict[str, float] | None = None,
) -> Image.Image:
    """Render a single labelled glyph crop into a 32x48 RGB canvas."""
    res = profile.resolve(rng)
    rgb = Image.new("RGB", (CELL_W, CELL_H), res.ground)
    on_mask = Image.new("L", (CELL_W, CELL_H), 0)
    ghost_mask = Image.new("L", (CELL_W, CELL_H), 0)
    _draw_glyph(rgb, on_mask, ghost_mask, label, profile, res, 0.0, 0.0)
    rgb = _apply_bloom(rgb, on_mask, profile, res)
    if augment:
        arr, _ = _augment.augment(
            np.asarray(rgb), profile, rng, overrides=overrides,
            ghost_mask=np.asarray(ghost_mask, dtype=np.float32) / 255.0,
        )
        rgb = Image.fromarray(arr, "RGB")
    return rgb


def render_glyph_mask(
    label: SegmentLabel, profile: MakeProfile, rng: np.random.Generator
) -> Image.Image:
    """The lit-segment mask of a glyph, before colour, bloom or augmentation.

    Geometry only: two profiles that differ solely in colour produce identical
    masks, which is what lets a test separate shape variety from palette variety.
    """
    res = profile.resolve(rng)
    rgb = Image.new("RGB", (CELL_W, CELL_H), res.ground)
    on_mask = Image.new("L", (CELL_W, CELL_H), 0)
    ghost_mask = Image.new("L", (CELL_W, CELL_H), 0)
    _draw_glyph(rgb, on_mask, ghost_mask, label, profile, res, 0.0, 0.0)
    return on_mask


VALID_PATTERNS: tuple[int, ...] = tuple(
    [SegmentLabel.from_digit(d).bits for d in DIGIT_SEGMENTS] + [BLANK.bits]
)
"""The seven-segment patterns a display can show (ten digits and blank), a-g only."""


def decode_constrained(probs, *, allow_blank: bool = True) -> tuple[int, float]:
    """Decode 8 segment probabilities to the most likely VALID glyph.

    A per-bit threshold can emit a pattern no display shows; the digit is a
    lookup over valid patterns ranked by likelihood, so the decoder searches
    only those. Returns ``(bits, margin)`` where ``bits`` carries the chosen
    a-g pattern plus the dp bit thresholded on its own, and ``margin`` is the
    log-likelihood gap to the runner-up (an abstention signal for callers).
    """
    import math

    p = [min(max(float(v), 1e-6), 1 - 1e-6) for v in probs[:7]]
    scores = []
    for pat in VALID_PATTERNS:
        if pat == 0 and not allow_blank:
            continue
        ll = 0.0
        for i in range(7):
            ll += math.log(p[i]) if (pat >> i) & 1 else math.log(1 - p[i])
        scores.append((ll, pat))
    scores.sort(reverse=True)
    best, second = scores[0], scores[1]
    bits = best[1] | (0x80 if float(probs[7]) >= 0.5 else 0)
    return bits, best[0] - second[0]

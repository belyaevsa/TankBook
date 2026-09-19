"""Number-row rendering: a sequence of glyphs on the profile's pitch.

``render_row`` draws a whole number such as ``"12.38"`` or ``" 40.00"``, returns
the row image and one axis-aligned box per glyph, and applies perspective to the
whole row (transforming the boxes with the same homography) so the boxes are
true in the final image. Leading blanks are rendered as blank glyphs and
labelled as such; zero-padding is a sampled variant of the random row text.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageDraw

from . import augment as _augment
from .glyph import CELL_H, CELL_W, DP_ONLY, SegmentLabel, _draw_glyph, _apply_bloom
from .profiles import MakeProfile

_ROW_MARGIN_X: int = 10
_ROW_MARGIN_Y: int = 8


@dataclass
class GlyphBox:
    label: SegmentLabel
    x: float
    y: float
    w: float
    h: float

    @property
    def cx(self) -> float:
        return self.x + self.w / 2

    @property
    def cy(self) -> float:
        return self.y + self.h / 2


def parse_row(text: str, dp_own_cell: bool) -> list[SegmentLabel]:
    """Split a number string into glyph cells.

    Each digit becomes a cell; a ``"."`` sets the dp bit on the preceding digit
    (the common case) or, when ``dp_own_cell``, becomes its own dp-only cell;
    a space becomes a blank cell. Any other character is ignored.
    """
    labels: list[SegmentLabel] = []
    chars = list(text)
    i = 0
    while i < len(chars):
        ch = chars[i]
        if ch in "0123456789":
            dp = (
                not dp_own_cell
                and i + 1 < len(chars)
                and chars[i + 1] == "."
            )
            labels.append(SegmentLabel.from_digit(ch, dp=dp))
        elif ch == ".":
            if dp_own_cell:
                labels.append(DP_ONLY)
        elif ch == " ":
            labels.append(SegmentLabel(0))
        i += 1
    return labels


def sample_row_text(rng: np.random.Generator) -> str:
    """A random number string: integer + fraction, optional zero-pad and leading blanks."""
    n_int = int(rng.integers(1, 4))
    n_frac = int(rng.integers(1, 3))
    int_digits = [str(rng.integers(0, 10)) for _ in range(n_int)]
    frac_digits = [str(rng.integers(0, 10)) for _ in range(n_frac)]
    if rng.random() < 0.3:
        int_digits = ["0"] * int(rng.integers(0, 3)) + int_digits
    text = "".join(int_digits) + "." + "".join(frac_digits)
    if rng.random() < 0.25:
        text = " " * int(rng.integers(1, 3)) + text
    return text


def _cell_advance(is_dp: bool, pitch: float) -> float:
    return pitch * CELL_W * (0.5 if is_dp else 1.0)


def render_row(
    text: str,
    profile: MakeProfile,
    rng: np.random.Generator,
    *,
    augment: bool = True,
    overrides: dict[str, float] | None = None,
) -> tuple[Image.Image, list[GlyphBox]]:
    """Render ``text`` as a number row; returns (image, boxes) with true boxes."""
    cells = parse_row(text, profile.dp_own_cell)
    return render_row_of_labels(cells, profile, rng, augment=augment, overrides=overrides)


def render_row_of_labels(
    cells: list[SegmentLabel],
    profile: MakeProfile,
    rng: np.random.Generator,
    *,
    augment: bool = True,
    overrides: dict[str, float] | None = None,
    advances: list[float] | None = None,
) -> tuple[Image.Image, list[GlyphBox]]:
    """Render a list of glyph cells as one row; returns (image, true boxes).

    ``advances``, when given, overrides the per-cell advance (normally the
    profile's pitch). The spill renderer passes a tightened advance so each
    neighbour overlaps the centre cell and its edge bleeds into the centre box -
    the way a real slicer's overlapping cells carry the neighbour's edge (PU.7,
    gap 2 "neighbour spill").
    """
    res = profile.resolve(rng)
    if advances is None:
        advances = [_cell_advance(lbl.bits == 0x80, res.pitch) for lbl in cells]
    total_w = int(sum(advances) + 2 * _ROW_MARGIN_X)
    total_h = CELL_H + 2 * _ROW_MARGIN_Y

    rgb = Image.new("RGB", (total_w, total_h), res.ground)
    on_mask = Image.new("L", (total_w, total_h), 0)
    ghost_mask = Image.new("L", (total_w, total_h), 0)

    x = float(_ROW_MARGIN_X)
    boxes: list[GlyphBox] = []
    for lbl, adv in zip(cells, advances):
        if lbl.bits == 0x80:
            _draw_glyph(rgb, on_mask, ghost_mask, lbl, profile, res, x, float(_ROW_MARGIN_Y))
            boxes.append(GlyphBox(lbl, x, float(_ROW_MARGIN_Y), adv, float(CELL_H)))
        else:
            _draw_glyph(rgb, on_mask, ghost_mask, lbl, profile, res, x, float(_ROW_MARGIN_Y))
            boxes.append(GlyphBox(lbl, x, float(_ROW_MARGIN_Y), float(CELL_W), float(CELL_H)))
        x += adv

    rgb = _apply_bloom(rgb, on_mask, profile, res)

    if augment:
        arr, hmat = _augment.augment(
            np.asarray(rgb),
            profile,
            rng,
            overrides=overrides,
            ghost_mask=np.asarray(ghost_mask, dtype=np.float32) / 255.0,
        )
        rgb = Image.fromarray(arr, "RGB")
        if hmat is not None:
            boxes = _transform_boxes(boxes, hmat)

    return rgb, boxes


def _transform_boxes(boxes: list[GlyphBox], hmat: np.ndarray) -> list[GlyphBox]:
    """Map each box's corners through ``hmat`` and take the axis-aligned bounds."""
    out: list[GlyphBox] = []
    for b in boxes:
        corners = np.array(
            [
                [b.x, b.y, 1.0],
                [b.x + b.w, b.y, 1.0],
                [b.x + b.w, b.y + b.h, 1.0],
                [b.x, b.y + b.h, 1.0],
            ]
        )
        mapped = corners @ hmat.T
        xs = mapped[:, 0] / mapped[:, 2]
        ys = mapped[:, 1] / mapped[:, 2]
        out.append(
            GlyphBox(
                label=b.label,
                x=float(xs.min()),
                y=float(ys.min()),
                w=float(xs.max() - xs.min()),
                h=float(ys.max() - ys.min()),
            )
        )
    return out

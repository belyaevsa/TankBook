"""Dataset spill: with the spill probability on, ~SPILL_PROB of samples carry a
neighbour's edge in the outer margin columns, and the centre glyph's label is the
row's own centre box label - the neighbours never change it.

Oracle: ``SPILL_PROB`` (the configured spill probability) and
``render_row_of_labels``' centre box. A single glyph keeps its ink inside its
``MARGIN`` inset, and the italic slant shears a glyph *right*, so the left margin
columns ``[0, MARGIN)`` stay empty of the centre's own ink - ink there can only
be a neighbour's. The named mutation - setting ``SPILL_PROB`` to 0 - makes the
observed fraction 0 and the test red.
"""

from __future__ import annotations

import numpy as np

from pump_reader.dataset import SPILL_PROB, _SPILL_ADVANCE, render_cell
from pump_reader.glyph import MARGIN, SegmentLabel
from pump_reader.profiles import PROFILES
from pump_reader.row import render_row_of_labels

_INK_THRESHOLD = 30.0
N = 500


def _left_margin_ink(arr: np.ndarray) -> bool:
    """True if the left MARGIN columns deviate from the corner ground.

    The left margin is checked, not the right: the slant shears a glyph right, so
    the right margin carries the centre's own leaned segments and would read as
    ink even without a neighbour.
    """
    ground = arr[0, 0].astype(np.float32)
    diff = np.abs(arr.astype(np.float32) - ground).max(axis=2)
    return float(diff[:, :MARGIN].max()) > _INK_THRESHOLD


def test_spill_probability_puts_neighbour_ink_in_the_margin() -> None:
    assert SPILL_PROB >= 0.3, f"spill probability too low to land >= 30%: {SPILL_PROB}"
    rng = np.random.default_rng(20260919)
    profile = PROFILES["gilbarco"]
    label = SegmentLabel.from_digit("8")
    hits = 0
    for _ in range(N):
        img = render_cell(label, profile, rng, augment=False)
        if _left_margin_ink(np.asarray(img)):
            hits += 1
    assert hits / N >= 0.30, f"neighbour spill seen in {hits}/{N} = {hits / N:.3f} < 0.30"


def test_centre_label_is_unchanged_by_neighbours() -> None:
    rng = np.random.default_rng(1)
    profile = PROFILES["wayne"]
    centre = SegmentLabel.from_digit("8")
    left = SegmentLabel.from_digit("3")
    right = SegmentLabel.from_digit("1")
    advances = [_SPILL_ADVANCE] * 3
    _, boxes = render_row_of_labels(
        [left, centre, right], profile, rng, augment=False, advances=advances
    )
    assert boxes[0].label == left
    assert boxes[1].label == centre
    assert boxes[2].label == right

"""Row labels: a rendered row's boxes spell the input string.

Oracle: the input string. ``render_row("12.38")`` must yield boxes whose digits
read ``1,2,3,8`` with the dp bit on the ``2`` (the common case), or an extra
dp-only cell when the profile flags its own dp cell.
"""

from __future__ import annotations

import numpy as np

from pump_reader.glyph import SegmentLabel
from pump_reader.profiles import PROFILES
from pump_reader.row import render_row


def test_row_boxes_match_the_input_string() -> None:
    rng = np.random.default_rng(0)

    # Common case: dp bit on the preceding glyph.
    _, boxes = render_row("12.38", PROFILES["wayne"], rng, augment=False)
    assert [b.label.digit for b in boxes] == ["1", "2", "3", "8"]
    assert boxes[1].label.dp is True
    assert all(not b.label.dp for i, b in enumerate(boxes) if i != 1)

    # dp-own-cell case: a separate dp-only cell, no dp bit on the "2".
    _, boxes = render_row("12.38", PROFILES["tokheim"], rng, augment=False)
    assert [b.label.bits for b in boxes] == [
        SegmentLabel.from_digit("1").bits,
        SegmentLabel.from_digit("2").bits,
        0x80,
        SegmentLabel.from_digit("3").bits,
        SegmentLabel.from_digit("8").bits,
    ]
    assert boxes[2].label.digit is None
    assert boxes[2].label.dp is True


def test_leading_blank_is_labelled_blank() -> None:
    rng = np.random.default_rng(0)
    _, boxes = render_row(" 40.00", PROFILES["gilbarco"], rng, augment=False)
    assert boxes[0].label.digit == "blank"
    assert [b.label.digit for b in boxes[1:]] == ["4", "0", "0", "0"]
    assert boxes[2].label.dp is True

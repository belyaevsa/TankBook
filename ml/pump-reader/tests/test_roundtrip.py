"""Round trip: a label decodes back to the digit it was rendered from.

Oracle: ``DIGIT_SEGMENTS`` in ``glyph.py``. For every digit,
``SegmentLabel.from_digit(d).digit == d`` (with and without the dp bit); for
every sampled non-digit pattern, ``.digit`` is ``None`` (or ``"blank"`` for the
all-off label).
"""

from __future__ import annotations

import numpy as np

from pump_reader.glyph import DIGIT_SEGMENTS, SEGMENTS, SegmentLabel


def _expected_digit(bits: int) -> str | None:
    if bits == 0:
        return "blank"
    segs = frozenset(ch for i, ch in enumerate(SEGMENTS) if bits & (1 << i))
    for d, s in DIGIT_SEGMENTS.items():
        if segs == frozenset(s):
            return d
    return None


def test_from_digit_round_trips() -> None:
    for d in "0123456789":
        assert SegmentLabel.from_digit(d).digit == d
        assert SegmentLabel.from_digit(d, dp=True).digit == d
        assert SegmentLabel.from_digit(d, dp=True).dp is True


def test_non_digit_patterns_decode_to_none() -> None:
    rng = np.random.default_rng(0)
    for _ in range(2_000):
        bits = int(rng.integers(0, 256))
        label = SegmentLabel(bits)
        assert label.digit == _expected_digit(bits), f"bits={bits}"

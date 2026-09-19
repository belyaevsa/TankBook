"""The decoder never emits a pattern no display can show.

Oracle: ``VALID_PATTERNS`` (the ten digits and blank). A per-bit threshold
turns a 7-bit vector into one of 128 patterns, 117 of which are no glyph; on
real cells a quarter of all reads were such patterns. The constrained decode
picks the most likely valid one, and its margin ranks the runner-up.
"""

from __future__ import annotations

import numpy as np

from pump_reader.dataset import target_to_bits
from pump_reader.glyph import VALID_PATTERNS, SegmentLabel, decode_constrained


def test_constrained_decode_is_always_a_glyph() -> None:
    rng = np.random.default_rng(3)
    invalid_threshold = 0
    for _ in range(2000):
        probs = rng.random(8)
        bits, margin = decode_constrained(probs)
        assert (bits & 0x7F) in VALID_PATTERNS
        assert margin >= 0.0
        if (target_to_bits(probs) & 0x7F) not in VALID_PATTERNS:
            invalid_threshold += 1
    # The threshold decoder does emit non-glyphs on random vectors; that is
    # the failure this decoder removes.
    assert invalid_threshold > 0


def test_constrained_decode_recovers_a_one_bit_loss() -> None:
    # A `9` whose segment e reads low decodes as 9 (not the non-glyph 9-minus-e)
    # when the other six segments are confident.
    nine = SegmentLabel.from_digit("9").bits
    probs = np.array([0.95 if (nine >> i) & 1 else 0.05 for i in range(7)] + [0.05])
    # 9 = a b c d f g; e is off already. Dim segment c toward 0.45.
    probs[2] = 0.45
    bits, _ = decode_constrained(probs)
    assert SegmentLabel(bits).digit == "9"
    assert SegmentLabel(target_to_bits(probs) & 0x7F).digit is None


def test_reading_order_rolls_corners_like_the_swift_side() -> None:
    """Oracle: 90 degrees clockwise makes the image's left edge the top edge, so
    the upright top-left is the image's bottom-left; 270 makes the right edge
    the top. The rotated fixtures (`pump-019/020` at 90, `pump-021/022/023` at
    270) were warped as vertical slivers before this rule existed."""
    from pump_reader.score import reading_order

    tl, tr, br, bl = [0, 0], [1, 0], [1, 1], [0, 1]
    q = np.array([tl, tr, br, bl], float)
    assert reading_order(q, 90).tolist() == [bl, tl, tr, br]
    assert reading_order(q, 270).tolist() == [tr, br, bl, tl]
    assert reading_order(q, 0).tolist() == q.tolist()

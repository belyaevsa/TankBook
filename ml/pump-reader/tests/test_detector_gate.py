"""Decision 10's detector gate, asserted as an ordering rule.

The gate decides whether a detector CANDIDATE ships; a human reads
``detector/measure.swift``'s summary line and applies it, and nothing the reader
executes calls it. It lives here, beside its only test, because the write set for
the row that added it allowed ``tests/`` and not the runtime package: keeping the
rule and the test that pins its ordering in one file stops the two drifting.
``docs/EXTRACTION.md`` states the rule and ``measure.swift`` prints the numbers
it reads.

The point of the contrast below: recall @ IoU 0.5 prefers boxes that overlap a
row loosely but match more rows at the loose threshold, while the read stage
consumes the box's tight framing. A gate on recall@0.5 therefore calls a
worse-framed detector better - which is exactly what happened to PU.48.
"""

from __future__ import annotations

FALSE_ROWS_SLACK = 0.05

Box = tuple[float, float, float, float]


def iou(a: Box, b: Box) -> float:
    """IoU of two boxes, mirroring ``measure.swift``."""
    ax0, ay0, ax1, ay1 = a
    bx0, by0, bx1, by1 = b
    ix = max(0.0, min(ax1, bx1) - max(ax0, bx0))
    iy = max(0.0, min(ay1, by1) - max(ay0, by0))
    inter = ix * iy
    union = (ax1 - ax0) * (ay1 - ay0) + (bx1 - bx0) * (by1 - by0) - inter
    return inter / union if union > 0 else 0.0


def score(predictions: list[Box], truth: list[Box], photos: int = 1) -> dict[str, float]:
    """The metrics the gate reads, mirroring ``measure.swift``.

    Each truth box takes its best still-unmatched prediction; an unmatched truth
    scores IoU 0. ``false_rows_per_photo`` counts predictions that matched no
    truth (measure.swift's "found - matched").
    """
    matched: set[int] = set()
    ious: list[float] = []
    hit50 = hit70 = 0
    for t in truth:
        best, best_index = 0.0, -1
        for i, p in enumerate(predictions):
            if i in matched:
                continue
            value = iou(t, p)
            if value > best:
                best, best_index = value, i
        ious.append(best)
        if best >= 0.5:
            hit50 += 1
            matched.add(best_index)
        if best >= 0.7:
            hit70 += 1
    ious.sort()
    median = ious[len(ious) // 2] if ious else 0.0
    total = len(truth)
    return {
        "recall50": hit50 / total if total else 0.0,
        "recall70": hit70 / total if total else 0.0,
        "median_iou": median,
        "false_rows_per_photo": (len(predictions) - len(matched)) / photos,
    }


def detector_gate(
    baseline: dict[str, float], candidate: dict[str, float], false_rows_slack: float = FALSE_ROWS_SLACK
) -> tuple[bool, list[str]]:
    """Decision 10's gate: tight framing decides, recall@0.5 never does.

    A candidate ships only when median IoU and recall@0.7 both hold or rise and
    false rows/photo does not rise by more than ``false_rows_slack``.
    """
    failures: list[str] = []
    if candidate["median_iou"] < baseline["median_iou"]:
        failures.append("median IoU fell")
    if candidate["recall70"] < baseline["recall70"]:
        failures.append("recall@0.7 fell")
    if candidate["false_rows_per_photo"] > baseline["false_rows_per_photo"] + false_rows_slack:
        failures.append("false rows/photo rose by more than the slack")
    return (not failures, failures)


def old_gate(baseline: dict[str, float], candidate: dict[str, float]) -> bool:
    """The rule this gate replaces: recall @ IoU 0.5 alone decides."""
    return candidate["recall50"] >= baseline["recall50"]


def _box(x: float, width: float = 10.0, height: float = 10.0) -> Box:
    return (x, 0.0, x + width, height)


_TRUTH = [_box(i * 20.0) for i in range(10)]

# Tight: exact on the first six rows and nothing else - high IoU, no false rows.
_TIGHT = [_box(i * 20.0) for i in range(6)]

# Loose: shifted 2.5 px (IoU 0.60) so every row matches at 0.5 and none at 0.7,
# plus three boxes that match nothing.
_LOOSE = [_box(i * 20.0 + 2.5) for i in range(10)] + [_box(1000.0 + i * 20.0) for i in range(3)]


def test_gate_prefers_tight_over_loose() -> None:
    tight = score(_TIGHT, _TRUTH)
    loose = score(_LOOSE, _TRUTH)

    # The loose set wins on the loose metric alone; it is worse on every tight one.
    assert loose["recall50"] > tight["recall50"]
    assert loose["recall70"] < tight["recall70"]
    assert loose["median_iou"] < tight["median_iou"]
    assert loose["false_rows_per_photo"] > tight["false_rows_per_photo"]

    passed, reasons = detector_gate(tight, loose)
    assert not passed, reasons
    assert detector_gate(loose, tight)[0]


def test_old_rule_prefers_the_loose_set() -> None:
    tight = score(_TIGHT, _TRUTH)
    loose = score(_LOOSE, _TRUTH)

    # recall@0.5 alone is the trap: it prefers the worse-framed boxes.
    assert old_gate(tight, loose)
    assert not old_gate(loose, tight)

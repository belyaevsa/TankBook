"""The checked-in calibration: monotone quantiles, per-field counts, and the
synthetic draw's aspect p50 reproducing the corpus's calibrated p50.

Oracle: ``src/pump_reader/calibration.json`` (the corpus's aggregate geometry,
measured over transaction windows only - never pixels, never per-fixture
labels). ``render_slicer_cell`` samples its crop aspect from those quantiles, so
a 500-sample draw's median aspect must land within 0.1 of the calibrated p50.
"""

from __future__ import annotations

import numpy as np

from pump_reader.calibration import Q_KEYS, load_calibration
from pump_reader.dataset import render_slicer_cell
from pump_reader.glyph import SegmentLabel
from pump_reader.profiles import PROFILES

_FIELDS = ("total", "liters", "unitPrice")


def _assert_monotone(qs: list[float], name: str) -> None:
    assert qs == sorted(qs), f"{name} quantiles not monotone: {qs}"


def test_calibration_quantiles_monotone_and_counted() -> None:
    cal = load_calibration()
    data = cal.data
    aspect = [data["aspect"][k] for k in Q_KEYS]
    _assert_monotone(aspect, "aspect")
    assert data["aspect"]["count"] > 0
    for section in ("right_margin_frac", "left_margin_frac"):
        _assert_monotone([data["phase"][section][k] for k in Q_KEYS], f"phase.{section}")
        assert data["phase"][section]["count"] > 0
    for field in _FIELDS:
        assert sum(data["digit_frequency"][field].values()) > 0, f"{field} has no digit counts"
        assert data["leading_zero_run_length"][field]["count"] > 0, f"{field} has no zero-run count"
        assert 0.0 <= data["dp_rate"][field] <= 1.0, f"{field} dp_rate out of range"
    assert 0.0 <= data["dp_rate"]["all"] <= 1.0


def test_calibration_aspect_draw_matches_p50() -> None:
    cal = load_calibration()
    p50 = cal.data["aspect"]["p50"]
    rng = np.random.default_rng(20260919)
    aspects = []
    record: dict = {}
    for _ in range(500):
        profile = PROFILES[str(rng.choice(list(PROFILES)))]
        render_slicer_cell(
            SegmentLabel.from_digit("8"), profile, rng, augment=False, record=record
        )
        aspects.append(record["aspect"])
    drawn = float(np.percentile(np.asarray(aspects), 50.0))
    assert abs(drawn - p50) <= 0.1, f"drawn aspect p50 {drawn:.3f} vs calibrated {p50:.3f}"

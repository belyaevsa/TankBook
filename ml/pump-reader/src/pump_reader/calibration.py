"""Loader and sampler for ``calibration.json`` (PU.18).

The renderer draws its crop geometry from the corpus's aggregate statistics
rather than hardcoded ranges: cell aspect, the horizontal phase, and the dp
presence rate. ``Calibration`` loads the checked-in JSON and samples from the
stored quantiles by inverse-CDF interpolation, so the sampled median lands on
the calibrated p50 exactly.
"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

import numpy as np

Q_KEYS: tuple[str, ...] = ("p5", "p25", "p50", "p75", "p95")
Q_POSITIONS: tuple[float, ...] = (0.05, 0.25, 0.50, 0.75, 0.95)

_CALIBRATION_PATH = Path(__file__).with_name("calibration.json")


def sample_quantiles(qs: list[float], rng: np.random.Generator) -> float:
    """Inverse-CDF sample from ``[p5, p25, p50, p75, p95]`` (piecewise linear).

    ``u = 0.5`` maps to the p50 exactly; ``u`` below 0.05 or above 0.95 clamps
    to p5 / p95 so the tails stay inside the measured support.
    """
    u = float(rng.uniform(0.0, 1.0))
    if u <= Q_POSITIONS[0]:
        return qs[0]
    if u >= Q_POSITIONS[-1]:
        return qs[-1]
    for i in range(len(Q_POSITIONS) - 1):
        if u <= Q_POSITIONS[i + 1]:
            f = (u - Q_POSITIONS[i]) / (Q_POSITIONS[i + 1] - Q_POSITIONS[i])
            return qs[i] + f * (qs[i + 1] - qs[i])
    return qs[-1]


class Calibration:
    """A loaded ``calibration.json`` with quantile samplers."""

    def __init__(self, data: dict) -> None:
        self.data = data

    @classmethod
    def load(cls, path: Path | None = None) -> "Calibration":
        path = path or _CALIBRATION_PATH
        return cls(json.loads(path.read_text(encoding="utf-8")))

    @staticmethod
    def _qs(quantile_dict: dict) -> list[float]:
        return [quantile_dict[k] for k in Q_KEYS]

    def sample_aspect(self, rng: np.random.Generator) -> float:
        return sample_quantiles(self._qs(self.data["aspect"]), rng)

    def dp_rate(self) -> float:
        return float(self.data["dp_rate"]["all"])

    @property
    def strip_height(self) -> int:
        return int(self.data.get("strip_height", 96))


@lru_cache(maxsize=1)
def _cached() -> Calibration:
    return Calibration.load()


def load_calibration() -> Calibration:
    """The checked-in calibration, cached (tests and the dataset share it)."""
    return _cached()

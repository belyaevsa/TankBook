"""Dataset: 1 000 samples cover every technology and make, respect the class
floor, and every tensor is a bounded 3x48x32 float.

Oracle: the sampling priors in ``dataset.py`` (LCD-heavy; see
``TECHNOLOGY_PRIORS``), blank and dp-only at >= 8 % each. The class of a sample
is read off its target bits (all-off = blank, dp-only bit = the standalone dot),
and make/technology from ``SyntheticDataset.meta``.
"""

from __future__ import annotations

from pump_reader.dataset import (
    BLANK_PRIOR,
    DP_ONLY_PRIOR,
    TECHNOLOGIES,
    TECHNOLOGY_PRIORS,
    SyntheticDataset,
    target_to_bits,
)
from pump_reader.profiles import PROFILES

N = 1_000


def test_technology_priors_sum_to_one_and_lcd_dominates() -> None:
    assert set(TECHNOLOGY_PRIORS) == set(TECHNOLOGIES)
    assert abs(sum(TECHNOLOGY_PRIORS.values()) - 1.0) < 1e-9
    assert TECHNOLOGY_PRIORS["lcd"] == max(TECHNOLOGY_PRIORS.values())
    assert TECHNOLOGY_PRIORS["lcd"] >= 0.8, "the corpus is ~90 % LCD; the prior must follow"


def test_dataset_covers_technology_make_and_classes() -> None:
    ds = SyntheticDataset(seed=20260919, length=N, cache=False)
    makes: set[str] = set()
    techs: set[str] = set()
    blank = 0
    dp_only = 0
    for i in range(N):
        tensor, target = ds[i]
        assert tensor.shape == (3, 48, 32), f"sample {i} shape {tensor.shape}"
        assert float(tensor.min()) >= 0.0, f"sample {i} min below 0"
        assert float(tensor.max()) <= 1.0, f"sample {i} max above 1"
        make, tech = ds.meta(i)
        makes.add(make)
        techs.add(tech)
        bits = target_to_bits(target)
        if bits == 0:
            blank += 1
        elif bits == 0x80:
            dp_only += 1

    assert makes == set(PROFILES), f"missing makes: {set(PROFILES) - makes}"
    assert techs == set(TECHNOLOGIES), f"missing technologies: {set(TECHNOLOGIES) - techs}"
    assert blank / N >= 0.05, f"blank rate {blank / N:.3f} below floor"
    assert dp_only / N >= 0.05, f"dp-only rate {dp_only / N:.3f} below floor"
    assert BLANK_PRIOR >= 0.08 and DP_ONLY_PRIOR >= 0.08

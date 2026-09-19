"""The abstention frontier ranks: accuracy falls with coverage.

Oracle: the frontier's own construction. A margin that carries information
makes the confident prefix more accurate than the whole; a constant margin
(the named mutation) makes every decile equal the overall accuracy.
"""

from __future__ import annotations

import numpy as np

from pump_reader.score import frontier_curve


def test_frontier_is_monotone_and_a_constant_margin_flattens_it() -> None:
    rng = np.random.default_rng(5)
    # A signal that ranks: correct cells tend to have larger margins.
    items = [(float(rng.normal(3.0 if ok else 1.0, 1.0)), bool(ok)) for ok in rng.random(2000) < 0.7]
    f = frontier_curve(items)
    accs = [a for _, a in f["deciles"]]
    assert accs[0] > accs[-1] + 0.1
    assert all(a >= b - 0.02 for a, b in zip(accs, accs[1:]))
    assert f["coverage_0.95"] > 0
    flat = frontier_curve([(1.0, ok) for _, ok in items])
    flat_accs = [a for _, a in flat["deciles"]]
    assert max(flat_accs) - min(flat_accs) < 0.06

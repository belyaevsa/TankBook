import numpy as np

from pump_reader import temperature


def _labels(n: int, rng: np.random.Generator) -> np.ndarray:
    return (rng.random((n, 8)) < 0.4).astype(np.float64)


def test_fit_recovers_a_known_temperature():
    # Logits drawn calibrated at scale 1, then shrunk by 0.5: the fitted T must
    # undo the shrink (T ~ 0.5).
    rng = np.random.default_rng(0)
    true_logits = rng.normal(0, 3, size=(20000, 8))
    y = (rng.random(true_logits.shape) < temperature.sigmoid(true_logits)).astype(np.float64)
    T = temperature.fit_temperature(true_logits * 0.5, y)
    assert abs(T - 0.5) < 0.03


def test_a_shared_temperature_changes_no_digit_ranking():
    rng = np.random.default_rng(1)
    # Logits kept inside the decoder's 1e-6 clamp at every T tried: past it,
    # clamped labels tie and the ranking is the clamp's, not the model's.
    z = np.clip(rng.normal(0, 2, size=(5000, 8)), -7, 7)
    before = temperature.sigmoid(z)
    for T in (0.57, 1.0, 2.0):
        assert (temperature.digit_ranks(before) == temperature.digit_ranks(temperature.sigmoid(z / T))).all()


def test_report_is_well_formed_and_flips_nothing():
    rng = np.random.default_rng(2)
    z = rng.normal(0, 3, size=(3000, 8))
    result = temperature.report(z, _labels(3000, rng))
    assert result["digitFlips"] == 0
    assert result["temperature"] > 0
    assert len(result["nll"]) == 2 and result["nll"][1] <= result["nll"][0] + 1e-9


def test_ece_is_zero_for_a_perfectly_calibrated_certain_predictor():
    y = np.array([[1, 0, 1, 0, 1, 0, 1, 0]] * 50, dtype=np.float64)
    assert temperature.ece_confidence(y, y) == 0.0
    assert temperature.ece_per_label(y, y) == 0.0


def test_confidence_ece_weights_by_every_label_prediction():
    # Two cells, eight labels, every prediction 0.8 and every label 1: each bin
    # holds all 16 predictions at confidence 0.8 and accuracy 1, so ECE = 0.2.
    # Weighting by cells instead of predictions would read 1.6.
    y = np.ones((2, 8))
    p = np.full((2, 8), 0.8)
    assert abs(temperature.ece_confidence(y, p) - 0.2) < 1e-12


def test_ece_ml_pairs_each_side_with_its_own_labels():
    # One label column repeated eight times: positives read 0.9 and 0.6 (error
    # 0.25), negatives 0.2 and 0.1 (error 0.15) -> 0.2. Indexing the full label
    # column with the one-sided subset's indices reads 0.3.
    column_y = np.array([0, 1, 0, 1], dtype=np.float64)
    column_p = np.array([0.2, 0.9, 0.1, 0.6])
    y = np.tile(column_y[:, None], (1, 8))
    p = np.tile(column_p[:, None], (1, 8))
    assert abs(temperature.ece_ml(y, p) - 0.2) < 1e-12

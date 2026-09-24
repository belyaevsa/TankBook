import torch

from pump_reader.train import segment_loss


def test_defaults_are_exactly_bce():
    # The paper's eq. (4) statement: focal loss at gamma 0 (no alpha, unit
    # weight) is cross-entropy. The control arm depends on it.
    torch.manual_seed(0)
    logits = torch.randn(64, 8)
    hard = (torch.rand(64, 8) < 0.3).float()
    soft = hard * 0.95 + 0.025
    ours = segment_loss(torch.ones(8), 0.0, None)(logits, soft, hard)
    reference = torch.nn.BCEWithLogitsLoss()(logits, soft)
    assert torch.allclose(ours, reference, atol=1e-7)


def test_focal_down_weights_easy_examples():
    logits = torch.tensor([[6.0] * 8, [0.1] * 8])
    hard = torch.ones(2, 8)
    per = [segment_loss(torch.ones(8), 2.0, None)(logits[i:i + 1], hard[i:i + 1], hard[i:i + 1]) for i in range(2)]
    plain = [segment_loss(torch.ones(8), 0.0, None)(logits[i:i + 1], hard[i:i + 1], hard[i:i + 1]) for i in range(2)]
    # The confident example loses far more of its loss than the uncertain one.
    assert per[0] / plain[0] < 0.01 < per[1] / plain[1]


def test_dp_pos_weight_touches_only_the_dp_bit():
    logits = torch.zeros(4, 8)
    hard = torch.ones(4, 8)
    weight = torch.ones(8)
    weight[7] = 3.0
    base = segment_loss(torch.ones(8), 0.0, None)(logits, hard, hard)
    weighted = segment_loss(weight, 0.0, None)(logits, hard, hard)
    assert abs(float(weighted) - float(base) * (7 + 3) / 8) < 1e-6


def test_dp_pos_weight_vector_weights_only_the_dp_bit():
    from pump_reader.train import dp_pos_weight_vector
    weights = dp_pos_weight_vector(8, 3.52)
    assert weights[:7].tolist() == [1.0] * 7 and abs(float(weights[7]) - 3.52) < 1e-6
    assert dp_pos_weight_vector(7, 3.52).tolist() == [1.0] * 7


def test_cli_defaults_are_the_shipped_training():
    from pump_reader.train import build_parser
    args = build_parser().parse_args(["--out", "/tmp/unused"])
    assert (args.dp_pos_weight, args.focal_gamma, args.focal_alpha, args.head) == (1.0, 0.0, None, "gap")

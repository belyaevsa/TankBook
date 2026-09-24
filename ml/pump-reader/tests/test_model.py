"""Model: ``SegmentNet`` forwards a batch of 4 to shape (4, 8) and stays under
130 000 parameters (oracle: the <= 500 KB float32 export target, which 130k
params would blow: 130k * 4 bytes = 520 KB).
"""

from __future__ import annotations

import torch

from pump_reader.model import SegmentNet, count_parameters


def test_segmentnet_shape_and_size() -> None:
    net = SegmentNet()
    out = net(torch.randn(4, 3, 48, 32))
    assert tuple(out.shape) == (4, 8)
    assert count_parameters(net) < 130_000, f"params {count_parameters(net)}"


def test_heads_keep_the_io_contract_and_budget():
    import torch

    from pump_reader.model import SegmentNet, count_parameters
    x = torch.zeros(2, 3, 48, 32)
    for head in ("gap", "flatten", "coord"):
        net = SegmentNet(head)
        assert net(x).shape == (2, 8)
        assert count_parameters(net) < 125_000


def test_coord_with_zero_coordinate_weights_is_the_plain_stem():
    # Liu et al. §3: CoordConv whose coordinate weights are zero is an ordinary
    # convolution - the Round B control equivalence.
    import torch

    from pump_reader.model import SegmentNet
    torch.manual_seed(0)
    plain, coord = SegmentNet("gap").eval(), SegmentNet("coord").eval()
    state = coord.state_dict()
    for key, value in plain.state_dict().items():
        if key == "features.0.0.weight":
            state[key] = torch.zeros_like(state[key])
            state[key][:, :3] = value
        else:
            state[key] = value
    coord.load_state_dict(state)
    x = torch.rand(4, 3, 48, 32)
    assert torch.allclose(plain(x), coord(x), atol=1e-6)


def test_coord_head_really_adds_coordinates():
    import torch

    from pump_reader.model import SegmentNet
    coord = SegmentNet("coord").eval()
    assert coord.coords.shape == (1, 2, 48, 32)
    assert float(coord.coords.min()) == -1.0 and float(coord.coords.max()) == 1.0
    assert coord.features[0][0].weight.shape[1] == 5
    # With non-zero coordinate weights the output depends on position: shifting
    # the SAME image content must change it, unlike an average-pooled plain stem
    # fed a constant image.
    torch.manual_seed(0)
    x = torch.full((1, 3, 48, 32), 0.5)
    plain = SegmentNet("gap").eval()
    state = coord.state_dict()
    for key, value in plain.state_dict().items():
        if key == "features.0.0.weight":
            state[key][:, :3] = value
        else:
            state[key] = value
    coord.load_state_dict(state)
    assert not torch.allclose(plain(x), coord(x), atol=1e-4)


def test_flatten_head_keeps_the_layout():
    import torch

    from pump_reader.model import SegmentNet
    flat, gap = SegmentNet("flatten").eval(), SegmentNet("gap").eval()
    assert flat.classifier.weight.shape == (8, 1536)
    torch.manual_seed(0)
    x = torch.rand(2, 3, 48, 32)
    assert flat(x).shape == gap(x).shape == (2, 8)

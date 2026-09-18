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

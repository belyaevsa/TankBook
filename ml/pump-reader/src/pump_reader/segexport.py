"""CLI: ``python -m pump_reader.segexport <run>/segnet.pt <out>.mlpackage``.

Exports the PU.76 spike's segmenter as a Core ML ``mlprogram`` (iOS 18): a
512 x 512 RGB image in, the nine sigmoid maps out as ``maps`` [1, 9, 256, 256]
(pixel, then the eight links in `segnet.NEIGHBOURS` order). The conversion is
the classifier's (`export.py`): conv, batch norm, ReLU, upsampling and sigmoid
only - no custom op and no in-graph NMS.
"""

from __future__ import annotations

import sys
from pathlib import Path

import torch
from torch import nn

from pump_reader import segnet
from pump_reader.export import _git_short_sha


class _Sigmoid(nn.Module):
    def __init__(self, net: nn.Module) -> None:
        super().__init__()
        self.net = net

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return torch.sigmoid(self.net(x))


def export(checkpoint: Path, out: Path) -> None:
    import coremltools as ct

    state = torch.load(checkpoint, map_location="cpu")
    net = segnet.SegNet(state["width"])
    net.load_state_dict(state["state_dict"])
    wrapped = _Sigmoid(net.eval()).eval()
    traced = torch.jit.trace(wrapped, torch.rand(1, 3, 512, 512))
    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=[ct.ImageType(name="image", shape=(1, 3, 512, 512), scale=1 / 255.0,
                             color_layout=ct.colorlayout.RGB)],
        outputs=[ct.TensorType(name="maps")],
        minimum_deployment_target=ct.target.iOS18,
    )
    mlmodel.author = "Tankbook"
    mlmodel.short_description = "PU.76 spike: pixel + 8 link maps of pump-display digit rows (PixelLink)."
    mlmodel.version = _git_short_sha()
    mlmodel.save(str(out))


if __name__ == "__main__":
    export(Path(sys.argv[1]), Path(sys.argv[2]))

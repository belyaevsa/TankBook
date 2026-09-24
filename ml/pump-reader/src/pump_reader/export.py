"""CLI: ``python -m pump_reader.export --checkpoint DIR/segmentnet.pt --out …``.

Converts a trained ``SegmentNet`` to a Core ML ML Program package. The sigmoid is
placed *in* the exported graph, so the single output ``segments`` is 8
probabilities with no post-processing on the device. Input is a 32x48 RGB image
scaled by 1/255 to match the ``[0, 1]`` floats the model was trained on.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

import torch
from torch import nn

from .model import SegmentNet


def _git_short_sha() -> str:
    try:
        return subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "unknown"


class _SigmoidNet(nn.Module):
    """Wraps ``SegmentNet`` so the exported graph includes the sigmoid."""

    def __init__(self, net: SegmentNet) -> None:
        super().__init__()
        self.net = net

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return torch.sigmoid(self.net(x))


def export(checkpoint: Path, out: Path) -> None:
    import coremltools as ct

    state = torch.load(checkpoint, map_location="cpu")
    net = SegmentNet(state.get("head", "gap"))
    net.load_state_dict(state["state_dict"])
    net.eval()
    wrapped = _SigmoidNet(net).eval()

    example = torch.rand(1, 3, 48, 32)
    traced = torch.jit.trace(wrapped, example)

    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=[
            ct.ImageType(
                name="glyph",
                shape=(1, 3, 48, 32),
                scale=1 / 255.0,
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.TensorType(name="segments")],
        minimum_deployment_target=ct.target.iOS18,
    )
    mlmodel.author = "Tankbook"
    mlmodel.short_description = "Seven-segment pump-display classifier; output order a b c d e f g dp."
    mlmodel.version = _git_short_sha()

    out.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(out))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="pump_reader.export")
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    export(args.checkpoint, args.out)
    print(f"exported to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

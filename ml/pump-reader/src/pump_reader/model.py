"""The segment classifier (PU.3).

A small CNN that reads a 32x48 glyph and predicts 8 segment logits (a-g, dp).
The digit is never a stored class: it is a lookup over the thresholded segment
bits, so a ``9`` whose segment ``e`` is uncertain is a ``4`` candidate with a
known posterior rather than a confident wrong digit (`docs/EXTRACTION.md` -> "The
pump reader").

Target size is <= 500 KB at float32, which caps the parameter count around 125k.
"""

from __future__ import annotations

import torch
from torch import nn


def _block(in_ch: int, out_ch: int) -> nn.Sequential:
    return nn.Sequential(
        nn.Conv2d(in_ch, out_ch, 3, padding=1),
        nn.BatchNorm2d(out_ch),
        nn.ReLU(inplace=True),
        nn.MaxPool2d(2),
    )


HEADS = ("gap", "flatten", "coord")


class SegmentNet(nn.Module):
    """3 conv blocks -> a head -> 8 logits.

    Input ``(N, 3, 48, 32)``; output ``(N, 8)`` (logits, sigmoid applied by the
    caller or at export). Weights live in ``self.features`` / ``self.classifier``.

    ``head`` (PU.73 Round B, agents/research/PU.73.md §3.2): ``gap`` averages the
    last feature map, as the shipped model does; ``flatten`` keeps where on the
    glyph each feature fired (a flatten + fully connected head); ``coord`` adds
    two coordinate channels in [-1, 1] before the first convolution (CoordConv,
    Liu et al. 2018, arXiv:1807.03247) and keeps the average pool.
    """

    def __init__(self, head: str = "gap") -> None:
        super().__init__()
        if head not in HEADS:
            raise ValueError(f"unknown head {head!r}")
        self.head = head
        stem = 5 if head == "coord" else 3
        self.features = nn.Sequential(
            _block(stem, 16),
            _block(16, 32),
            _block(32, 64),
        )
        self.classifier = nn.Linear(64 * 6 * 4 if head == "flatten" else 64, 8)
        if head == "coord":
            rows = torch.linspace(-1, 1, 48).view(1, 1, 48, 1).expand(1, 1, 48, 32)
            cols = torch.linspace(-1, 1, 32).view(1, 1, 1, 32).expand(1, 1, 48, 32)
            self.register_buffer("coords", torch.cat([rows, cols], dim=1).clone())

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        if self.head == "coord":
            x = torch.cat([x, self.coords.expand(x.shape[0], -1, -1, -1)], dim=1)
        x = self.features(x)
        x = torch.flatten(x, 1) if self.head == "flatten" else x.mean(dim=(2, 3))
        return self.classifier(x)


def count_parameters(model: nn.Module) -> int:
    return sum(p.numel() for p in model.parameters())

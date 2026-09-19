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


class SegmentNet(nn.Module):
    """3 conv blocks -> global average pool -> 8 logits.

    Input ``(N, 3, 48, 32)``; output ``(N, 8)`` (logits, sigmoid applied by the
    caller or at export). Weights live in ``self.features`` / ``self.classifier``.
    """

    def __init__(self) -> None:
        super().__init__()
        self.features = nn.Sequential(
            _block(3, 16),
            _block(16, 32),
            _block(32, 64),
        )
        self.classifier = nn.Linear(64, 8)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.features(x)
        x = x.mean(dim=(2, 3))
        return self.classifier(x)


def count_parameters(model: nn.Module) -> int:
    return sum(p.numel() for p in model.parameters())

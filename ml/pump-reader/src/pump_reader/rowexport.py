"""CLI: ``python -m pump_reader.rowexport --run <run dir> --out <RowRead.mlpackage>``.

Exports a row reader checkpoint (`rowtrain.py`'s ``crnn.pt``) to the Core ML program the app
bundles: input ``strip`` [1, 3, 32, W] in 0..1 with W between the reader's minimum and maximum
widths, output ``logprobs`` [T, 12] (log-softmax per frame, T = W / 4 - 1). Float32, because the
decoding compares likelihoods across the ten substitutions of every digit. The export is checked
against PyTorch at three widths before it is written.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import torch

from pump_reader import rowreader as rr


class _LogProbs(torch.nn.Module):
    def __init__(self, model: torch.nn.Module) -> None:
        super().__init__()
        self.model = model

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.model(x)[:, 0].log_softmax(1)


def main(argv: list[str] | None = None) -> int:
    import coremltools as ct  # noqa: PLC0415 - optional dependency, the export extra

    p = argparse.ArgumentParser(prog="pump_reader.rowexport")
    p.add_argument("--run", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    args = p.parse_args(argv)
    model = rr.CRNN()
    model.load_state_dict(torch.load(args.run / "crnn.pt", map_location="cpu")["state_dict"])
    wrapped = _LogProbs(model.eval()).eval()
    traced = torch.jit.trace(wrapped, torch.rand(1, 3, rr.HEIGHT, 128))
    width = ct.RangeDim(rr.MIN_WIDTH, rr.MAX_WIDTH, default=128)
    ml = ct.convert(traced, inputs=[ct.TensorType(name="strip", shape=(1, 3, rr.HEIGHT, width))],
                    outputs=[ct.TensorType(name="logprobs")], convert_to="mlprogram",
                    minimum_deployment_target=ct.target.iOS18, compute_precision=ct.precision.FLOAT32)
    ml.short_description = "Pump row reader: a CRNN over a 32 px row strip, CTC log-probabilities per frame"
    for w in (rr.MIN_WIDTH, 131, rr.MAX_WIDTH):
        x = torch.rand(1, 3, rr.HEIGHT, w)
        gap = float(np.abs(wrapped(x).detach().numpy() - ml.predict({"strip": x.numpy()})["logprobs"]).max())
        print(f"width {w}: max |torch - coreml| = {gap:.2e}")
        if gap > 1e-3:
            raise SystemExit(f"export disagrees with PyTorch at width {w}")
    ml.save(str(args.out))
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

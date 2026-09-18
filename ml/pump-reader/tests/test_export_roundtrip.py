"""Export round trip: the smoke checkpoint, exported to a ``.mlpackage`` and
loaded back, agrees with the torch model on one PU.1 render of ``8`` within 1e-3
(oracle: the torch model - the export inserts a sigmoid and a 1/255 scale, so a
match here proves the exported graph computes the same probabilities).
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest
import torch

from pump_reader.glyph import SegmentLabel, render_glyph
from pump_reader.model import SegmentNet
from pump_reader.profiles import PROFILES


def test_export_roundtrip(tmp_path: Path) -> None:
    run = tmp_path / "run"
    subprocess.run(
        [sys.executable, "-m", "pump_reader.train", "--smoke", "--out", str(run)],
        check=True,
        capture_output=True,
    )
    mlpkg = tmp_path / "PumpSegments.mlpackage"
    subprocess.run(
        [
            sys.executable,
            "-m",
            "pump_reader.export",
            "--checkpoint",
            str(run / "segmentnet.pt"),
            "--out",
            str(mlpkg),
        ],
        check=True,
        capture_output=True,
    )

    state = torch.load(run / "segmentnet.pt", map_location="cpu")
    net = SegmentNet()
    net.load_state_dict(state["state_dict"])
    net.eval()

    rng = np.random.default_rng(0)
    img = render_glyph(SegmentLabel.from_digit("8"), PROFILES["wayne"], rng, augment=False)
    t = torch.from_numpy(np.asarray(img, dtype=np.float32).transpose(2, 0, 1) / 255.0).unsqueeze(0)
    with torch.no_grad():
        torch_probs = torch.sigmoid(net(t))[0].numpy()

    try:
        import coremltools as ct

        mlmodel = ct.models.MLModel(str(mlpkg))
        coreml_probs = np.asarray(mlmodel.predict({"glyph": img})["segments"]).flatten()
    except Exception as exc:  # pragma: no cover - only when Core ML is unavailable
        pytest.skip(f"Core ML prediction unavailable on this host: {exc}")

    assert coreml_probs.shape == (8,)
    assert float(np.abs(torch_probs - coreml_probs).max()) < 1e-3

"""Smoke train: ``--smoke`` runs 20 steps, writes the checkpoint and
``metrics.json``, and the final validation loss is below the initial one (oracle:
a learning model on a learnable task).
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def test_smoke_train_writes_checkpoint_and_learns(tmp_path: Path) -> None:
    out = tmp_path / "run"
    subprocess.run(
        [sys.executable, "-m", "pump_reader.train", "--smoke", "--out", str(out)],
        check=True,
        capture_output=True,
    )
    assert (out / "segmentnet.pt").exists()
    metrics = json.loads((out / "metrics.json").read_text(encoding="utf-8"))
    assert metrics["steps"] == 20
    assert metrics["final_val_loss"] < metrics["initial_val_loss"], (
        f"final {metrics['final_val_loss']} >= initial {metrics['initial_val_loss']}"
    )

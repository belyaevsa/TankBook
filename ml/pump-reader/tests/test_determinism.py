"""Determinism: the seed contract.

Oracle: a fixed seed reproduces byte-identical output. Two runs of the CLI with
``--seed 7 --count 50`` into different directories must produce byte-identical
PNGs and CSVs (not merely the same file count).
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def _run(out: Path) -> None:
    subprocess.run(
        [
            sys.executable,
            "-m",
            "pump_reader.render",
            "--count",
            "50",
            "--seed",
            "7",
            "--out",
            str(out),
        ],
        check=True,
        capture_output=True,
    )


def test_seed_reproduces_byte_identical_output(tmp_path: Path) -> None:
    out1 = tmp_path / "a"
    out2 = tmp_path / "b"
    _run(out1)
    _run(out2)

    files1 = sorted((out1 / "glyphs").glob("*.png"))
    files2 = sorted((out2 / "glyphs").glob("*.png"))
    assert len(files1) == 50
    assert len(files2) == 50
    for f1, f2 in zip(files1, files2):
        assert f1.read_bytes() == f2.read_bytes(), f"PNG differs: {f1.name}"
    assert (out1 / "labels.csv").read_bytes() == (out2 / "labels.csv").read_bytes()

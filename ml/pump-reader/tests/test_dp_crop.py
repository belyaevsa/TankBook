"""The dp framing (``--dp-crop``) and dp labels (``--dp-bits``) of a realglyphs
pool, and train.py's agreement with them. ``--dp-crop gap`` widens every cell's
crop to the right by 0.4 x pitch so a decimal mark in the inter-cell gap is inside
the pixels the bit is trained on; ``off`` is the shipped framing. ``--dp-bits
clear`` zeroes every dp bit because the slicer owns the mark; ``keep`` is the
default.

Oracle: the crop's own pixels for ``gap``/``off``, the stored labels for
``clear``/``keep``, and train.py's metrics.json for the agreement.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

from pump_reader import realglyphs

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))
import corpus_db as cdb  # noqa: E402

QUAD = [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]]


def _strip_with_mark() -> Image.Image:
    img = Image.new("RGB", (40, 20), "white")
    d = ImageDraw.Draw(img)
    d.rectangle([2, 2, 8, 18], fill="black")  # the digit
    d.rectangle([26, 12, 28, 14], fill="black")  # the mark in the gap after the cell
    return img


def test_gap_crop_widens_to_include_the_mark() -> None:
    img = _strip_with_mark()
    box = {"x0": 0.0, "x1": 0.5, "y0": 0.0, "y1": 1.0}
    off, _ = realglyphs.crop_cell(img, box, dp_crop="off")
    gap, _ = realglyphs.crop_cell(img, box, dp_crop="gap")
    assert off.shape == gap.shape == (3, 48, 32)
    assert gap[:, :, -3:].min() < 128, "the gap crop must carry the mark at its right edge"
    assert off[:, :, -3:].min() > 200, "the off crop stops at the cell edge, short of the mark"


def _add_still(con, name: str, split: str, text: str, ord_: int) -> None:
    con.execute("insert into fixtures values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (name, "pump", "unused", None, None, 40, 20, None, None, text, None, None, None, split, ord_))
    con.execute("insert into entries (fixture, rotationCW, reviewed, notOnDisplay, csvDisagrees, tracking, keys, extra, ord) "
                "values (?,?,?,?,?,?,?,?,?)", (name, 0, 0, None, None, None, '["windows"]', "{}", ord_))
    con.execute("insert into windows (fixture, ord, field, text, legibility, quad, x0, y0, x1, y1) "
                "values (?,?,?,?,?,?,?,?,?,?)",
                (name, 0, "total", text, None, json.dumps(QUAD), 0.0, 0.0, 1.0, 1.0))


def _corpus(tmp_path: Path, text: str, cells: int) -> tuple[Path, Path]:
    db = tmp_path / "c.sqlite"
    con = cdb.connect(db)
    con.executescript(cdb.SCHEMA)
    _add_still(con, "pump-900-a-ee.jpg", "train", text, 0)
    con.commit()
    con.close()
    strip = "strips/s000000.png"
    (tmp_path / "strips").mkdir()
    Image.new("RGB", (40, 20), "white").save(tmp_path / strip)
    window = {"fixture": "pump-900-a-ee.jpg", "frame": None, "field": "total", "text": text, "strip": strip,
              "cells": [{"x0": i / cells, "x1": (i + 1) / cells, "y0": 0.0, "y1": 1.0,
                         "isBlank": False, "hasDecimalPoint": False} for i in range(cells)]}
    manifest = tmp_path / "export.json"
    manifest.write_text(json.dumps({"windows": [window]}))
    return db, manifest


def _run(tmp_path: Path, db: Path, manifest: Path, *extra: str) -> tuple[dict, "object"]:
    import numpy as np

    out = tmp_path / "out"
    rc = realglyphs.main(["--export", str(manifest), "--out", str(out), "--db", str(db), *extra])
    assert rc == 0
    return json.loads((out / "manifest.json").read_text()), np.load(out / "cells.npz")["y"]


def test_dp_bits_clear_clears_every_dp_bit(tmp_path: Path) -> None:
    db, manifest = _corpus(tmp_path, "1.5", 2)
    m, y = _run(tmp_path, db, manifest, "--dp-bits", "clear")
    assert len(y) == 2, "the window must be used - a skipped window would make this vacuous"
    assert all(int(b) & 0x80 == 0 for b in y), f"a dp bit survived --dp-bits clear: {[int(b) for b in y]}"
    assert m["dp_bits"] == "clear" and m["dp_crop"] == "off"


def test_pool_defaults_are_the_shipped_framing(tmp_path: Path) -> None:
    db, manifest = _corpus(tmp_path, "1.5", 2)
    m, y = _run(tmp_path, db, manifest)
    assert (m["dp_crop"], m["dp_bits"]) == ("off", "keep")
    assert any(int(b) & 0x80 for b in y), "the default pool keeps the labelled dp bit"


def test_dp_crop_off_keeps_the_dp_bit(tmp_path: Path) -> None:
    db, manifest = _corpus(tmp_path, "1.5", 2)
    _, y = _run(tmp_path, db, manifest, "--dp-crop", "off")
    assert any(int(b) & 0x80 for b in y), "off must keep the labelled dp bit"


def test_train_default_agrees_with_the_pool(tmp_path: Path) -> None:
    """A pool built at realglyphs' defaults and a train run at train's defaults
    agree: 8 bits on the pool's kept dp labels, and metrics.json records both."""
    import subprocess

    db, manifest = _corpus(tmp_path, "1.5", 2)
    _run(tmp_path, db, manifest)
    run = tmp_path / "run"
    subprocess.run([sys.executable, "-m", "pump_reader.train", "--smoke", "--out", str(run),
                    "--real", str(tmp_path / "out")], check=True, capture_output=True)
    metrics = json.loads((run / "metrics.json").read_text())
    assert metrics["dp_bits"] == 8
    assert (metrics["pool_dp_crop"], metrics["pool_dp_bits"]) == ("off", "keep")


def test_train_follows_a_cleared_pool_and_refuses_eight_bits(tmp_path: Path) -> None:
    from pump_reader import train

    db, manifest = _corpus(tmp_path, "1.5", 2)
    _run(tmp_path, db, manifest, "--dp-bits", "clear")
    pool = train.pool_framing(tmp_path / "out")
    assert pool == {"dp_crop": "off", "dp_bits": "clear"}
    assert train.resolve_dp_bits(None, pool["dp_bits"]) == 7
    try:
        train.resolve_dp_bits(8, pool["dp_bits"])
    except SystemExit:
        pass
    else:
        raise AssertionError("an 8-bit run on a cleared pool must be refused")


def test_a_legacy_none_manifest_reads_as_a_cleared_off_pool(tmp_path: Path) -> None:
    from pump_reader import train

    (tmp_path / "manifest.json").write_text(json.dumps({"dp_crop": "none"}))
    assert train.pool_framing(tmp_path) == {"dp_crop": "off", "dp_bits": "clear"}

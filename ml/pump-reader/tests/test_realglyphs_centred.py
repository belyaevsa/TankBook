"""The centred-ink filter (``--centred``): a real cell whose ink sits in the
outer quarter of its crop is dropped, a centred one is kept, and a cell with no
ink is kept because there is nothing to judge.

A synthetic export (one strip, one still, one cell) is cut through the real
``realglyphs.main``, so the test exercises the crop, the centroid and the filter
together - not a helper in isolation.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from pump_reader import realglyphs

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))
import corpus_db as cdb  # noqa: E402

QUAD = [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]]


def _add_still(con, name: str, split: str, text: str, ord_: int) -> None:
    con.execute("insert into fixtures values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (name, "pump", "unused", None, None, 40, 20, None, None, text, None, None, None, split, ord_))
    con.execute("insert into entries (fixture, rotationCW, reviewed, notOnDisplay, csvDisagrees, tracking, keys, extra, ord) "
                "values (?,?,?,?,?,?,?,?,?)", (name, 0, 0, None, None, None, '["windows"]', "{}", ord_))
    con.execute("insert into windows (fixture, ord, field, text, legibility, quad, x0, y0, x1, y1) "
                "values (?,?,?,?,?,?,?,?,?,?)",
                (name, 0, "total", text, None, json.dumps(QUAD), 0.0, 0.0, 1.0, 1.0))


def _window(fixture: str, text: str, strip: str, cells: int) -> dict:
    return {"fixture": fixture, "frame": None, "field": "total", "text": text, "strip": strip,
            "cells": [{"x0": i / cells, "x1": (i + 1) / cells, "y0": 0.0, "y1": 1.0,
                       "isBlank": False, "hasDecimalPoint": False} for i in range(cells)]}


def _corpus(tmp_path: Path, draw) -> tuple[Path, Path]:
    db = tmp_path / "c.sqlite"
    con = cdb.connect(db)
    con.executescript(cdb.SCHEMA)
    _add_still(con, "pump-900-a-ee.jpg", "train", "1", 0)
    con.commit()
    con.close()
    strip = "strips/s000000.png"
    (tmp_path / "strips").mkdir()
    img = Image.new("RGB", (40, 20), "white")
    draw(ImageDraw.Draw(img))
    img.save(tmp_path / strip)
    export = {"windows": [_window("pump-900-a-ee.jpg", "1", strip, 1)]}
    manifest = tmp_path / "export.json"
    manifest.write_text(json.dumps(export))
    return db, manifest


def _run(tmp_path: Path, db: Path, manifest: Path, *extra: str) -> dict:
    out = tmp_path / "out"
    rc = realglyphs.main(["--export", str(manifest), "--out", str(out), "--db", str(db), *extra])
    assert rc == 0
    return json.loads((out / "manifest.json").read_text())


def test_centred_filter_keeps_a_centred_cell(tmp_path: Path) -> None:
    db, manifest = _corpus(tmp_path, lambda d: d.rectangle([18, 2, 22, 18], fill="black"))
    m = _run(tmp_path, db, manifest, "--centred", "0.25")
    assert m["centred_dropped_total"] == 0, "a centred cell must be kept"
    assert m["cells"] == 1


def test_centred_filter_drops_a_cell_whose_ink_is_off_centre(tmp_path: Path) -> None:
    db, manifest = _corpus(tmp_path, lambda d: d.rectangle([1, 2, 5, 18], fill="black"))
    m = _run(tmp_path, db, manifest, "--centred", "0.25")
    assert m["centred_dropped_total"] == 1, "a cell whose ink sits in the outer quarter must drop"
    assert m["centred_dropped"] == {"1": 1}
    assert m["cells"] == 0


def test_centred_filter_keeps_a_cell_with_no_ink(tmp_path: Path) -> None:
    db, manifest = _corpus(tmp_path, lambda d: None)
    m = _run(tmp_path, db, manifest, "--centred", "0.25")
    assert m["centred_dropped_total"] == 0, "a no-ink cell is kept: the filter cannot disqualify it"
    assert m["cells"] == 1


def test_ink_centroid_is_none_without_ink() -> None:
    flat = np.full((10, 20), 200.0, dtype=np.float32)
    assert realglyphs.ink_centroid(flat) is None


def test_ink_centroid_reads_the_light_on_dark_polarity() -> None:
    # A bright bar on a dark ground: the slicer's polarity rule says the ink is
    # the brighter tail, so the centroid follows the bar.
    dark = np.full((10, 20), 20.0, dtype=np.float32)
    dark[:, 14:17] = 220.0
    centroid = realglyphs.ink_centroid(dark)
    assert centroid is not None and 0.70 < centroid < 0.82

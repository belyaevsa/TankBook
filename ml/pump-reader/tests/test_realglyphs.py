"""The real-glyph sampler on the database: the pool is selected from the
database, the per-fixture cap and the hard-example weight both act on it.

A synthetic export (one strip, three stills) is cut through the real
``realglyphs.main`` against a temp database, so the test exercises the query,
the cap and the weight together, not a helper in isolation.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

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


def _window(fixture: str, text: str, strip: str) -> dict:
    n = len(text)
    return {"fixture": fixture, "frame": None, "field": "total", "text": text, "strip": strip,
            "cells": [{"x0": i / n, "x1": (i + 1) / n, "y0": 0.0, "y1": 1.0,
                       "isBlank": False, "hasDecimalPoint": False} for i in range(n)]}


def _corpus(tmp_path: Path, corrections: list[dict] | None = None) -> tuple[Path, Path]:
    db = tmp_path / "c.sqlite"
    con = cdb.connect(db)
    con.executescript(cdb.SCHEMA)
    _add_still(con, "pump-900-a-ee.jpg", "train", "1111111111", 0)  # 10 cells, over half the pool
    _add_still(con, "pump-901-b-ee.jpg", "train", "11", 1)  # 2
    _add_still(con, "pump-902-c-ee.jpg", "train", "11", 2)  # 2
    _add_still(con, "pump-903-d-ee.jpg", "train", "11", 3)  # 2
    for row in corrections or []:
        con.execute("insert into corrections (at, build, kind, still, record, video, frame, field, proposedBy, "
                    "proposed, final, iou, inliers, extra) values (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    (row.get("at"), row.get("build"), row["kind"], row.get("still"), row.get("record"),
                     row.get("video"), row.get("frame"), row.get("field"), row.get("proposedBy"),
                     row.get("proposed"), row.get("final"), None, None, None))
    con.commit()
    con.close()
    strip = "strips/s000000.png"
    (tmp_path / "strips").mkdir()
    Image.new("RGB", (40, 20), "white").save(tmp_path / strip)
    export = {"windows": [_window("pump-900-a-ee.jpg", "1111111111", strip),
                          _window("pump-901-b-ee.jpg", "11", strip),
                          _window("pump-902-c-ee.jpg", "11", strip),
                          _window("pump-903-d-ee.jpg", "11", strip)]}
    manifest = tmp_path / "export.json"
    manifest.write_text(json.dumps(export))
    return db, manifest


def _run(tmp_path: Path, db: Path, manifest: Path, *extra: str) -> dict:
    out = tmp_path / "out"
    rc = realglyphs.main(["--export", str(manifest), "--out", str(out), "--db", str(db), *extra])
    assert rc == 0
    return json.loads((out / "manifest.json").read_text())


def test_cap_fixture_caps_a_dominant_source(tmp_path: Path) -> None:
    db, manifest = _corpus(tmp_path)
    m = _run(tmp_path, db, manifest, "--cap-fixture", "0.3")
    before, after = m["composition_before"], m["composition_after"]
    assert before["top_sources"][0] == ["pump-900-a-ee.jpg", 0.625], "no source over the cap: the test is vacuous"
    assert after["cells"] < before["cells"]
    assert max(share for _, share in after["top_sources"]) <= 0.3
    assert dict(after["top_sources"])["pump-900-a-ee.jpg"] < 10


def test_cap_fixture_leaves_a_pool_no_source_exceeds(tmp_path: Path) -> None:
    db, manifest = _corpus(tmp_path)
    m = _run(tmp_path, db, manifest, "--cap-fixture", "0.9")
    assert m["composition_after"]["cells"] == m["composition_before"]["cells"]


def test_hard_weight_triples_the_corrected_frame(tmp_path: Path) -> None:
    db, manifest = _corpus(tmp_path, corrections=[{
        "kind": "text", "still": "pump-900-a-ee.jpg", "field": "total", "proposedBy": "reader",
        "proposed": "1111111110", "final": "1111111111"}])
    m = _run(tmp_path, db, manifest, "--hard-weight", "3")
    meta = m["cell_meta"]
    a = [c for c in meta if c["fixture"] == "pump-900-a-ee.jpg"]
    b = [c for c in meta if c["fixture"] == "pump-901-b-ee.jpg"]
    assert len(a) == 30 and all(c["weight"] == 3 for c in a)
    assert len(b) == 2 and all(c["weight"] == 1 for c in b), "the weight leaked onto an uncorrected frame"

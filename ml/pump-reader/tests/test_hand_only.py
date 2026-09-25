"""The ``--hand-only`` pool selection: frame windows come only from frames the
owner placed by hand (``frames.verified = 1``); still windows are unchanged.

A synthetic corpus holds one still, one verified frame and one unverified frame,
all carrying the same two-cell label, cut through ``realglyphs.main`` against a
temp database. The full pool keeps every frame; ``--hand-only`` drops the
unverified frame's cells and keeps the still's and the verified frame's.

Oracle: the ``frames`` table's ``verified`` column and the manifest's
``hand_only`` flag.
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


def _add_still(con, name: str, text: str, ord_: int) -> None:
    con.execute("insert into fixtures values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (name, "pump", "unused", None, None, 40, 20, None, None, text, None, None, None, "train", ord_))
    con.execute("insert into entries (fixture, rotationCW, reviewed, notOnDisplay, csvDisagrees, tracking, keys, extra, ord) "
                "values (?,?,?,?,?,?,?,?,?)", (name, 0, 0, None, None, None, '["windows"]', "{}", ord_))
    con.execute("insert into windows (fixture, ord, field, text, legibility, quad, x0, y0, x1, y1) "
                "values (?,?,?,?,?,?,?,?,?,?)",
                (name, 0, "total", text, None, json.dumps(QUAD), 0.0, 0.0, 1.0, 1.0))


def _add_frame(con, record: str, frame: str, still: str, verified: bool, text: str) -> None:
    con.execute("insert into frames (record, frame, still, split, inliers, anchor, verified, keys, extra, ord) "
                "values (?,?,?,?,?,?,?,?,?,?)",
                (record, frame, still, "train", None, None, int(verified),
                 '["verified"]' if verified else "[]", "{}", 0))
    con.execute("insert into frame_windows (record, frame, ord, field, text, quad) values (?,?,?,?,?,?)",
                (record, frame, 0, "total", text, json.dumps(QUAD)))


def _window(fixture: str, frame: str | None, text: str, strip: str) -> dict:
    n = len(text)
    return {"fixture": fixture, "frame": frame, "field": "total", "text": text, "strip": strip,
            "cells": [{"x0": i / n, "x1": (i + 1) / n, "y0": 0.0, "y1": 1.0,
                       "isBlank": False, "hasDecimalPoint": False} for i in range(n)]}


def _corpus(tmp_path: Path) -> tuple[Path, Path]:
    db = tmp_path / "c.sqlite"
    con = cdb.connect(db)
    con.executescript(cdb.SCHEMA)
    _add_still(con, "pump-900-a-ee.jpg", "11", 0)
    _add_frame(con, "live-9000", "001.jpg", "pump-900-a-ee.jpg", True, "11")
    _add_frame(con, "live-9000", "002.jpg", "pump-900-a-ee.jpg", False, "11")
    con.commit()
    con.close()
    strip = "strips/s000000.png"
    (tmp_path / "strips").mkdir()
    Image.new("RGB", (40, 20), "white").save(tmp_path / strip)
    export = {"windows": [_window("pump-900-a-ee.jpg", None, "11", strip),
                          _window("pump-900-a-ee.jpg", "live-9000/001.jpg", "11", strip),
                          _window("pump-900-a-ee.jpg", "live-9000/002.jpg", "11", strip)]}
    manifest = tmp_path / "export.json"
    manifest.write_text(json.dumps(export))
    return db, manifest


def _run(tmp_path: Path, db: Path, manifest: Path, *extra: str) -> dict:
    out = tmp_path / "out"
    rc = realglyphs.main(["--export", str(manifest), "--out", str(out), "--db", str(db), *extra])
    assert rc == 0
    return json.loads((out / "manifest.json").read_text())


def _frames(meta: dict) -> set[str | None]:
    return {c["frame"] for c in meta["cell_meta"]}


def test_full_pool_keeps_every_frame(tmp_path: Path) -> None:
    db, manifest = _corpus(tmp_path)
    m = _run(tmp_path, db, manifest)
    assert m["hand_only"] is False
    assert _frames(m) == {None, "live-9000/001.jpg", "live-9000/002.jpg"}
    assert m["cells"] == 6, "still + verified + unverified, two cells each"


def test_hand_only_keeps_the_verified_frame_and_the_still(tmp_path: Path) -> None:
    db, manifest = _corpus(tmp_path)
    m = _run(tmp_path, db, manifest, "--hand-only")
    assert m["hand_only"] is True
    assert _frames(m) == {None, "live-9000/001.jpg"}
    assert "live-9000/002.jpg" not in _frames(m), "the unverified frame must be dropped"
    assert m["cells"] == 4, "still + verified frame, two cells each"

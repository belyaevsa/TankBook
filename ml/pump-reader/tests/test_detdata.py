"""The row detector's set built from the database: a train still and a labelled
video frame go to train, a heldout still goes to heldout, and the heldout still
never reaches train (decision 9)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

from pump_reader import detdata

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))
import corpus_db as cdb  # noqa: E402

QUAD = [[0.1, 0.1], [0.5, 0.1], [0.5, 0.5], [0.1, 0.5]]


def _png(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", (60, 40), "white").save(path)


def _add_still(con, name: str, split: str, path: Path, ord_: int) -> None:
    con.execute("insert into fixtures values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (name, "pump", str(path), None, None, 60, 40, None, None, None, None, None, None, split, ord_))
    con.execute("insert into entries (fixture, rotationCW, reviewed, notOnDisplay, csvDisagrees, tracking, keys, extra, ord) "
                "values (?,?,?,?,?,?,?,?,?)", (name, 0, 0, None, None, None, '["windows"]', "{}", ord_))
    con.execute("insert into windows (fixture, ord, field, text, legibility, quad, x0, y0, x1, y1) "
                "values (?,?,?,?,?,?,?,?,?,?)",
                (name, 0, "total", "1.23", None, json.dumps(QUAD), 0.1, 0.1, 0.5, 0.5))


def test_detdata_splits_train_and_heldout(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(detdata, "FRAMES", tmp_path / "frames")
    monkeypatch.setattr(detdata, "FIX", tmp_path / "fixtures")
    for sub in detdata.NEGATIVE_FOLDERS:
        (tmp_path / "fixtures" / sub).mkdir(parents=True)

    db = tmp_path / "c.sqlite"
    con = cdb.connect(db)
    con.executescript(cdb.SCHEMA)
    train_img, held_img = tmp_path / "train.png", tmp_path / "held.png"
    _png(train_img)
    _png(held_img)
    _add_still(con, "pump-900-train-ee.jpg", "train", train_img, 0)
    _add_still(con, "pump-901-held-ee.jpg", "heldout", held_img, 1)

    rec = "video-001-x"
    _png(tmp_path / "frames" / rec / "001.jpg")
    con.execute("insert into frames (record, frame, still, split, inliers, anchor, verified, keys, extra, ord) "
                "values (?,?,?,?,?,?,?,?,?,?)",
                (rec, "", rec, "train", None, None, None, '["_video","_split","frames"]',
                 '{"_video": "video-001-x", "_split": "train"}', None))
    con.execute("insert into frames (record, frame, still, split, inliers, anchor, verified, keys, extra, ord) values (?,?,?,?,?,?,?,?,?,?)",
                (rec, "001.jpg", rec, "train", 10, 1, 1, '["windows","inliers","anchor","verified"]', "{}", 0))
    con.execute("insert into frame_windows values (?,?,?,?,?,?,?)",
                (rec, "001.jpg", 0, "total", "1.23", json.dumps(QUAD), None))
    con.execute("insert into labels values (?,?,?,?,?)", (rec, "001.jpg", "total", "1.23", "owner"))
    con.commit()
    con.close()

    out = tmp_path / "out"
    assert detdata.main(["--out", str(out), "--db", str(db)]) == 0
    counts = json.loads((out / "counts.json").read_text())
    assert counts["train_stills"] == 1
    assert counts["heldout_stills"] == 1
    assert counts["video_frames"] == 1
    train = json.loads((out / "train" / "annotations.json").read_text())
    held = json.loads((out / "heldout" / "annotations.json").read_text())
    assert len(train) == 2 and len(held) == 1
    assert held[0]["source"] == "pump-901-held-ee.jpg"
    assert held[0]["source"] not in {r["source"] for r in train}

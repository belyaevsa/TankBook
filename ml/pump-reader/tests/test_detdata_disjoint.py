"""Decision 9 at the detector's export: a heldout still and every frame of a
record paired to it stay out of `train`, and a record the owner marked
`tracking = bad` contributes no frame either."""

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


def _add_still(con, name: str, split: str, path: Path, ord_: int, tracking: str | None = None) -> None:
    con.execute("insert into fixtures values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (name, "pump", str(path), None, None, 60, 40, None, None, None, None, None, None, split, ord_))
    con.execute("insert into entries (fixture, rotationCW, reviewed, notOnDisplay, csvDisagrees, tracking, keys, extra, ord) "
                "values (?,?,?,?,?,?,?,?,?)", (name, 0, 0, None, None, tracking, '["windows"]', "{}", ord_))
    con.execute("insert into windows (fixture, ord, field, text, legibility, quad, x0, y0, x1, y1) "
                "values (?,?,?,?,?,?,?,?,?,?)",
                (name, 0, "total", "1.23", None, json.dumps(QUAD), 0.1, 0.1, 0.5, 0.5))


def _add_record(con, record: str, still: str, split: str, frames_root: Path, frame: str = "001.jpg") -> None:
    """A tracked Live record (no `_video`): its meta row carries the still it is
    paired to and that still's split, exactly as `_write_frames` writes it."""
    _png(frames_root / record / frame)
    con.execute("insert into frames (record, frame, still, split, inliers, anchor, verified, keys, extra, ord) "
                "values (?,?,?,?,?,?,?,?,?,?)",
                (record, "", still, split, None, None, None, '["_still","_split","frames"]',
                 json.dumps({"_still": still, "_split": split}), None))
    con.execute("insert into frames (record, frame, still, split, inliers, anchor, verified, keys, extra, ord) "
                "values (?,?,?,?,?,?,?,?,?,?)",
                (record, frame, still, split, 10, 1, 1, '["windows","inliers","anchor","verified"]', "{}", 0))
    con.execute("insert into frame_windows values (?,?,?,?,?,?,?)",
                (record, frame, 0, "total", "1.23", json.dumps(QUAD), None))


def _sources(path: Path) -> set[str]:
    return {r["source"] for r in json.loads(path.read_text())}


def _export(tmp_path: Path, monkeypatch) -> tuple[Path, set[str], set[str]]:
    monkeypatch_frames = tmp_path / "frames"
    monkeypatch_fix = tmp_path / "fixtures"
    for sub in detdata.NEGATIVE_FOLDERS:
        (monkeypatch_fix / sub).mkdir(parents=True)
    monkeypatch.setattr(detdata, "FRAMES", monkeypatch_frames)
    monkeypatch.setattr(detdata, "FIX", monkeypatch_fix)

    db = tmp_path / "c.sqlite"
    con = cdb.connect(db)
    con.executescript(cdb.SCHEMA)
    for name in ("train.png", "held.png", "bad.png"):
        _png(tmp_path / name)
    _add_still(con, "pump-900-train-ee.jpg", "train", tmp_path / "train.png", 0)
    _add_still(con, "pump-901-held-ee.jpg", "heldout", tmp_path / "held.png", 1)
    _add_still(con, "pump-902-bad-ee.jpg", "train", tmp_path / "bad.png", 2, tracking="bad")
    _add_record(con, "live-9001", "pump-900-train-ee.jpg", "train", monkeypatch_frames)
    _add_record(con, "live-9002", "pump-901-held-ee.jpg", "heldout", monkeypatch_frames)
    _add_record(con, "live-9003", "pump-902-bad-ee.jpg", "train", monkeypatch_frames)
    con.commit()
    con.close()

    out = tmp_path / "out"
    assert detdata.main(["--out", str(out), "--db", str(db)]) == 0
    return out, _sources(out / "train" / "annotations.json"), _sources(out / "heldout" / "annotations.json")


def test_no_heldout_still_or_paired_frame_reaches_train(tmp_path: Path, monkeypatch) -> None:
    out, train, held = _export(tmp_path, monkeypatch)
    assert "pump-901-held-ee.jpg" in held
    assert "pump-901-held-ee.jpg" not in train
    assert not any(s.startswith("live-9002") for s in train), f"heldout record in train: {sorted(train)}"
    assert not (out / "train" / "pump-901-held-ee.jpg").exists()
    assert not any((out / "train").glob("live-9002-*"))
    assert "pump-900-train-ee.jpg" in train
    assert any(s.startswith("live-9001") for s in train)


def test_a_bad_tracked_record_contributes_no_frame(tmp_path: Path, monkeypatch) -> None:
    out, train, _ = _export(tmp_path, monkeypatch)
    assert not any(s.startswith("live-9003") for s in train), f"bad record in train: {sorted(train)}"
    assert not any((out / "train").glob("live-9003-*"))
    assert "pump-902-bad-ee.jpg" in train

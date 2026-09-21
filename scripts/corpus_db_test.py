#!/usr/bin/env python3
"""Round-trip and write-path tests for `corpus_db.py`.

    ml/pump-reader/.venv/bin/pytest scripts/corpus_db_test.py -q

The corpus is copied into a temp directory (the committed text files plus the
local `frames/`, which is gitignored; a synthetic record is added when it is
absent), the module's paths are pointed at the copy, and `import` -> `dump`
must leave every file byte-identical. The write path (`save_entry`,
`pin_frame`, `add_corrections`) is exercised on the same copy.
"""
from __future__ import annotations

import difflib
import json
import shutil
import sqlite3
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
import corpus_db as cdb  # noqa: E402

SRC = REPO / "Spike" / "ReceiptSpike" / "fixtures"
TEXT_FILES = (
    "pump/expected.csv", "pump/split.csv", "pump/windows.json",
    "receipts/expected.csv",
    "pump-live/videos.json", "pump-live/video-labels.json",
    "pump-live/README.md", "pump-live/corrections.jsonl",
)


def _synthetic_frames(frames: Path) -> None:
    """`frames/` is gitignored: on a checkout without it, one small record
    keeps the frames/readings dump covered."""
    record = frames / "synthetic-0001"
    record.mkdir(parents=True)
    (record / "windows.json").write_text(json.dumps({
        "_video": "synthetic-0001", "_reference": "001.jpg", "_anchors": ["001.jpg"], "_split": "train",
        "frames": {"001.jpg": {"windows": [{"field": "total", "text": "1.00",
                                            "quad": [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]]}],
                               "inliers": -1, "anchor": 1, "verified": True}},
        "_kept": 1, "_dropped": 0}, indent=1))
    (record / "readings.json").write_text(
        '{"001.jpg":{"closes":true,"liters":"1.00","total":"1.00"}}')


@pytest.fixture()
def corpus(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    fix = tmp_path / "Spike" / "ReceiptSpike" / "fixtures"
    for rel in TEXT_FILES:
        source = SRC / rel
        if source.exists():
            dest = fix / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, dest)
    frames_src = SRC / "pump-live" / "frames"
    frames = fix / "pump-live" / "frames"
    if frames_src.exists():
        for path in frames_src.glob("*/*.json"):
            dest = frames / path.parent.name / path.name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, dest)
    if not list(frames.glob("*/windows.json")):
        _synthetic_frames(frames)

    monkeypatch.setattr(cdb, "ROOT", tmp_path)
    monkeypatch.setattr(cdb, "FIX", fix)
    monkeypatch.setattr(cdb, "DB", fix / "corpus.sqlite")
    monkeypatch.setattr(cdb, "PUMP", fix / "pump")
    monkeypatch.setattr(cdb, "LIVE", fix / "pump-live")
    monkeypatch.setattr(cdb, "FRAMES", frames)
    monkeypatch.setattr(cdb, "WINDOWS_FILE", fix / "pump" / "windows.json")
    monkeypatch.setattr(cdb, "EXPECTED_FILE", fix / "pump" / "expected.csv")
    monkeypatch.setattr(cdb, "VIDEOS_FILE", fix / "pump-live" / "videos.json")
    monkeypatch.setattr(cdb, "LABELS_FILE", fix / "pump-live" / "video-labels.json")
    monkeypatch.setattr(cdb, "CORRECTIONS_FILE", fix / "pump-live" / "corrections.jsonl")
    cdb.import_corpus()
    return fix


def _snapshot(root: Path) -> dict[Path, bytes]:
    return {p.relative_to(root): p.read_bytes() for p in root.rglob("*")
            if p.is_file() and p.suffix in (".json", ".csv", ".jsonl")}


def _first_mismatch(a: bytes, b: bytes, label: str) -> str:
    diff = list(difflib.unified_diff(a.decode(errors="replace").splitlines(True),
                                     b.decode(errors="replace").splitlines(True),
                                     fromfile="on disk", tofile="dump", lineterm=""))[:20]
    return f"{label}\n" + "\n".join(diff)


def test_round_trip_is_byte_identical(corpus: Path) -> None:
    before = _snapshot(corpus)
    cdb.dump()
    after = _snapshot(corpus)
    # Every file the database carries must be dumped, not only the tables with rows.
    assert before.keys() <= after.keys(), f"dump dropped files: {set(before) - set(after)}"
    for rel, original in before.items():
        assert after[rel] == original, _first_mismatch(original, after[rel], str(rel))


def test_dump_covers_every_file_kind(corpus: Path) -> None:
    rendered = {p.relative_to(corpus) for p in cdb.render()}
    assert cdb.WINDOWS_FILE.relative_to(corpus) in rendered
    assert cdb.EXPECTED_FILE.relative_to(corpus) in rendered
    assert cdb.VIDEOS_FILE.relative_to(corpus) in rendered
    assert cdb.LABELS_FILE.relative_to(corpus) in rendered
    frames_rel = cdb.FRAMES.relative_to(corpus)
    assert any(p.name == "windows.json" and frames_rel in p.parents for p in rendered)
    assert any(p.name == "readings.json" and frames_rel in p.parents for p in rendered)


def test_save_entry_changes_only_that_block(corpus: Path) -> None:
    cdb.dump()
    before = json.loads(cdb.WINDOWS_FILE.read_text())
    name = next(k for k in before if not k.startswith("_") and before[k].get("windows"))
    entry = json.loads(json.dumps(before[name]))
    entry["windows"][0]["quad"] = [[0.11, 0.11], [0.22, 0.11], [0.22, 0.22], [0.11, 0.22]]
    cdb.save_entry(name, entry)
    cdb.dump()
    after = json.loads(cdb.WINDOWS_FILE.read_text())
    changed = [k for k in before if json.dumps(before[k]) != json.dumps(after[k])]
    assert changed == [name], f"changed blocks: {changed}"
    assert list(after) == list(before), "save_entry moved the entry in the file"
    assert after[name]["windows"][0]["quad"] == entry["windows"][0]["quad"]
    assert cdb.check() == []


def test_pin_frame_writes_verified_anchor_and_correction(corpus: Path) -> None:
    cdb.dump()
    # `pin_frame` keys the old windows by field, so a frame with two `board`
    # windows would report the second one as moved too; pick a frame whose
    # fields are unique so the assertion counts one correction.
    record = frame = ""
    for path in sorted(cdb.FRAMES.glob("*/windows.json")):
        tracked = json.loads(path.read_text())
        for name, entry in tracked.get("frames", {}).items():
            fields = [w["field"] for w in entry.get("windows", [])]
            if fields and len(fields) == len(set(fields)):
                record, frame = path.parent.name, name
                break
        if record:
            break
    assert record, "no tracked frame with unique field names"
    tracked = json.loads((cdb.FRAMES / record / "windows.json").read_text())
    windows = [{"field": w["field"], "quad": w["quad"]} for w in tracked["frames"][frame]["windows"]]
    windows[0]["quad"] = [[0.5, 0.5], [0.6, 0.5], [0.6, 0.6], [0.5, 0.6]]

    import sqlite3
    with sqlite3.connect(cdb.DB) as con:
        before = con.execute("select count(*) from corrections where kind = 'quad'").fetchone()[0]
    assert cdb.pin_frame(record, frame, windows) is True
    with sqlite3.connect(cdb.DB) as con:
        con.row_factory = sqlite3.Row
        row = con.execute("select verified, anchor, inliers from frames where record = ? and frame = ?",
                          (record, frame)).fetchone()
        after = con.execute("select count(*) from corrections where kind = 'quad'").fetchone()[0]
    assert row["verified"] == 1
    assert row["anchor"] == int(frame[:-4])
    assert after == before + 1

    cdb.dump()
    assert cdb.check() == []
    assert json.loads((cdb.FRAMES / record / "windows.json").read_text())["frames"][frame]["verified"] is True


def test_save_tracked_round_trips_the_record(corpus: Path) -> None:
    cdb.dump()
    record = next(p.parent.name for p in cdb.FRAMES.glob("*/windows.json")
                  if json.loads(p.read_text()).get("frames"))
    path = cdb.FRAMES / record / "windows.json"
    before = path.read_bytes()
    tracked = cdb.tracked(record)
    assert tracked and tracked["frames"], "an empty record would make this round trip vacuous"
    cdb.save_tracked(record, tracked)
    cdb.dump([path])
    assert path.read_bytes() == before
    # Non-vacuous: a moved quad must change the dumped file.
    frame = next(iter(tracked["frames"]))
    tracked["frames"][frame]["windows"][0]["quad"] = [[0.11, 0.11], [0.22, 0.11], [0.22, 0.22], [0.11, 0.22]]
    cdb.save_tracked(record, tracked)
    cdb.dump([path])
    assert path.read_bytes() != before
    assert cdb.check() == []


def test_save_live_anchor_replaces_one_frame(corpus: Path) -> None:
    cdb.dump()
    windows_json = json.loads(cdb.WINDOWS_FILE.read_text())
    still = next((k for k, v in windows_json.items()
                  if isinstance(v, dict) and v.get("liveAnchors")), None)
    if still is None:
        pytest.skip("no Live anchors in this corpus copy")
    before = windows_json[still]["liveAnchors"]
    record, frame = before[0]["record"], before[0]["frame"]
    windows = [{"field": w["field"], "quad": w["quad"]} for w in before[0]["windows"]]
    windows[0]["quad"] = [[0.9, 0.9], [0.95, 0.9], [0.95, 0.95], [0.9, 0.95]]
    anchors = cdb.save_live_anchor(still, record, frame, windows)
    assert anchors
    cdb.dump()
    after = json.loads(cdb.WINDOWS_FILE.read_text())
    got = next(a for a in after[still]["liveAnchors"] if a["record"] == record and a["frame"] == frame)
    assert got["windows"][0]["quad"] == windows[0]["quad"]
    assert len(after[still]["liveAnchors"]) == len(before)
    assert cdb.check() == []


def test_save_video_anchor_updates_the_reference(corpus: Path) -> None:
    cdb.dump()
    videos = json.loads(cdb.VIDEOS_FILE.read_text())
    stem = next(k for k in videos if not k.startswith("_"))
    windows = [{"field": w["field"], "quad": w["quad"]} for w in videos[stem]["windows"]]
    windows[0]["quad"] = [[0.1, 0.1], [0.2, 0.1], [0.2, 0.2], [0.1, 0.2]]
    cdb.save_video_anchor(stem, videos[stem]["reference"], windows)
    cdb.dump()
    after = json.loads(cdb.VIDEOS_FILE.read_text())
    assert after[stem]["windows"][0]["quad"] == windows[0]["quad"]
    assert cdb.check() == []


def test_import_keeps_gitignored_frames_when_files_absent(corpus: Path) -> None:
    cdb.dump()
    record = next(p.parent.name for p in cdb.FRAMES.glob("*/windows.json"))
    import sqlite3
    with sqlite3.connect(cdb.DB) as con:
        before = con.execute("select count(*) from frames").fetchone()[0]
    shutil.rmtree(cdb.FRAMES)
    cdb.import_corpus()
    with sqlite3.connect(cdb.DB) as con:
        after = con.execute("select count(*) from frames").fetchone()[0]
    assert after == before, "import blanked the frames the gitignored files cannot carry"
    cdb.dump()
    assert (cdb.FRAMES / record / "windows.json").exists()
    assert cdb.check() == []


def test_check_flags_a_hand_edit_and_dump_clears_it(corpus: Path) -> None:
    cdb.dump()
    assert cdb.check() == []
    text = cdb.WINDOWS_FILE.read_text().replace('"reviewed": true', '"reviewed": false', 1)
    cdb.WINDOWS_FILE.write_text(text)
    stale = cdb.check()
    assert stale and "windows.json" in stale[0]
    cdb.dump()
    assert cdb.check() == []


def test_corrections_round_trip(corpus: Path) -> None:
    cdb.add_corrections([{"kind": "quad", "record": "live-0001", "frame": "001.jpg", "field": "total",
                          "proposedBy": "tracker", "proposed": [[0.1, 0.1], [0.2, 0.1], [0.2, 0.2], [0.1, 0.2]],
                          "final": [[0.3, 0.3], [0.4, 0.3], [0.4, 0.4], [0.3, 0.4]], "iou": 0.2, "inliers": 40}])
    cdb.dump()
    rows = [json.loads(line) for line in cdb.CORRECTIONS_FILE.read_text().splitlines() if line.strip()]
    line = next(r for r in rows if r.get("record") == "live-0001")
    assert line["kind"] == "quad"
    assert line["proposed"] == [[0.1, 0.1], [0.2, 0.1], [0.2, 0.2], [0.1, 0.2]]
    first = cdb.CORRECTIONS_FILE.read_bytes()
    cdb.import_corpus()
    cdb.dump()
    assert cdb.CORRECTIONS_FILE.read_bytes() == first


# ---------------------------------------------------------------------------
# import-readings: the Swift writer's path
# ---------------------------------------------------------------------------

def _staging(tmp_path: Path, record: str, readings: dict, labels: dict) -> Path:
    path = tmp_path / "video-read" / f"{record}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"record": record, "readings": readings, "labels": labels}, sort_keys=True))
    return path


def _unowned_record(corpus: Path) -> str:
    """A tracked record with readings and no owner label, so a staged arithmetic
    label cannot collide with one. Every record with a `readings.json` is a
    video stem; some have no labels at all."""
    labels = cdb.labels()
    for path in sorted(cdb.FRAMES.glob("*/readings.json")):
        frames = labels.get(path.parent.name, {})
        if any(f.get("source") == "owner" for f in frames.values()):
            continue
        return path.parent.name
    raise AssertionError("no unowned tracked record in this corpus copy")


def _lexical_readings(path: Path) -> bool:
    """The Swift writer emits readings with sorted keys, so its frame order is
    lexical; the byte-identity test needs a committed file in that order."""
    keys = list(json.loads(path.read_bytes()))
    return keys == sorted(keys)


def test_import_readings_writes_readings_and_arithmetic_labels(corpus: Path) -> None:
    cdb.dump()
    stem = _unowned_record(corpus)
    readings = {"001.jpg": {"closes": True, "liters": "1.00", "total": "1.00"},
                "002.jpg": {"closes": False, "liters": "", "total": ""}}
    labels = {"001.jpg": {"liters": "1.00", "source": "arithmetic", "total": "1.00", "unitPrice": "1.000"}}
    cdb.import_readings(_staging(corpus.parent, stem, readings, labels))
    assert json.loads((cdb.FRAMES / stem / "readings.json").read_text()) == readings
    with sqlite3.connect(cdb.DB) as con:
        con.row_factory = sqlite3.Row
        rows = con.execute("select frame, field, text, closes from readings where record = ? order by frame, rowid",
                           (stem,)).fetchall()
        stored = {r["frame"]: {"closes": bool(r["closes"])} for r in rows}
        for r in rows:
            stored[r["frame"]][r["field"]] = r["text"]
    assert stored == readings, "readings did not round-trip through the database"
    dumped = json.loads(cdb.LABELS_FILE.read_text())[stem]
    assert dumped["001.jpg"] == labels["001.jpg"]
    assert "002.jpg" not in dumped, "a non-closing frame was labelled"
    assert cdb.check() == []


def test_import_readings_keeps_an_owner_label(corpus: Path) -> None:
    cdb.dump()
    stem = _unowned_record(corpus)
    owner = {"total": "9.99", "liters": "9.99", "unitPrice": "1.000", "source": "owner"}
    cdb.save_labels(stem, {"001.jpg": owner})
    cdb.dump()
    readings = {"001.jpg": {"closes": True, "liters": "1.00", "total": "1.00"},
                "002.jpg": {"closes": True, "liters": "2.00", "total": "2.00"}}
    labels = {"001.jpg": {"liters": "1.00", "source": "arithmetic", "total": "1.00", "unitPrice": "1.000"},
              "002.jpg": {"liters": "2.00", "source": "arithmetic", "total": "2.00", "unitPrice": "1.000"}}
    cdb.import_readings(_staging(corpus.parent, stem, readings, labels))
    dumped = json.loads(cdb.LABELS_FILE.read_text())[stem]
    assert dumped["001.jpg"] == owner, "an arithmetic row overwrote an owner label"
    assert dumped["002.jpg"]["source"] == "arithmetic"
    with sqlite3.connect(cdb.DB) as con:
        owner_rows = con.execute("select count(*) from labels where video = ? and frame = '001.jpg' and source = 'owner'",
                                 (stem,)).fetchone()[0]
        arithmetic_rows = con.execute("select count(*) from labels where video = ? and frame = '001.jpg' and source = 'arithmetic'",
                                      (stem,)).fetchone()[0]
    assert owner_rows == len(owner) - 1 and arithmetic_rows == 0
    assert cdb.check() == []


def test_import_readings_dump_matches_the_committed_corpus(corpus: Path) -> None:
    """The committed `video-labels.json` / `readings.json` are the old writers'
    output. Re-importing a record's readings and arithmetic labels and dumping
    must reproduce them byte for byte, and the record's data must equal what
    `git show HEAD` has for it."""
    cdb.dump()
    labels = cdb.labels()
    stem = next(k for k, frames in labels.items()
                if any(f.get("source") == "owner" for f in frames.values())
                and any(f.get("source") == "arithmetic" for f in frames.values())
                and (cdb.FRAMES / k / "readings.json").exists()
                and _lexical_readings(cdb.FRAMES / k / "readings.json")
                and b'": ' not in (cdb.FRAMES / k / "readings.json").read_bytes()[:200])
    readings_path = cdb.FRAMES / stem / "readings.json"
    before_labels = cdb.LABELS_FILE.read_bytes()
    before_readings = readings_path.read_bytes()
    readings = json.loads(before_readings)
    arithmetic = {frame: fields for frame, fields in labels[stem].items()
                  if fields.get("source") == "arithmetic"}
    assert arithmetic, "no arithmetic labels to re-import would make this vacuous"
    cdb.import_readings(_staging(corpus.parent, stem, readings, arithmetic))
    assert cdb.LABELS_FILE.read_bytes() == before_labels, "the labels dump changed the committed file"
    assert readings_path.read_bytes() == before_readings, "the readings dump changed the committed file"
    assert cdb.check() == []
    head = subprocess.run(["git", "show", "HEAD:Spike/ReceiptSpike/fixtures/pump-live/video-labels.json"],
                          cwd=REPO, capture_output=True, check=True).stdout
    head_labels = json.loads(head)
    assert json.loads(cdb.LABELS_FILE.read_text())[stem] == head_labels[stem], "the data differs from HEAD"




def test_migrate_adds_s3_key_without_losing_rows(corpus: Path) -> None:
    cdb.dump()
    with sqlite3.connect(cdb.DB) as con:
        con.execute("alter table frames drop column s3_key")
        con.execute("update meta set value = '2' where key = 'schema_version'")
        before = con.execute("select count(*) from frames").fetchone()[0]
    assert before > 0, "an empty frames table would make this vacuous"
    assert cdb.migrate() is True
    with sqlite3.connect(cdb.DB) as con:
        columns = {r[1] for r in con.execute("pragma table_info(frames)")}
        after = con.execute("select count(*) from frames").fetchone()[0]
        version = con.execute("select value from meta where key = 'schema_version'").fetchone()[0]
    assert "s3_key" in columns
    assert after == before, "the migration lost frames rows"
    assert version == cdb.SCHEMA_VERSION


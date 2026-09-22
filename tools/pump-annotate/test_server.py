"""The annotator server's split, heldout-badge and reviewed-clearing routes.

Every test runs the real server against a COPY of `corpus.sqlite` (the
`PUMP_ANNOTATE_DB` env var redirects the database and suppresses the JSON
dump), so no test touches the checkout's corpus.

    ml/pump-reader/.venv/bin/python -m pytest tools/pump-annotate -q
"""
from __future__ import annotations

import csv
import json
import os
import socket
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
TOOL = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "scripts"))
SERVER = TOOL / "server.py"
REAL_DB = ROOT / "Spike" / "ReceiptSpike" / "fixtures" / "corpus.sqlite"
SPLIT_CSV = ROOT / "Spike" / "ReceiptSpike" / "fixtures" / "pump" / "split.csv"
HELDOUT = "pump-186-tatsuno-amber-led-night-third-party-ru.jpg"


def copy_db(dest: Path) -> Path:
    """A consistent copy (WAL included) via SQLite's own backup, brought to the
    schema the current writer inserts. The live database may predate a nullable
    column the sibling task is adding, and the server's redirected run skips the
    checkout's own migrate() so it cannot write to it."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    src = sqlite3.connect(f"file:{REAL_DB}?mode=ro", uri=True)  # never write the real corpus
    dst = sqlite3.connect(str(dest))
    try:
        with dst:
            src.backup(dst)
    finally:
        src.close()
        dst.close()
    sync_windows_schema(dest)
    return dest


def sync_windows_schema(db: Path) -> None:
    """Add every nullable `windows` column the code's SCHEMA declares but the
    copy lacks, so the server's write path works against a pre-migration copy."""
    import corpus_db

    create = "create table windows (" + corpus_db.SCHEMA.split("create table windows (", 1)[1].split(";", 1)[0]
    mem = sqlite3.connect(":memory:")
    mem.execute(create)
    declared = {r[1]: (r[2], r[3]) for r in mem.execute("pragma table_info(windows)")}  # name -> (type, notnull)
    mem.close()
    with sqlite3.connect(str(db)) as con:
        have = {r[1] for r in con.execute("pragma table_info(windows)")}
        for col, (typ, notnull) in declared.items():
            if col not in have and not notnull:
                con.execute(f"alter table windows add column {col} {typ}")


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def http_json(method: str, url: str, body: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Content-Type": "application/json"} if data else {})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())


@pytest.fixture
def server(tmp_path):
    db = copy_db(tmp_path / "corpus.sqlite")
    port = free_port()
    log_path = tmp_path / "server.log"
    log = log_path.open("w")
    proc = subprocess.Popen([sys.executable, str(SERVER), str(port)],
                            env={**os.environ, "PUMP_ANNOTATE_DB": str(db)},
                            stdout=log, stderr=subprocess.STDOUT)
    base = f"http://127.0.0.1:{port}"
    deadline = time.time() + 30
    while True:
        if proc.poll() is not None:
            log.flush()
            raise RuntimeError(f"server exited {proc.returncode}:\n{log_path.read_text()}")
        try:
            http_json("GET", base + "/api/fixtures")
            break
        except (urllib.error.URLError, ConnectionError):
            if time.time() > deadline:
                raise RuntimeError("server did not come up") from None
            time.sleep(0.1)
    yield base, db
    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
    log.close()


def db_reviewed(db: Path, name: str) -> int:
    with sqlite3.connect(str(db), timeout=5.0) as con:
        return con.execute("select reviewed from entries where fixture = ?", (name,)).fetchone()[0]


def db_windows(db: Path, name: str) -> list[dict]:
    """The stored entry's windows, exactly as the server compares them."""
    with sqlite3.connect(str(db), timeout=5.0) as con:
        rows = con.execute("select field, text, legibility, quad from windows "
                           "where fixture = ? order by ord", (name,)).fetchall()
    out = []
    for field, text, legibility, quad in rows:
        w = {"field": field, "text": text, "quad": json.loads(quad)}
        if legibility:
            w["legibility"] = legibility
        out.append(w)
    return out


def test_fixtures_route_carries_split(server):
    base, db = server
    fixtures = http_json("GET", base + "/api/fixtures")
    stills = {x["name"]: x for x in fixtures if not x.get("video")}
    with SPLIT_CSV.open() as f:
        oracle = {r["filename"]: r["split"] for r in csv.DictReader(f)}
    with sqlite3.connect(str(db)) as con:
        stored = {r[0]: r[1] for r in con.execute("select name, split from fixtures where kind = 'pump'")}
    # the database and the frozen draw agree
    for name, split in oracle.items():
        assert stored.get(name) == split, name
    heldout = [n for n, x in stills.items() if x.get("split") == "heldout"]
    train = [n for n, x in stills.items() if x.get("split") == "train"]
    assert heldout, "no heldout still in the fixtures route"
    assert train, "no train still in the fixtures route"
    for name, x in stills.items():
        assert x["split"] == stored.get(name, "train"), name


def test_reviewed_heldout_entry_with_moved_quad_stores_reviewed_false(server):
    base, db = server
    assert db_reviewed(db, HELDOUT) == 1
    body = {"windows": db_windows(db, HELDOUT), "reviewed": True}
    body["windows"][0]["quad"][0][0] = round(body["windows"][0]["quad"][0][0] + 0.01, 4)
    resp = http_json("PUT", base + "/api/entry/" + HELDOUT, body)
    assert resp.get("reviewedCleared") is True
    assert db_reviewed(db, HELDOUT) == 0


def test_identical_windows_keep_reviewed(server):
    base, db = server
    assert db_reviewed(db, HELDOUT) == 1
    body = {"windows": db_windows(db, HELDOUT), "reviewed": True}
    resp = http_json("PUT", base + "/api/entry/" + HELDOUT, body)
    assert not resp.get("reviewedCleared")
    assert db_reviewed(db, HELDOUT) == 1


# ---------------------------------------------------------------------------
# PU.45: keyframes, interpolation and per-frame confidence for video labels.
#
# The clip is the Batch 5 oracle (`pump-live/README.md`): price `1.729`, and the
# two keyframes below are its measured ends (1.84 x 1.729 = 3.18,
# 3.00 x 1.729 = 5.19). The tests assert against the labels table of the DB copy
# the fixture redirected the server to, never the checkout's files.
# ---------------------------------------------------------------------------

VIDEO = "video-001-wayne-circlek-running-display-ee"
PRICE = "1.729"
RUN = ["001.jpg", "002.jpg", "003.jpg", "004.jpg", "005.jpg"]
KEY_A = {"total": "3.18", "liters": "1.84", "unitPrice": PRICE}
KEY_B = {"total": "5.19", "liters": "3.00", "unitPrice": PRICE}


def db_labels(db: Path, stem: str) -> dict[str, dict]:
    with sqlite3.connect(str(db), timeout=5.0) as con:
        rows = con.execute("select frame, field, text, source from labels where video = ?", (stem,)).fetchall()
    out: dict[str, dict] = {}
    for frame, field, text, source in rows:
        if frame == "":
            continue
        fields = out.setdefault(frame, {})
        fields[field] = text
        if source is not None:
            fields["source"] = source
    return out


def db_ledger(db: Path, stem: str) -> list[dict]:
    with sqlite3.connect(str(db), timeout=5.0) as con:
        rows = con.execute("select kind, extra from corrections where video = ? order by rowid", (stem,)).fetchall()
    out = []
    for kind, extra in rows:
        row = {"kind": kind}
        row.update(json.loads(extra) if extra else {})
        out.append(row)
    return out


def clear_labels(db: Path, stem: str) -> None:
    with sqlite3.connect(str(db), timeout=5.0) as con:
        con.execute("delete from labels where video = ?", (stem,))
        con.commit()


def put_label(base: str, frame: str, body: dict) -> dict:
    return http_json("PUT", f"{base}/api/video-label/{VIDEO}/{frame}", body)


def label_keyframes(base: str) -> None:
    put_label(base, "001.jpg", {**KEY_A, "run": RUN, "keyframe": True})
    put_label(base, "005.jpg", {**KEY_B, "run": RUN, "keyframe": True})


def test_interpolation_between_two_keyframes_yields_only_closing_pairs(server):
    base, db = server
    clear_labels(db, VIDEO)
    label_keyframes(base)
    labels = db_labels(db, VIDEO)
    assert labels["001.jpg"]["source"] == "owner"
    assert labels["005.jpg"]["source"] == "owner"
    last_l = last_t = -1.0
    for frame in ("002.jpg", "003.jpg", "004.jpg"):
        lab = labels[frame]
        # the named mutation (write `source: owner`) turns this red
        assert lab["source"] == "interpolated", (frame, lab)
        liters, total = float(lab["liters"]), float(lab["total"])
        assert round(liters * float(PRICE), 2) == total, (frame, liters, total)
        assert liters >= last_l and total >= last_t, (frame, liters, total)
        last_l, last_t = liters, total


def test_confirmed_run_writes_owner_per_frame_and_interpolated_nowhere(server):
    base, db = server
    clear_labels(db, VIDEO)
    for frame in ("002.jpg", "003.jpg", "004.jpg"):
        put_label(base, frame, {**KEY_A, "run": RUN, "confirm": True})
    labels = db_labels(db, VIDEO)
    for frame in ("002.jpg", "003.jpg", "004.jpg"):
        assert labels[frame]["source"] == "owner", (frame, labels[frame])
        assert labels[frame].get("via") == "run", (frame, labels[frame])
    assert all(lab.get("source") != "interpolated" for lab in labels.values())
    confirmed = sum(row.get("confirmed", 0) for row in db_ledger(db, VIDEO))
    assert confirmed == 3, db_ledger(db, VIDEO)


def test_keyframe_change_invalidates(server):
    base, db = server
    clear_labels(db, VIDEO)
    label_keyframes(base)
    assert db_labels(db, VIDEO)["003.jpg"]["source"] == "interpolated"
    # A changed keyframe is a changed pair: the middle is invalidated, left
    # unlabelled for attention rather than silently refilled with the new pair.
    put_label(base, "005.jpg", {**KEY_B, "total": "5.30", "liters": "3.06", "run": RUN})
    labels = db_labels(db, VIDEO)
    assert labels["005.jpg"]["source"] == "owner"
    for frame in ("002.jpg", "003.jpg", "004.jpg"):
        assert labels.get(frame, {}).get("source") != "interpolated", (frame, labels.get(frame))


# ---------------------------------------------------------------------------
# PU.44: derived text conventions and per-window provenance.
#
# The provenance is written by the PAGE (the server cannot know the zoom), so
# the Python tests cover the store: the import defaults, the `clean_entry`
# passthrough and the dump order. The page's own writes are the headless tests
# under `ml/pump-reader/.out/pu44/`.
# ---------------------------------------------------------------------------


@pytest.fixture
def db_copy(tmp_path: Path) -> Path:
    return copy_db(tmp_path / "corpus.sqlite")


def _minimal_corpus(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """A scratch fixtures tree with one still - enough for import/dump."""
    import corpus_db as cdb

    fix = tmp_path / "Spike" / "ReceiptSpike" / "fixtures"
    pump = fix / "pump"
    pump.mkdir(parents=True)
    name = "pump-032-gilbarco-circlek-ee-clean.jpg"
    (pump / "windows.json").write_text(json.dumps({name: {"windows": [
        {"field": "total", "text": "0034,36", "quad": [[0.1, 0.1], [0.2, 0.1], [0.2, 0.2], [0.1, 0.2]],
         "placedBy": "hand", "zoom": 1.4},
        {"field": "board", "text": "1.969", "quad": [[0.3, 0.3], [0.4, 0.3], [0.4, 0.4], [0.3, 0.4]],
         "placedBy": "auto", "zoom": 1.0},
    ], "reviewed": True}}, indent=1) + "\n")
    (pump / "expected.csv").write_text(
        "filename,liters,unitPrice,total,fuelKind,currency\n" + name + ",10.00,3.436,34.36,,\n")
    monkeypatch.setattr(cdb, "ROOT", tmp_path)
    monkeypatch.setattr(cdb, "FIX", fix)
    monkeypatch.setattr(cdb, "DB", fix / "corpus.sqlite")
    monkeypatch.setattr(cdb, "PUMP", pump)
    monkeypatch.setattr(cdb, "LIVE", fix / "pump-live")
    monkeypatch.setattr(cdb, "FRAMES", fix / "pump-live" / "frames")
    monkeypatch.setattr(cdb, "WINDOWS_FILE", pump / "windows.json")
    monkeypatch.setattr(cdb, "EXPECTED_FILE", pump / "expected.csv")
    monkeypatch.setattr(cdb, "VIDEOS_FILE", fix / "pump-live" / "videos.json")
    monkeypatch.setattr(cdb, "LABELS_FILE", fix / "pump-live" / "video-labels.json")
    monkeypatch.setattr(cdb, "CORRECTIONS_FILE", fix / "pump-live" / "corrections.jsonl")
    cdb.import_corpus()
    return cdb, name, pump / "windows.json"


def test_placed_by_zoom_round_trip(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    cdb, name, path = _minimal_corpus(tmp_path, monkeypatch)
    before = path.read_bytes()
    cdb.dump([path])
    assert path.read_bytes() == before, "import -> dump changed the placedBy/zoom text"
    # The save path: `clean_entry` passes both through and the dump keeps them.
    # Removing those two lines (the named mutation) makes this go red.
    entry = cdb.entry(name)
    entry["windows"][0]["placedBy"] = "reader"
    entry["windows"][0]["zoom"] = 1.4
    cdb.save_entry(name, entry)
    cdb.dump([path])
    text = path.read_text()
    assert '"placedBy": "reader"' in text, "clean_entry dropped placedBy"
    assert '"zoom": 1.4' in text, "clean_entry dropped zoom"
    keys = list(json.loads(text)[name]["windows"][0])
    assert keys.index("placedBy") > keys.index("quad")
    assert keys.index("zoom") == keys.index("placedBy") + 1


def test_import_defaults_placed_by(db_copy: Path) -> None:
    import corpus_db as cdb

    assert cdb.default_placed_by("pump-032-gilbarco-circlek-ee-clean.jpg") == "hand"
    assert cdb.default_placed_by("pump-250-gilbarco-circlek-peetri-pump7-3590l-2099-ee.jpg") == "auto"
    assert cdb.default_placed_by("pump-032-gilbarco-circlek-ee-clean.jpg", pending=True) == "auto"
    # The corpus assertion is about the IMPORT, not about which stills are
    # auto today: an auto-placed still whose boxes the owner then adjusts
    # carries both provenances, which is the annotator working as intended.
    # What must hold is that every window has one.
    with sqlite3.connect(str(db_copy)) as con:
        placed = {r[0] for r in con.execute("select distinct coalesce(placed_by, '') from windows")}
        missing = con.execute("select count(*) from windows where placed_by is null or placed_by = ''").fetchone()[0]
    assert missing == 0, f"{missing} imported windows carry no placedBy"
    assert {"auto", "hand"} <= placed, f"the imported corpus carries both defaults: {placed}"


def test_board_text_validator(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys) -> None:
    import importlib.util

    spec = importlib.util.spec_from_file_location("pump_windows_check", ROOT / "scripts" / "pump-windows-check.py")
    pwc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pwc)
    assert pwc.board_problem("abc") is not None
    assert pwc.board_problem("1.969") is None
    assert pwc.board_problem("") is None
    assert pwc.board_problem("-00-") is None  # pump-263's idle/closed marker
    fix = tmp_path / "pump"
    fix.mkdir()
    name = "pump-032-gilbarco-circlek-ee-clean.jpg"

    def write(board: str) -> None:
        (fix / "windows.json").write_text(json.dumps({name: {
            "windows": [
                {"field": "total", "text": "34,36", "quad": [[0.1, 0.1], [0.2, 0.1], [0.2, 0.2], [0.1, 0.2]]},
                {"field": "board", "text": board, "quad": [[0.3, 0.3], [0.4, 0.3], [0.4, 0.4], [0.3, 0.4]]}],
            "notOnDisplay": ["liters", "unitPrice"]}}, indent=1) + "\n")
        (fix / "expected.csv").write_text(
            "filename,liters,unitPrice,total,fuelKind,currency\n" + name + ",10.00,3.436,34.36,,\n")

    monkeypatch.setattr(pwc, "FIX", fix)
    monkeypatch.setattr(sys, "argv", ["pump-windows-check.py"])
    write("abc")
    assert pwc.main() == 0  # without --check the checker reports, never exits non-zero
    out = capsys.readouterr().out
    assert "board" in out and name in out, out
    write("1.969")
    assert pwc.main() == 0
    assert "0 problems" in capsys.readouterr().out


def test_migrate_adds_placed_by_and_backfills(tmp_path: Path) -> None:
    import corpus_db as cdb

    db = tmp_path / "old.sqlite"
    src = sqlite3.connect(str(REAL_DB))
    dst = sqlite3.connect(str(db))
    try:
        with dst:
            src.backup(dst)
    finally:
        src.close()
        dst.close()
    with sqlite3.connect(str(db)) as con:
        con.execute("alter table windows drop column placed_by")
        con.execute("alter table windows drop column zoom")
        con.execute("update meta set value = '3' where key = 'schema_version'")
        before = con.execute("select count(*) from windows").fetchone()[0]
    assert before > 0, "an empty windows table would make this vacuous"
    assert cdb.migrate(db) is True
    with sqlite3.connect(str(db)) as con:
        cols = {r[1] for r in con.execute("pragma table_info(windows)")}
        version = con.execute("select value from meta where key = 'schema_version'").fetchone()[0]
        nulls = con.execute("select count(*) from windows where placed_by is null").fetchone()[0]
        auto = {r[0] for r in con.execute("select distinct fixture from windows where placed_by = 'auto'")}
    assert {"placed_by", "zoom"} <= cols
    assert version == cdb.SCHEMA_VERSION
    assert nulls == 0, "the migration left windows without provenance"
    assert auto and all(244 <= int(n.split("-")[1]) <= 281 for n in auto), auto


# ---------------------------------------------------------------------------
# PU.50: the compare view. Two models on one still, side by side.
#
# The compare route runs the real `pump-read` twice, so the tests name a still
# whose CSV row they know and read the verdict back against it. The disagreement
# route is pure: it is fed stubbed replies and never runs a model.
# ---------------------------------------------------------------------------

COMPARE_STILL = "pump-032-gilbarco-circlek-ee-clean.jpg"


def http_post_json(url: str, body: dict, timeout: int = 900):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def expected_row(still: str) -> dict:
    with (ROOT / "Spike" / "ReceiptSpike" / "fixtures" / "pump" / "expected.csv").open() as f:
        return next(r for r in csv.DictReader(f) if r["filename"] == still)


def test_compare_route_returns_both_replies_and_verdict(server):
    base, _ = server
    detectors = http_json("GET", base + "/api/detectors")
    classifiers = http_json("GET", base + "/api/classifiers")
    assert len(detectors) >= 2, "the compare view needs two detectors to compare"
    assert classifiers, "no classifier on this machine"
    det_a = next((d for d in detectors if d["shipped"]), detectors[0])["path"]
    det_b = next(d for d in detectors if d["path"] != det_a)["path"]
    cls = next((c for c in classifiers if c["shipped"]), classifiers[0])["path"]
    body = {"image": COMPARE_STILL, "detectorA": det_a, "detectorB": det_b,
            "classifierA": cls, "classifierB": cls, "cache": False}
    res = http_post_json(base + "/api/compare", body)
    for side in ("a", "b"):
        assert isinstance(res[side]["reply"].get("committed"), dict), (side, res[side])
        assert res[side]["detector"]["path"] in (det_a, det_b)
    # The oracle: the CSV row the test named, per field, with A and B beside it.
    row = expected_row(COMPARE_STILL)
    for field in ("total", "liters", "unitPrice"):
        cell = res["verdict"][field]
        assert cell["expected"] == row[field], (field, cell, row)
        assert cell["a"] == res["a"]["reply"]["committed"].get(field)
        assert cell["b"] == res["b"]["reply"]["committed"].get(field)
        assert cell["aVerdict"] in ("✓", "✗", "–")
        assert cell["bVerdict"] in ("✓", "✗", "–")


def test_compare_unknown_model_refused(server):
    base, _ = server
    body = {"image": COMPARE_STILL, "detectorA": "not/a/detector.mlmodel",
            "detectorB": "not/a/detector.mlmodel"}
    with pytest.raises(urllib.error.HTTPError) as err:
        http_post_json(base + "/api/compare", body)
    assert err.value.code == 400


def test_compare_disagreement_route_lists_only_differing(server):
    base, _ = server
    same = {"committed": {"total": "20.02", "liters": "11.38", "unitPrice": "1.759"}}
    other = {"committed": {"total": "20.02", "liters": "11.38", "unitPrice": "1.75"}}
    nulls = {"committed": {"total": None, "liters": None, "unitPrice": None}}
    pairs = [{"still": "agrees", "a": same, "b": dict(same)},
             {"still": "differs", "a": same, "b": other},
             {"still": "abstains", "a": same, "b": nulls}]
    res = http_post_json(base + "/api/compare/disagree", {"pairs": pairs})
    names = [r["still"] for r in res["rows"]]
    assert names == ["differs", "abstains"], names
    assert res["rows"][0]["a"] == ["20.02", "11.38", "1.759"]
    assert res["rows"][0]["b"] == ["20.02", "11.38", "1.75"]


def _server_module(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """The server's pure functions, imported with the database redirected so
    the import cannot reach the checkout's corpus."""
    import importlib.util
    monkeypatch.setenv("PUMP_ANNOTATE_DB", str(copy_db(tmp_path / "corpus.sqlite")))
    spec = importlib.util.spec_from_file_location("pump_annotate_server", SERVER)
    module = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(TOOL))
    spec.loader.exec_module(module)
    return module


def test_presence_counts_kept_dropped_missed(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    server = _server_module(tmp_path, monkeypatch)
    box = lambda x0, y0, x1, y1: [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
    hand = [{"field": "total", "quad": box(0.1, 0.1, 0.5, 0.2)},
            {"field": "liters", "quad": box(0.1, 0.3, 0.5, 0.4)},
            {"field": "unitPrice", "quad": box(0.1, 0.5, 0.5, 0.6)},
            {"field": "board", "quad": box(0.7, 0.1, 0.8, 0.2)}]
    reply = {"candidates": [
        {"quad": box(0.11, 0.1, 0.5, 0.21), "kept": True},    # over total: kept
        {"quad": box(0.1, 0.31, 0.49, 0.4), "kept": False},   # over liters: dropped
        {"quad": box(0.7, 0.1, 0.8, 0.2), "kept": True},      # over the board: not a transaction row
    ]}
    # The price has no candidate over it; the board never counts.
    assert server.presence_counts(hand, reply) == {"kept": 1, "dropped": 1, "missed": 1}
    # A kept and a dropped candidate over the same row: the row was kept.
    reply["candidates"].append({"quad": box(0.1, 0.1, 0.5, 0.2), "kept": False})
    assert server.presence_counts(hand, reply)["kept"] == 1


def test_compare_passes_the_stills_currency(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    # Without the currency the reader's pair tier has no price band and
    # refuses a total + volume pair, so compare under-reported what the app
    # commits (decision 11).
    server = _server_module(tmp_path, monkeypatch)
    with (ROOT / "Spike" / "ReceiptSpike" / "fixtures" / "pump" / "expected.csv").open() as f:
        row = next(r for r in csv.DictReader(f) if r["currency"])
    assert server.image_currency(row["filename"]) == row["currency"]
    assert server.image_currency("frame/video-001/000.jpg") is None

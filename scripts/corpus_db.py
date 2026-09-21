#!/usr/bin/env python3
"""The corpus as one SQLite file - `Spike/ReceiptSpike/fixtures/corpus.sqlite`.

SQLite-first (product owner, 2026-09-21): the database is the canonical write
store and the text files are a deterministic dump of it, committed beside it so
diffs stay readable and the Swift ratchets keep reading files unchanged.

    scripts/corpus_db.py import   # files -> corpus.sqlite (the old `build`)
    scripts/corpus_db.py dump     # corpus.sqlite -> the seven text files
    scripts/corpus_db.py check    # exit 1 when a file differs from the dump
    scripts/corpus_db.py import-readings <staging.json>   # the Swift reader's write path
    scripts/corpus_db.py sql "select field, count(*) from windows group by 1"

`import` reads `pump/windows.json`, `pump/expected.csv`,
`pump-live/videos.json`, `pump-live/video-labels.json`,
`pump-live/frames/<stem>/windows.json`, `pump-live/frames/<stem>/readings.json`
and `pump-live/corrections.jsonl`; `dump` writes exactly those, in the byte
format the old writers used, so `import` followed by `dump` on an unchanged
corpus leaves `git diff Spike/` empty. Values that have no column live in an
`extra` JSON column on their table, and record-level tables also carry a `keys`
column - the original top-level key order - so the dump loses nothing.

`import-readings` is the Swift reader's write path: the test stages one
record's readings and its arithmetic labels as a JSON file, this writes
`readings` and `labels` in one transaction (an owner label is never
overwritten) and dumps the two files. `frames.s3_key` records where the
gitignored frame JPEGs live in the bucket; the dump does not carry it, so the
text files stay byte-identical.

The tables the report and the annotator read (`fixtures`, `entries`,
`windows`, `media`, `pairs`) are unchanged apart from `entries.tracking` and
the two new columns. `pump_reader.track` writes `frames` / `frame_windows`
through `save_tracked` and dumps the record's file; `import_frames` remains
only for a folder tracked before that move. The Python readers and writers
(track, frames, realglyphs, detdata, score, calibrate, corrections-report) go
through the query helpers below; the text dump stays for the Swift readers.
"""
from __future__ import annotations

import csv
import hashlib
import io
import json
import re
import sqlite3
import subprocess
import sys
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIX = ROOT / "Spike" / "ReceiptSpike" / "fixtures"
DB = FIX / "corpus.sqlite"
PUMP = FIX / "pump"
LIVE = FIX / "pump-live"
FRAMES = LIVE / "frames"
WINDOWS_FILE = PUMP / "windows.json"
EXPECTED_FILE = PUMP / "expected.csv"
VIDEOS_FILE = LIVE / "videos.json"
LABELS_FILE = LIVE / "video-labels.json"
CORRECTIONS_FILE = LIVE / "corrections.jsonl"
S3_ENDPOINT = "https://storage.yandexcloud.net"
S3_BUCKET = "tankbook-corpus"
S3_MEDIA_PREFIX = "pump-live/"

SCHEMA_VERSION = "3"

ENTRY_KEYS = ("windows", "rotationCW", "notOnDisplay", "csvDisagrees", "reviewed", "tracking", "liveAnchors")
VIDEO_KEYS = ("reference", "currency", "unitPrice", "windows", "reviewed", "anchors", "firstFrame", "lastFrame", "note")
FRAME_KEYS = ("windows", "inliers", "anchor", "verified")
CORRECTION_ORDER = ("still", "record", "video", "frame", "field", "proposedBy", "proposed", "final", "iou", "inliers")

SCHEMA = """
create table meta (key text primary key, value text);
create table fixtures (
  name text primary key, kind text not null, path text not null, bytes integer, sha256 text,
  width integer, height integer,
  liters text, unitPrice text, total text, fuelKind text, currency text, station text,
  split text, ord integer);
create table entries (
  fixture text primary key references fixtures(name),
  rotationCW integer not null default 0, reviewed integer not null default 0,
  notOnDisplay text, csvDisagrees text, tracking text, keys text, extra text, ord integer);
create table windows (
  id integer primary key, fixture text not null references fixtures(name), ord integer not null,
  field text not null, text text not null, legibility text, quad text not null,
  x0 real, y0 real, x1 real, y1 real);
create table media (
  name text primary key, kind text not null, path text not null, bytes integer,
  s3_key text not null, s3_url text not null, in_bucket integer,
  frames integer, paired_fixture text, note text, batch text);
create table pairs (
  pump text not null, receipt text not null, totalsAgree integer not null, note text,
  primary key (pump, receipt));
create table live_anchors (
  fixture text not null, record text not null, frame text not null, ord integer not null,
  field text not null, quad text not null);
create table videos (
  stem text primary key, reference text, unitPrice text, currency text,
  reviewed integer not null default 0, firstFrame text, lastFrame text, note text,
  keys text, extra text, ord integer);
create table video_windows (
  stem text not null, ord integer not null, field text not null, quad text not null);
create table video_anchors (
  stem text not null, frame text not null, ord integer not null, field text not null, quad text not null);
create table frames (
  record text not null, frame text not null, still text, split text,
  inliers integer, anchor integer, verified integer, keys text, extra text, ord integer,
  s3_key text,
  primary key (record, frame));
create table frame_windows (
  record text not null, frame text not null, ord integer not null, field text not null,
  text text, quad text not null, legibility text);
create table labels (
  video text not null, frame text not null, field text not null, text text, source text);
create table readings (
  record text not null, frame text not null, field text not null, text text, closes integer, ord integer);
create table corrections (
  at text, build text, kind text, still text, record text, video text, frame text, field text,
  proposedBy text, proposed text, final text, iou real, inliers integer, extra text);
"""


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def dimensions(path: Path) -> tuple[int | None, int | None]:
    try:
        out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
                             capture_output=True, text=True, check=True).stdout
        got = {k.strip(): int(v) for k, v in
               (line.strip().split(":") for line in out.splitlines() if "pixel" in line)}
        return got.get("pixelWidth"), got.get("pixelHeight")
    except (OSError, subprocess.CalledProcessError, ValueError):
        return None, None


def connect(path: Path | None = None) -> sqlite3.Connection:
    """WAL and a busy timeout: the annotator threads and a CLI dump may meet."""
    con = sqlite3.connect(str(path or DB), timeout=5.0)
    con.row_factory = sqlite3.Row
    con.execute("pragma journal_mode=wal")
    con.execute("pragma busy_timeout=5000")
    return con


def previous(db: Path) -> tuple[dict[str, tuple[int, int]], dict[str, tuple[int, int]]]:
    """What the last import knew and this one may not recompute: dimensions
    (slow) by content hash, and each medium's size and bucket presence - the
    file is committed, so a build on a machine without the movies or without
    the S3 key must not blank what a machine with them recorded."""
    if not db.exists():
        return {}, {}
    try:
        with sqlite3.connect(db) as con:
            dims = {s: (w, h) for s, w, h in con.execute(
                "select sha256, width, height from fixtures where width is not null")}
            media = {n: (b, k) for n, b, k in con.execute("select name, bytes, in_bucket from media")}
            return dims, media
    except sqlite3.DatabaseError:
        return {}, {}


# ---------------------------------------------------------------------------
# import: the files -> the database
# ---------------------------------------------------------------------------

def load_fixtures(con: sqlite3.Connection, known: dict[str, tuple[int, int]]) -> None:
    # decision 9: the frozen heldout draw; a pump still not listed is train.
    split: dict[str, str] = {}
    split_file = PUMP / "split.csv"
    if split_file.exists():
        with split_file.open() as f:
            split = {r["filename"]: r["split"] for r in csv.DictReader(f)}
    ord_ = 0
    for kind in ("pump", "receipts"):
        folder = FIX / kind
        expected = folder / "expected.csv"
        if not expected.exists():
            continue
        with expected.open() as f:
            for row in csv.DictReader(f):
                path = folder / row["filename"]
                digest = sha256(path) if path.exists() else None
                w, h = known.get(digest) if digest in known else (dimensions(path) if path.exists() else (None, None))
                con.execute(
                    "insert into fixtures values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    (row["filename"], "pump" if kind == "pump" else "receipt",
                     str(path.relative_to(ROOT)), path.stat().st_size if path.exists() else None, digest, w, h,
                     row.get("liters") or None, row.get("unitPrice") or None, row.get("total") or None,
                     row.get("fuelKind") or None, row.get("currency") or None, row.get("station") or None,
                     (split.get(row["filename"], "train") if kind == "pump" else None), ord_))
                ord_ += 1


def _residual(obj: dict, known: tuple[str, ...]) -> dict:
    return {k: v for k, v in obj.items() if k not in known}


def _live_anchors(con: sqlite3.Connection, fixture: str) -> list[dict]:
    rows = con.execute("select record, frame, field, quad from live_anchors "
                       "where fixture = ? order by ord", (fixture,)).fetchall()
    out: list[dict] = []
    for r in rows:
        anchor = next((a for a in out if a["record"] == r["record"] and a["frame"] == r["frame"]), None)
        if anchor is None:
            anchor = {"record": r["record"], "frame": r["frame"], "windows": []}
            out.append(anchor)
        anchor["windows"].append({"field": r["field"], "quad": json.loads(r["quad"])})
    return out


def load_windows(con: sqlite3.Connection) -> None:
    ann = json.loads(WINDOWS_FILE.read_text())
    ord_ = 0
    for name, entry in ann.items():
        if name.startswith("_"):
            con.execute("insert into meta values (?,?)", ("windows.json:" + name, entry))
            continue
        con.execute(
            "insert into entries (fixture, rotationCW, reviewed, notOnDisplay, csvDisagrees, tracking, keys, extra, ord) "
            "values (?,?,?,?,?,?,?,?,?)",
            (name, entry.get("rotationCW", 0), int(bool(entry.get("reviewed"))),
             json.dumps(entry["notOnDisplay"]) if entry.get("notOnDisplay") else None,
             json.dumps(entry["csvDisagrees"]) if entry.get("csvDisagrees") else None,
             entry.get("tracking"), json.dumps(list(entry.keys())), json.dumps(_residual(entry, ENTRY_KEYS)), ord_))
        ord_ += 1
        for i, w in enumerate(entry.get("windows", [])):
            xs = [p[0] for p in w["quad"]]
            ys = [p[1] for p in w["quad"]]
            con.execute("insert into windows (fixture, ord, field, text, legibility, quad, x0, y0, x1, y1) "
                        "values (?,?,?,?,?,?,?,?,?,?)",
                        (name, i, w["field"], w.get("text", ""), w.get("legibility"), json.dumps(w["quad"]),
                         min(xs), min(ys), max(xs), max(ys)))
        for i, a in enumerate(entry.get("liveAnchors", [])):
            for w in a["windows"]:
                con.execute("insert into live_anchors values (?,?,?,?,?,?)",
                            (name, a["record"], a["frame"], i, w["field"], json.dumps(w["quad"])))


def load_videos(con: sqlite3.Connection) -> None:
    if not VIDEOS_FILE.exists():
        return
    videos = json.loads(VIDEOS_FILE.read_text())
    ord_ = 0
    for stem, entry in videos.items():
        if stem.startswith("_"):
            con.execute("insert into meta values (?,?)", ("videos.json:" + stem, entry))
            continue
        con.execute(
            "insert into videos (stem, reference, unitPrice, currency, reviewed, firstFrame, lastFrame, note, keys, extra, ord) "
            "values (?,?,?,?,?,?,?,?,?,?,?)",
            (stem, entry.get("reference"), entry.get("unitPrice"), entry.get("currency"),
             int(bool(entry.get("reviewed"))), entry.get("firstFrame"), entry.get("lastFrame"),
             entry.get("note"), json.dumps(list(entry.keys())), json.dumps(_residual(entry, VIDEO_KEYS)), ord_))
        ord_ += 1
        for i, w in enumerate(entry.get("windows", [])):
            con.execute("insert into video_windows values (?,?,?,?)", (stem, i, w["field"], json.dumps(w["quad"])))
        for i, a in enumerate(entry.get("anchors", [])):
            for w in a["windows"]:
                con.execute("insert into video_anchors values (?,?,?,?,?)",
                            (stem, a["frame"], i, w["field"], json.dumps(w["quad"])))


def _write_frames(con: sqlite3.Connection, record: str, tracked: dict) -> None:
    """One record's tracked frames as `frames` / `frame_windows` rows - the
    exact shape `_load_frames_file` imported, so `dump` reproduces the file."""
    con.execute("insert or replace into frames (record, frame, still, split, inliers, anchor, verified, keys, extra, ord) "
                "values (?,?,?,?,?,?,?,?,?,?)",
                (record, "", tracked.get("_still") or tracked.get("_video"), tracked.get("_split"),
                 None, None, None, json.dumps(list(tracked.keys())),
                 json.dumps({k: v for k, v in tracked.items() if k != "frames"}), None))
    for i, (frame, fr) in enumerate(tracked.get("frames", {}).items()):
        con.execute(
            "insert or replace into frames (record, frame, still, split, inliers, anchor, verified, keys, extra, ord) "
            "values (?,?,?,?,?,?,?,?,?,?)",
            (record, frame, tracked.get("_still") or tracked.get("_video"), tracked.get("_split"),
             fr.get("inliers"), fr.get("anchor"), (1 if fr.get("verified") else None) if "verified" in fr else None,
             json.dumps(list(fr.keys())), json.dumps(_residual(fr, FRAME_KEYS)), i))
        for j, w in enumerate(fr.get("windows", [])):
            con.execute("insert into frame_windows values (?,?,?,?,?,?,?)",
                        (record, frame, j, w["field"], w.get("text", ""), json.dumps(w["quad"]), w.get("legibility")))


def _load_frames_file(con: sqlite3.Connection, path: Path) -> None:
    _write_frames(con, path.parent.name, json.loads(path.read_text()))


def load_frames(con: sqlite3.Connection) -> None:
    for path in sorted(FRAMES.glob("*/windows.json")):
        _load_frames_file(con, path)


def load_labels(con: sqlite3.Connection) -> None:
    if not LABELS_FILE.exists():
        return
    labels = json.loads(LABELS_FILE.read_text())
    for video, frames in labels.items():
        if not frames:
            con.execute("insert into labels values (?,?,?,?,?)", (video, "", "", None, None))
        for frame, fields in frames.items():
            source = fields.get("source")
            for field, text in fields.items():
                if field == "source":
                    continue
                con.execute("insert into labels values (?,?,?,?,?)", (video, frame, field, text, source))


def load_readings(con: sqlite3.Connection) -> None:
    for path in sorted(FRAMES.glob("*/readings.json")):
        record = path.parent.name
        raw = path.read_bytes()
        # Two writers produced this file over time: the Swift reader writes
        # compact sorted JSON, an older Python one wrote `json.dumps(sort_keys=True)`.
        # The style is formatting, not data - carried in `meta` so the dump can
        # reproduce the file byte for byte.
        con.execute("insert into meta values (?,?)",
                    ("readings-style:" + record, "spaced" if b'": ' in raw[:200] else "compact"))
        readings = json.loads(raw)
        if not readings:
            con.execute("insert into readings values (?,?,?,?,?,?)", (record, "", "", None, None, -1))
        for i, (frame, fields) in enumerate(readings.items()):
            closes = int(bool(fields.get("closes")))
            for field, text in fields.items():
                if field == "closes":
                    continue
                con.execute("insert into readings values (?,?,?,?,?,?)", (record, frame, field, text, closes, i))


def _correction_value(v):
    return v if isinstance(v, str) else json.dumps(v)


def load_corrections(con: sqlite3.Connection) -> None:
    if not CORRECTIONS_FILE.exists():
        return
    for line in CORRECTIONS_FILE.read_text().splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        extra = {k: v for k, v in row.items() if k not in ("at", "build", *CORRECTION_ORDER)}
        con.execute(
            "insert into corrections (at, build, kind, still, record, video, frame, field, proposedBy, "
            "proposed, final, iou, inliers, extra) values (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (row.get("at"), row.get("build"), row.get("kind"), row.get("still"), row.get("record"),
             row.get("video"), row.get("frame"), row.get("field"), row.get("proposedBy"),
             _correction_value(row.get("proposed")) if row.get("proposed") is not None else None,
             _correction_value(row.get("final")) if row.get("final") is not None else None,
             row.get("iou"), row.get("inliers"), json.dumps(extra) if extra else None))


LIVE_ROW = re.compile(r"^\|\s*`?((?:live|video)-\d+[\w-]*?)(?:\.mov|\.mp4)?`?\s*\|\s*(\d+)[^|]*\|(.*)$")


def load_media(con: sqlite3.Connection, in_bucket: set[str] | None, known: dict[str, tuple[int, int]]) -> None:
    """The README's pairing tables are the record of what each movie is; the
    folder says what is on this machine; the bucket key is deterministic."""
    readme_path = LIVE / "README.md"
    readme = readme_path.read_text().splitlines() if readme_path.exists() else []
    rows: dict[str, dict] = {}
    batch = None
    for line in readme:
        if line.startswith("## "):
            batch = line[3:].strip()
        m = LIVE_ROW.match(line)
        if not m:
            continue
        name, frames, rest = m.group(1), int(m.group(2)), [c.strip() for c in m.group(3).strip("|").split("|")]
        paired = next((c for c in rest if re.search(r"\b(pump|receipt)-\d{3}\b", c)), None)
        paired = re.search(r"\b((?:pump|receipt)-\d{3})\b", paired).group(1) if paired else None
        note = " · ".join(c.replace("`", "").replace("**", "").strip() for c in rest if c and c != "-")
        if "dropped" in note:
            continue  # a duplicate that was removed from the folder and the bucket
        rows.setdefault(name, {"frames": frames, "paired": paired, "note": note, "batch": batch})
    for path in list(LIVE.glob("live-*.*")) + list(LIVE.glob("video-*.*")):
        if path.suffix.lower() in (".mov", ".heic", ".mp4"):
            rows.setdefault(path.stem, {"frames": None, "paired": None, "note": None, "batch": None})
    for stem, info in sorted(rows.items()):
        for suffix in ((".mp4",) if stem.startswith("video-") else (".mov", ".heic")):
            path = LIVE / f"{stem}{suffix}"
            key = S3_MEDIA_PREFIX + path.name
            was = known.get(path.name, (None, None))
            in_bucket_now = (key in in_bucket) if in_bucket is not None else was[1]
            size = path.stat().st_size if path.exists() else was[0]
            if not path.exists() and not in_bucket_now and suffix == ".heic":
                continue
            paired = info["paired"]
            if paired and not paired.endswith((".jpg", ".jpeg", ".png", ".heic")):
                match = con.execute("select name from fixtures where name like ?", (paired + "%",)).fetchone()
                paired = match[0] if match else paired
            con.execute("insert into media values (?,?,?,?,?,?,?,?,?,?,?)",
                        (path.name, {".mov": "live", ".heic": "keyframe", ".mp4": "video"}[suffix],
                         str(path.relative_to(ROOT)), size,
                         key, f"{S3_ENDPOINT}/{S3_BUCKET}/{key}", in_bucket_now,
                         info["frames"], paired, info["note"], info["batch"]))


PAIR = re.compile(r'MatchedPair\(pump: "([^"]+)", receipt: "([^"]+)"(?:, totalsAgree: (false|true))?'
                  r'(?:,\s*note: "([^"]*)")?\)')


def load_pairs(con: sqlite3.Connection) -> None:
    source_file = ROOT / "ios/Tests/TankbookCoreTests/CorpusPairTests.swift"
    if not source_file.exists():
        return
    source = source_file.read_text()
    for pump, receipt, agree, note in PAIR.findall(source):
        full = lambda stem: (con.execute("select name from fixtures where name like ?", (stem + "%",)).fetchone() or [stem])[0]  # noqa: E731
        con.execute("insert or replace into pairs values (?,?,?,?)",
                    (full(pump), full(receipt), 0 if agree == "false" else 1, note or None))


def bucket_keys() -> set[str]:
    sys.path.insert(0, str(ROOT / "scripts"))
    import importlib
    sync = importlib.import_module("corpus-sync")
    sync.credentials()
    return set(sync.remote_index(sync.client(), S3_MEDIA_PREFIX))


def _carry_forward(con: sqlite3.Connection, old_db: Path, tables: list[str]) -> None:
    """Keep rows the files cannot reproduce. `frames/` is gitignored, so on a
    checkout without it the committed database is the only carrier - an import
    must not blank it, the same rule `previous()` already applies to media."""
    if not old_db.exists() or not tables:
        return
    con.commit()
    try:
        con.execute("attach database ? as old", (str(old_db),))
    except sqlite3.DatabaseError:
        return
    try:
        for table in tables:
            try:
                con.execute(f"insert into {table} select * from old.{table}")
            except sqlite3.DatabaseError:
                con.rollback()  # the old database predates the table
        con.commit()
    finally:
        try:
            con.execute("detach database old")
        except sqlite3.DatabaseError:
            pass
        con.commit()


def _carry_frame_keys(con: sqlite3.Connection, old_db: Path) -> None:
    """Keep `frames.s3_key`: the frames files are gitignored and the key is not
    in them, so a rebuild that re-reads the frames must not blank it."""
    if not old_db.exists():
        return
    con.commit()
    try:
        con.execute("attach database ? as old", (str(old_db),))
    except sqlite3.DatabaseError:
        return
    try:
        columns = {r[1] for r in con.execute("pragma old.table_info(frames)")}
        if "s3_key" in columns:
            con.execute(
                "update frames set s3_key = (select o.s3_key from old.frames o "
                "where o.record = frames.record and o.frame = frames.frame) "
                "where exists (select 1 from old.frames o where o.record = frames.record "
                "and o.frame = frames.frame and o.s3_key is not null)")
        con.commit()
    except sqlite3.DatabaseError:
        con.rollback()  # an unreadable old database must not abort the rebuild
    finally:
        try:
            con.execute("detach database old")
        except sqlite3.DatabaseError:
            pass
        con.commit()


def import_corpus(with_s3: bool = False, db: Path | None = None) -> Path:
    """The files -> a fresh database, replacing it atomically. Renamed `build`."""
    target = db or DB
    known, media_known = previous(target)
    tmp = target.with_suffix(".sqlite.tmp")
    tmp.unlink(missing_ok=True)
    con = connect(tmp)
    try:
        con.executescript(SCHEMA)
        con.execute("insert into meta values ('schema_version', ?)", (SCHEMA_VERSION,))
        load_fixtures(con, known)
        load_windows(con)
        load_videos(con)
        load_frames(con)
        load_labels(con)
        load_readings(con)
        load_corrections(con)
        carry: list[str] = []
        if not any(FRAMES.glob("*/windows.json")):
            carry += ["frames", "frame_windows"]
        if not any(FRAMES.glob("*/readings.json")):
            carry.append("readings")
        if not LABELS_FILE.exists():
            carry.append("labels")
        if not CORRECTIONS_FILE.exists():
            carry.append("corrections")
        _carry_forward(con, target, carry)
        _carry_frame_keys(con, target)
        load_media(con, bucket_keys() if with_s3 else None, media_known)
        load_pairs(con)
        # The file is committed: a rebuild from unchanged inputs must be
        # byte-identical, so no timestamps, no git revision, and a VACUUM to
        # settle page layout.
        con.commit()
        con.execute("vacuum")
    finally:
        con.close()
    tmp.replace(target)
    return target


# ---------------------------------------------------------------------------
# dump: the database -> the files
# ---------------------------------------------------------------------------

def _group(rows, *keys) -> dict:
    out: dict = {}
    for r in rows:
        out.setdefault(tuple(r[k] for k in keys), []).append(r)
    return out


def _window_list(rows) -> list[dict]:
    return [{"field": r["field"], "text": r["text"], "quad": json.loads(r["quad"]),
             **({"legibility": r["legibility"]} if r["legibility"] else {})} for r in rows]


def _anchor_list(rows) -> list[dict]:
    anchors: list[dict] = []
    for r in rows:
        anchor = next((a for a in anchors if a["frame"] == r["frame"]), None)
        if anchor is None:
            anchor = {"frame": r["frame"], "windows": []}
            anchors.append(anchor)
        anchor["windows"].append({"field": r["field"], "quad": json.loads(r["quad"])})
    return anchors


def _live_anchor_list(rows) -> list[dict]:
    anchors: list[dict] = []
    for r in rows:
        anchor = next((a for a in anchors if a["record"] == r["record"] and a["frame"] == r["frame"]), None)
        if anchor is None:
            anchor = {"record": r["record"], "frame": r["frame"], "windows": []}
            anchors.append(anchor)
        anchor["windows"].append({"field": r["field"], "quad": json.loads(r["quad"])})
    return anchors


def _ordered(keys: list[str], values: dict, extra: dict) -> dict:
    out: dict = {}
    for k in keys:
        if k in extra:
            out[k] = extra[k]
        elif k in values and values[k] is not None:
            out[k] = values[k]
    return out


def _entry_obj(row: sqlite3.Row, windows: list, live: list) -> dict:
    values = {
        "windows": _window_list(windows),
        "rotationCW": row["rotationCW"],
        "reviewed": bool(row["reviewed"]),
        "notOnDisplay": json.loads(row["notOnDisplay"]) if row["notOnDisplay"] else None,
        "csvDisagrees": json.loads(row["csvDisagrees"]) if row["csvDisagrees"] else None,
        "tracking": row["tracking"],
        "liveAnchors": _live_anchor_list(live),
    }
    extra = json.loads(row["extra"]) if row["extra"] else {}
    return _ordered(json.loads(row["keys"]), values, extra)


def _render_windows(con: sqlite3.Connection) -> bytes:
    out: dict = {}
    for r in con.execute("select * from meta where key like 'windows.json:%' order by key"):
        out[r["key"].split(":", 1)[1]] = r["value"]
    windows = _group(con.execute("select * from windows order by fixture, ord"), "fixture")
    live = _group(con.execute("select * from live_anchors order by fixture, ord"), "fixture")
    for row in con.execute("select * from entries order by ord"):
        out[row["fixture"]] = _entry_obj(row, windows.get((row["fixture"],), []), live.get((row["fixture"],), []))
    return (json.dumps(out, indent=1) + "\n").encode()


def _render_expected(con: sqlite3.Connection) -> bytes:
    buf = io.StringIO()
    writer = csv.writer(buf, lineterminator="\n")
    writer.writerow(["filename", "liters", "unitPrice", "total", "fuelKind", "currency"])
    for r in con.execute("select name, liters, unitPrice, total, fuelKind, currency from fixtures "
                         "where kind = 'pump' order by ord"):
        writer.writerow([r["name"], r["liters"], r["unitPrice"], r["total"], r["fuelKind"], r["currency"]])
    return buf.getvalue().encode()


def _video_obj(row: sqlite3.Row, windows: list, anchors: list) -> dict:
    values = {"reference": row["reference"], "currency": row["currency"], "unitPrice": row["unitPrice"],
              "windows": [{"field": r["field"], "quad": json.loads(r["quad"])} for r in windows],
              "reviewed": bool(row["reviewed"]), "anchors": _anchor_list(anchors),
              "firstFrame": row["firstFrame"], "lastFrame": row["lastFrame"], "note": row["note"]}
    extra = json.loads(row["extra"]) if row["extra"] else {}
    return _ordered(json.loads(row["keys"]), values, extra)


def _render_videos(con: sqlite3.Connection) -> bytes:
    out: dict = {}
    for r in con.execute("select * from meta where key like 'videos.json:%' order by key"):
        out[r["key"].split(":", 1)[1]] = r["value"]
    windows = _group(con.execute("select * from video_windows order by stem, ord"), "stem")
    anchors = _group(con.execute("select * from video_anchors order by stem, ord"), "stem")
    for row in con.execute("select * from videos order by ord"):
        out[row["stem"]] = _video_obj(row, windows.get((row["stem"],), []), anchors.get((row["stem"],), []))
    return json.dumps(out, indent=1).encode()


def _render_labels(con: sqlite3.Connection) -> bytes:
    out: dict = {}
    rows = _group(con.execute("select * from labels order by video, frame"), "video", "frame")
    for (video, frame), group in rows.items():
        frames = out.setdefault(video, {})
        if frame == "":
            continue
        fields: dict = {}
        for r in group:
            fields[r["field"]] = r["text"]
            if r["source"] is not None:
                fields["source"] = r["source"]
        frames[frame] = fields
    return json.dumps(out, indent=1, sort_keys=True).encode()


def _render_readings(con: sqlite3.Connection) -> dict[Path, bytes]:
    out: dict[Path, bytes] = {}
    styles = {r["key"].split(":", 1)[1]: r["value"]
              for r in con.execute("select * from meta where key like 'readings-style:%'")}
    rows = _group(con.execute("select * from readings order by record, ord"), "record")
    for (record,), group in rows.items():
        body: dict = {}
        for r in group:
            if r["frame"] == "":
                continue
            fields = body.setdefault(r["frame"], {"closes": bool(r["closes"])})
            fields[r["field"]] = r["text"]
        if styles.get(record) == "spaced":
            out[FRAMES / record / "readings.json"] = json.dumps(body).encode()
        else:
            out[FRAMES / record / "readings.json"] = json.dumps(body, separators=(",", ":")).encode()
    return out


def _frame_obj(row: sqlite3.Row, windows: list) -> dict:
    values = {"windows": _window_list(windows), "inliers": row["inliers"], "anchor": row["anchor"],
              "verified": bool(row["verified"]) if row["verified"] is not None else None}
    extra = json.loads(row["extra"]) if row["extra"] else {}
    return _ordered(json.loads(row["keys"]), values, extra)


def _render_frames(con: sqlite3.Connection) -> dict[Path, bytes]:
    out: dict[Path, bytes] = {}
    windows = _group(con.execute("select * from frame_windows order by record, frame, ord"), "record", "frame")
    frames = _group(con.execute("select * from frames order by record, ord"), "record")
    for (record,), group in frames.items():
        meta = next((r for r in group if r["frame"] == ""), None)
        if meta is None:
            continue
        body: dict = {}
        for row in group:
            if row["frame"] == "":
                continue
            body[row["frame"]] = _frame_obj(row, windows.get((record, row["frame"]), []))
        values = {"frames": body, "_still": meta["still"], "_split": meta["split"]}
        extra = json.loads(meta["extra"]) if meta["extra"] else {}
        out[FRAMES / record / "windows.json"] = json.dumps(_ordered(json.loads(meta["keys"]), values, extra), indent=1).encode()
    return out


def _render_corrections(con: sqlite3.Connection) -> bytes | None:
    rows = con.execute("select * from corrections order by rowid").fetchall()
    if not rows:
        return None
    lines = []
    for r in rows:
        obj: dict = {"at": r["at"], "build": r["build"], "kind": r["kind"]}
        for k in CORRECTION_ORDER:
            v = r[k]
            if v is None:
                continue
            obj[k] = json.loads(v) if k in ("proposed", "final") and r["kind"] == "quad" else v
        obj.update(json.loads(r["extra"]) if r["extra"] else {})
        lines.append(json.dumps(obj, ensure_ascii=False))
    return ("\n".join(lines) + "\n").encode()


def render() -> dict[Path, bytes]:
    """Every dumped file's bytes, without writing."""
    con = connect()
    try:
        out = {
            WINDOWS_FILE: _render_windows(con),
            EXPECTED_FILE: _render_expected(con),
            VIDEOS_FILE: _render_videos(con),
            LABELS_FILE: _render_labels(con),
        }
        out.update(_render_readings(con))
        out.update(_render_frames(con))
        corrections = _render_corrections(con)
        if corrections is not None:
            out[CORRECTIONS_FILE] = corrections
        return out
    finally:
        con.close()


def dump(paths: list[Path] | None = None) -> list[Path]:
    """Write the database's files. `paths` limits the write to those files."""
    rendered = render()
    if paths is not None:
        want = {Path(p) for p in paths}
        rendered = {p: b for p, b in rendered.items() if p in want}
    for path, body in rendered.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(body)
    return list(rendered)


def mark_in_bucket(keys: set[str], db: Path | None = None) -> int:
    """Refresh `media.in_bucket` from a bucket listing - the one thing a push
    changes about the database; nothing else is touched."""
    with transaction(None) as con:
        rows = con.execute("select name, s3_key, in_bucket from media").fetchall()
        changed = 0
        for row in rows:
            now = 1 if row["s3_key"] in keys else 0
            if (row["in_bucket"] or 0) != now:
                con.execute("update media set in_bucket = ? where name = ?", (now, row["name"]))
                changed += 1
        return changed


def check() -> list[str]:
    """The dump's stale files: [] when every file matches the database."""
    stale: list[str] = []
    for path, body in render().items():
        if not path.exists():
            stale.append(f"{path.relative_to(ROOT)}: missing (the database has it)")
        elif path.read_bytes() != body:
            stale.append(f"{path.relative_to(ROOT)}: differs from the database (run corpus_db.py dump)")
    return stale


# ---------------------------------------------------------------------------
# the readers' query helpers
# ---------------------------------------------------------------------------

def entry(name: str, con: sqlite3.Connection | None = None) -> dict | None:
    """One still's annotated entry, the `windows.json` object. None if unknown."""
    with transaction(con) as con:
        row = con.execute("select * from entries where fixture = ?", (name,)).fetchone()
        if row is None:
            return None
        windows = con.execute("select * from windows where fixture = ? order by ord", (name,)).fetchall()
        live = con.execute("select * from live_anchors where fixture = ? order by ord", (name,)).fetchall()
        return _entry_obj(row, windows, live)


def entries(con: sqlite3.Connection | None = None) -> dict[str, dict]:
    """Every still entry, the `windows.json` object (without the meta keys)."""
    with transaction(con) as con:
        out: dict[str, dict] = {}
        for row in con.execute("select * from entries order by ord"):
            windows = con.execute("select * from windows where fixture = ? order by ord", (row["fixture"],)).fetchall()
            live = con.execute("select * from live_anchors where fixture = ? order by ord", (row["fixture"],)).fetchall()
            out[row["fixture"]] = _entry_obj(row, windows, live)
        return out


def video(stem: str, con: sqlite3.Connection | None = None) -> dict | None:
    """One running-display video's entry, the `videos.json` object."""
    with transaction(con) as con:
        row = con.execute("select * from videos where stem = ?", (stem,)).fetchone()
        if row is None:
            return None
        windows = con.execute("select * from video_windows where stem = ? order by ord", (stem,)).fetchall()
        anchors = con.execute("select * from video_anchors where stem = ? order by ord", (stem,)).fetchall()
        return _video_obj(row, windows, anchors)


def tracked(record: str, con: sqlite3.Connection | None = None) -> dict | None:
    """One record's tracked frames, the `frames/<record>/windows.json` object."""
    with transaction(con) as con:
        meta = con.execute("select * from frames where record = ? and frame = ''", (record,)).fetchone()
        if meta is None:
            return None
        rows = con.execute("select * from frames where record = ? and frame != '' order by ord", (record,)).fetchall()
        windows = _group(con.execute("select * from frame_windows where record = ? order by frame, ord", (record,)),
                         "frame")
        body = {r["frame"]: _frame_obj(r, windows.get((r["frame"],), [])) for r in rows}
        values = {"frames": body, "_still": meta["still"], "_split": meta["split"]}
        extra = json.loads(meta["extra"]) if meta["extra"] else {}
        return _ordered(json.loads(meta["keys"]), values, extra)


def tracked_records(con: sqlite3.Connection | None = None) -> list[str]:
    with transaction(con) as con:
        return [r["record"] for r in con.execute("select record from frames where frame = '' order by record")]


def video_stems(con: sqlite3.Connection | None = None) -> list[str]:
    with transaction(con) as con:
        return [r["stem"] for r in con.execute("select stem from videos order by ord")]


def split(con: sqlite3.Connection | None = None) -> dict[str, str]:
    """Every still's frozen split (`fixtures.split`); a pump not listed is train."""
    with transaction(con) as con:
        return {r["name"]: r["split"] for r in
                con.execute("select name, split from fixtures where split is not null")}


def heldout_names(con: sqlite3.Connection | None = None) -> set[str]:
    with transaction(con) as con:
        return {r["name"] for r in con.execute("select name from fixtures where split = 'heldout'")}


def labels(con: sqlite3.Connection | None = None) -> dict:
    """The video labels, the `video-labels.json` object."""
    with transaction(con) as con:
        out: dict = {}
        rows = _group(con.execute("select * from labels order by video, frame"), "video", "frame")
        for (video, frame), group in rows.items():
            frames = out.setdefault(video, {})
            if frame == "":
                continue
            fields: dict = {}
            for r in group:
                fields[r["field"]] = r["text"]
                if r["source"] is not None:
                    fields["source"] = r["source"]
            frames[frame] = fields
        return out


def corrections(con: sqlite3.Connection | None = None) -> list[dict]:
    """The ledger rows, in the order they were appended (the JSONL's order)."""
    with transaction(con) as con:
        out: list[dict] = []
        for r in con.execute("select * from corrections order by rowid"):
            obj: dict = {"at": r["at"], "build": r["build"], "kind": r["kind"]}
            for k in CORRECTION_ORDER:
                v = r[k]
                if v is None:
                    continue
                obj[k] = json.loads(v) if k in ("proposed", "final") and r["kind"] == "quad" else v
            obj.update(json.loads(r["extra"]) if r["extra"] else {})
            out.append(obj)
        return out


def paired_records(con: sqlite3.Connection | None = None) -> list[tuple[str, str, str]]:
    """(movie stem, still filename, split) for every Live record paired to a pump still."""
    with transaction(con) as con:
        rows = con.execute(
            "select m.name, m.paired_fixture, f.split from media m join fixtures f on f.name = m.paired_fixture "
            "where m.kind = 'live' and f.kind = 'pump' order by m.name").fetchall()
    return [(Path(name).stem, still, s) for name, still, s in rows]


# ---------------------------------------------------------------------------
# the annotator's write path
# ---------------------------------------------------------------------------

def clean_entry(entry: dict) -> dict:
    """Only the documented keys, in the file's order, empties dropped - the
    same shape the annotator has always written."""
    out: dict = {"windows": []}
    for w in entry.get("windows", []):
        quad = [[round(float(x), 4), round(float(y), 4)] for x, y in w["quad"]]
        cw = {"field": w["field"], "text": w.get("text", ""), "quad": quad}
        if w.get("legibility"):
            cw["legibility"] = w["legibility"]
        out["windows"].append(cw)
    if entry.get("rotationCW"):
        out["rotationCW"] = int(entry["rotationCW"])
    if entry.get("notOnDisplay"):
        out["notOnDisplay"] = list(entry["notOnDisplay"])
    if entry.get("csvDisagrees"):
        out["csvDisagrees"] = dict(entry["csvDisagrees"])
    if entry.get("reviewed"):
        out["reviewed"] = True
    if entry.get("tracking") in ("ok", "bad"):
        out["tracking"] = entry["tracking"]
    if entry.get("liveAnchors"):
        out["liveAnchors"] = [{"record": a["record"], "frame": a["frame"], "windows": a["windows"]}
                              for a in entry["liveAnchors"]]
    return out


@contextmanager
def transaction(con: sqlite3.Connection | None = None):
    """One connection and one transaction. A caller that passes its own
    connection owns the commit, so several writes are one transaction."""
    if con is not None:
        yield con
        return
    own = connect()
    try:
        with own:
            yield own
    finally:
        own.close()


def _write_entry(con: sqlite3.Connection, name: str, entry: dict) -> None:
    # An existing entry keeps its file position; a new one is appended, the
    # same order the annotator's whole-file rewrite produced.
    existing = con.execute("select ord from entries where fixture = ?", (name,)).fetchone()
    ord_ = existing["ord"] if existing is not None else con.execute(
        "select coalesce(max(ord), -1) + 1 from entries").fetchone()[0]
    con.execute("delete from windows where fixture = ?", (name,))
    con.execute("delete from live_anchors where fixture = ?", (name,))
    con.execute("delete from entries where fixture = ?", (name,))
    con.execute(
        "insert into entries (fixture, rotationCW, reviewed, notOnDisplay, csvDisagrees, tracking, keys, extra, ord) "
        "values (?,?,?,?,?,?,?,?,?)",
        (name, entry.get("rotationCW", 0), int(bool(entry.get("reviewed"))),
         json.dumps(entry["notOnDisplay"]) if entry.get("notOnDisplay") else None,
         json.dumps(entry["csvDisagrees"]) if entry.get("csvDisagrees") else None,
         entry.get("tracking"), json.dumps(list(entry.keys())), "{}", ord_))
    for i, w in enumerate(entry.get("windows", [])):
        xs = [p[0] for p in w["quad"]]
        ys = [p[1] for p in w["quad"]]
        con.execute("insert into windows (fixture, ord, field, text, legibility, quad, x0, y0, x1, y1) "
                    "values (?,?,?,?,?,?,?,?,?,?)",
                    (name, i, w["field"], w.get("text", ""), w.get("legibility"), json.dumps(w["quad"]),
                     min(xs), min(ys), max(xs), max(ys)))
    for i, a in enumerate(entry.get("liveAnchors", [])):
        for w in a["windows"]:
            con.execute("insert into live_anchors values (?,?,?,?,?,?)",
                        (name, a["record"], a["frame"], i, w["field"], json.dumps(w["quad"])))


def save_entry(name: str, entry: dict, con: sqlite3.Connection | None = None) -> dict:
    """One still's annotation. Live anchors the page did not carry are kept."""
    entry = dict(entry)
    with transaction(con) as con:
        if "liveAnchors" not in entry:
            existing = _live_anchors(con, name)
            if existing:
                entry["liveAnchors"] = existing
        cleaned = clean_entry(entry)
        _write_entry(con, name, cleaned)
        return cleaned


def save_live_anchor(still: str, record: str, frame: str, windows: list[dict],
                     con: sqlite3.Connection | None = None) -> list[dict]:
    """Replace one hand-placed frame on a Live record's still entry."""
    with transaction(con) as con:
        anchors = [a for a in _live_anchors(con, still) if not (a["record"] == record and a["frame"] == frame)]
        anchors.append({"record": record, "frame": frame, "windows": windows})
        anchors.sort(key=lambda a: (a["record"], int(a["frame"][:-4])))
        row = con.execute("select * from entries where fixture = ?", (still,)).fetchone()
        if row is None:
            return []
        entry = _entry_obj(row,
                           con.execute("select * from windows where fixture = ? order by ord", (still,)).fetchall(),
                           con.execute("select * from live_anchors where fixture = ? order by ord", (still,)).fetchall())
        entry["liveAnchors"] = anchors
        _write_entry(con, still, clean_entry(entry))
        return anchors


def save_video(stem: str, windows: list[dict], reviewed: bool, con: sqlite3.Connection | None = None) -> None:
    with transaction(con) as con:
        con.execute("update videos set reviewed = ? where stem = ?", (int(bool(reviewed)), stem))
        con.execute("delete from video_windows where stem = ?", (stem,))
        for i, w in enumerate(windows):
            con.execute("insert into video_windows values (?,?,?,?)", (stem, i, w["field"], json.dumps(w["quad"])))


def save_video_anchor(stem: str, frame: str, windows: list[dict],
                      con: sqlite3.Connection | None = None) -> list[dict]:
    """A hand-placed frame on a video: the reference's quads, or an anchor."""
    with transaction(con) as con:
        reference = con.execute("select reference from videos where stem = ?", (stem,)).fetchone()
        if reference is None:
            return []
        if frame == reference["reference"]:
            con.execute("delete from video_windows where stem = ?", (stem,))
            for i, w in enumerate(windows):
                con.execute("insert into video_windows values (?,?,?,?)", (stem, i, w["field"], json.dumps(w["quad"])))
        else:
            con.execute("delete from video_anchors where stem = ? and frame = ?", (stem, frame))
            ord_ = con.execute("select coalesce(max(ord), -1) + 1 from video_anchors where stem = ?", (stem,)).fetchone()[0]
            for i, w in enumerate(windows):
                con.execute("insert into video_anchors values (?,?,?,?,?)",
                            (stem, frame, ord_ + i, w["field"], json.dumps(w["quad"])))
        return [r["frame"] for r in con.execute("select distinct frame from video_anchors where stem = ? order by ord", (stem,))]


def quad_iou(a: list, b: list) -> float:
    """Axis-aligned IoU of two normalised quads - enough to rank how far a
    tracked quad sat from the hand-placed one."""
    def box(q):
        xs = [p[0] for p in q]
        ys = [p[1] for p in q]
        return min(xs), min(ys), max(xs), max(ys)
    ax0, ay0, ax1, ay1 = box(a)
    bx0, by0, bx1, by1 = box(b)
    iw = max(0.0, min(ax1, bx1) - max(ax0, bx0))
    ih = max(0.0, min(ay1, by1) - max(ay0, by0))
    inter = iw * ih
    union = (ax1 - ax0) * (ay1 - ay0) + (bx1 - bx0) * (by1 - by0) - inter
    return round(inter / union, 3) if union > 0 else 0.0


def _frame_windows(con: sqlite3.Connection, record: str, frame: str) -> list[dict]:
    return [{"field": r["field"], "text": r["text"], "quad": json.loads(r["quad"]),
             **({"legibility": r["legibility"]} if r["legibility"] else {})}
            for r in con.execute("select * from frame_windows where record = ? and frame = ? order by ord",
                                 (record, frame))]


def save_tracked(record: str, tracked: dict, con: sqlite3.Connection | None = None) -> None:
    """`pump_reader.track`'s write: one record's frames / frame windows in one
    transaction. The caller dumps the record's file so the Swift readers see it."""
    with transaction(con) as con:
        con.execute("delete from frame_windows where record = ?", (record,))
        con.execute("delete from frames where record = ?", (record,))
        _write_frames(con, record, tracked)


def import_frames(record: str) -> bool:
    """One-time import of `frames/<record>/windows.json` for a folder tracked
    before PU.36b, when `pump_reader.track` wrote the file and the server read it
    back. `save_tracked` is the write path now; this remains for old folders."""
    path = FRAMES / record / "windows.json"
    if not path.exists():
        return False
    con = connect()
    try:
        with con:
            con.execute("delete from frame_windows where record = ?", (record,))
            con.execute("delete from frames where record = ?", (record,))
            _load_frames_file(con, path)
        return True
    finally:
        con.close()


def pin_frame(record: str, frame: str, windows: list[dict], texts: dict[str, str] | None = None,
              con: sqlite3.Connection | None = None) -> bool:
    """A frame's hand-placed quads become a verified anchor; the corrections
    ledger takes the moved quads. No retrack."""
    with transaction(con) as con:
        row = con.execute("select * from frames where record = ? and frame = ?", (record, frame)).fetchone()
        if row is None:
            con.execute("delete from frame_windows where record = ?", (record,))
            con.execute("delete from frames where record = ?", (record,))
            if not import_frames_into(con, record):
                return False
            row = con.execute("select * from frames where record = ? and frame = ?", (record, frame)).fetchone()
            if row is None:
                return False
        # The frame's windows by index, not by field: a head with two `board`
        # cells has two windows under one field name, and the page sends the
        # windows in the frame's own order.
        previous = _frame_windows(con, record, frame)
        was_anchor = bool(row["verified"])
        corrections = []
        for index, w in enumerate(windows):
            before = previous[index] if index < len(previous) and previous[index]["field"] == w["field"] else None
            if before and before["quad"] != w["quad"]:
                corrections.append({"kind": "quad", "record": record, "frame": frame, "field": w["field"],
                                    "proposedBy": "operator" if was_anchor else "tracker",
                                    "proposed": before["quad"], "final": w["quad"],
                                    "iou": quad_iou(before["quad"], w["quad"]), "inliers": row["inliers"]})
        out = []
        for index, w in enumerate(windows):
            before = previous[index] if index < len(previous) and previous[index]["field"] == w["field"] else None
            cw = dict(before or {"field": w["field"], "text": ""})
            cw["quad"] = w["quad"]
            if texts and w["field"] in texts:
                cw["text"] = texts[w["field"]]
            out.append(cw)
        con.execute("update frames set inliers = -1, anchor = ?, verified = 1, keys = ? where record = ? and frame = ?",
                    (int(frame[:-4]) if frame[:-4].isdigit() else 0, json.dumps(list(FRAME_KEYS)), record, frame))
        meta = con.execute("select keys, extra from frames where record = ? and frame = ''", (record,)).fetchone()
        if meta is not None:
            extra = json.loads(meta["extra"]) if meta["extra"] else {}
            anchors = [a for a in extra.get("_anchors", []) if a != frame] + [frame]
            extra["_anchors"] = sorted(anchors, key=lambda n: int(n[:-4]))
            keys = json.loads(meta["keys"]) if meta["keys"] else []
            if "_anchors" not in keys:
                keys.append("_anchors")
            con.execute("update frames set extra = ?, keys = ? where record = ? and frame = ''",
                        (json.dumps(extra), json.dumps(keys), record))
        con.execute("delete from frame_windows where record = ? and frame = ?", (record, frame))
        for i, w in enumerate(out):
            con.execute("insert into frame_windows values (?,?,?,?,?,?,?)",
                        (record, frame, i, w["field"], w.get("text", ""), json.dumps(w["quad"]), w.get("legibility")))
        _insert_corrections(con, corrections)
        return True


def import_frames_into(con: sqlite3.Connection, record: str) -> bool:
    path = FRAMES / record / "windows.json"
    if not path.exists():
        return False
    con.execute("delete from frame_windows where record = ?", (record,))
    con.execute("delete from frames where record = ?", (record,))
    _load_frames_file(con, path)
    return True


def save_labels(stem: str, frames: dict[str, dict], con: sqlite3.Connection | None = None) -> None:
    with transaction(con) as con:
        con.execute("delete from labels where video = ?", (stem,))
        if not frames:
            con.execute("insert into labels values (?,?,?,?,?)", (stem, "", "", None, None))
        for frame, fields in frames.items():
            source = fields.get("source")
            for field, text in fields.items():
                if field == "source":
                    continue
                con.execute("insert into labels values (?,?,?,?,?)", (stem, frame, field, text, source))


def set_frame_key(record: str, frame: str, key: str, con: sqlite3.Connection | None = None) -> None:
    """Record where a frame JPEG (or the record's `sheet.jpg`, `frame=""`)
    lives in the bucket. The dump does not carry it."""
    with transaction(con) as con:
        con.execute("update frames set s3_key = ? where record = ? and frame = ?", (key, record, frame))


def import_readings(path: Path) -> None:
    """The Swift reader's staging file -> `readings` and arithmetic `labels`,
    one transaction, then the two files dumped.

    The staging file is `{"record": stem, "readings": {...}, "labels": {...}}`:
    `readings` is the per-frame readings object the old writer wrote to
    `frames/<stem>/readings.json`; `labels` carries only arithmetic rows. An
    owner label for a frame is kept and no arithmetic row is added for it.
    The old writer emitted compact readings JSON, so the style is reset to
    `compact` for the record."""
    data = json.loads(Path(path).read_text())
    record = data["record"]
    readings = data.get("readings") or {}
    labels = data.get("labels") or {}
    con = connect()
    try:
        with con:
            con.execute("delete from readings where record = ?", (record,))
            con.execute("delete from meta where key = ?", ("readings-style:" + record,))
            con.execute("insert into meta values (?,?)", ("readings-style:" + record, "compact"))
            if not readings:
                con.execute("insert into readings values (?,?,?,?,?,?)", (record, "", "", None, None, -1))
            for i, (frame, fields) in enumerate(readings.items()):
                closes = int(bool(fields.get("closes")))
                for field, text in fields.items():
                    if field == "closes":
                        continue
                    con.execute("insert into readings values (?,?,?,?,?,?)",
                                (record, frame, field, text, closes, i))
            owner = {r["frame"] for r in con.execute(
                "select distinct frame from labels where video = ? and source = 'owner'", (record,))}
            con.execute("delete from labels where video = ? and (source is null or source != 'owner')", (record,))
            if not labels and not owner:
                con.execute("insert into labels values (?,?,?,?,?)", (record, "", "", None, None))
            for frame, fields in labels.items():
                if frame in owner:
                    continue
                source = fields.get("source", "arithmetic")
                for field, text in fields.items():
                    if field == "source":
                        continue
                    con.execute("insert into labels values (?,?,?,?,?)", (record, frame, field, text, source))
    finally:
        con.close()
    dump([LABELS_FILE, FRAMES / record / "readings.json"])


def _stamp() -> tuple[str, str]:
    """Now, and the commit the tools run from - what every ledger line carries."""
    import datetime  # noqa: PLC0415
    stamp = datetime.datetime.now().replace(microsecond=0).isoformat()
    try:
        build = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                               capture_output=True, text=True).stdout.strip() or "unknown"
    except Exception:  # noqa: BLE001
        build = "unknown"
    return stamp, build


def _insert_corrections(con: sqlite3.Connection, rows: list[dict]) -> None:
    # A row without a stamp (pinned from a frame, not through `add_corrections`)
    # is stamped here: `at` and `build` are what makes the ledger readable per
    # build, and a null would drop the line from every per-build report.
    stamped = None
    for row in rows:
        if not row.get("at") or not row.get("build"):
            stamped = stamped or _stamp()
            row = {**row, "at": row.get("at") or stamped[0], "build": row.get("build") or stamped[1]}
        extra = {k: v for k, v in row.items() if k not in ("at", "build", *CORRECTION_ORDER)}
        con.execute(
            "insert into corrections (at, build, kind, still, record, video, frame, field, proposedBy, "
            "proposed, final, iou, inliers, extra) values (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (row.get("at"), row.get("build"), row.get("kind"), row.get("still"), row.get("record"),
             row.get("video"), row.get("frame"), row.get("field"), row.get("proposedBy"),
             _correction_value(row["proposed"]) if row.get("proposed") is not None else None,
             _correction_value(row["final"]) if row.get("final") is not None else None,
             row.get("iou"), row.get("inliers"), json.dumps(extra) if extra else None))


def add_corrections(rows: list[dict], con: sqlite3.Connection | None = None) -> None:
    """Append the operator's corrections, stamped with the build they answered."""
    if not rows:
        return
    import datetime  # noqa: PLC0415
    stamp = datetime.datetime.now().replace(microsecond=0).isoformat()
    try:
        build = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                               capture_output=True, text=True).stdout.strip() or "unknown"
    except Exception:  # noqa: BLE001
        build = "unknown"
    with transaction(con) as con:
        _insert_corrections(con, [{"at": stamp, "build": build, **row} for row in rows])


def migrate(db: Path | None = None) -> bool:
    """Bring an older database up to `SCHEMA_VERSION` in place, keeping every
    row. The one migration so far adds `frames.s3_key`; a rebuild from the files
    cannot reproduce it, because `frames/` is gitignored and the keys are only
    known to the machine that uploaded them."""
    target = db or DB
    if not target.exists():
        return False
    try:
        with sqlite3.connect(target) as con:
            columns = {r[1] for r in con.execute("pragma table_info(frames)")}
            if "s3_key" not in columns:
                con.execute("alter table frames add column s3_key text")
            version = con.execute("select value from meta where key = 'schema_version'").fetchone()
            if not version or version[0] != SCHEMA_VERSION:
                con.execute("insert or replace into meta values ('schema_version', ?)", (SCHEMA_VERSION,))
        return True
    except sqlite3.DatabaseError:
        return False


def ensure_schema() -> None:
    """At server start: a missing or older database is migrated, else imported
    from the files."""
    try:
        migrate()
        with sqlite3.connect(DB) as con:
            version = con.execute("select value from meta where key = 'schema_version'").fetchone()
        if version and version[0] == SCHEMA_VERSION:
            return
    except sqlite3.DatabaseError:
        pass
    import_corpus()


def build(with_s3: bool = False) -> Path:
    """Alias for `import`, kept for a release (callers still say `build`)."""
    return import_corpus(with_s3)


def main() -> int:
    args = sys.argv[1:]
    if not args or args[0] not in ("import", "build", "dump", "check", "import-readings", "sql"):
        print(__doc__)
        return 2
    if args[0] in ("import", "build"):
        import_corpus(with_s3="--s3" in args)
        with sqlite3.connect(DB) as con:
            counts = {t: con.execute(f"select count(*) from {t}").fetchone()[0]
                      for t in ("fixtures", "entries", "windows", "media", "pairs",
                                "videos", "video_windows", "frames", "frame_windows",
                                "labels", "readings", "corrections")}
        print(f"{DB.relative_to(ROOT)}: " + ", ".join(f"{v} {k}" for k, v in counts.items()))
        return 0
    if args[0] == "import-readings":
        if len(args) != 2:
            print("usage: corpus_db.py import-readings <staging.json>")
            return 2
        import_readings(Path(args[1]))
        return 0
    if args[0] == "dump":
        for path in dump():
            print(path.relative_to(ROOT))
        return 0
    if args[0] == "check":
        stale = check()
        for line in stale:
            print(line)
        return 1 if stale else 0
    with sqlite3.connect(DB) as con:
        for row in con.execute(" ".join(args[1:])):
            print("\t".join("" if v is None else str(v) for v in row))
    return 0


if __name__ == "__main__":
    sys.exit(main())

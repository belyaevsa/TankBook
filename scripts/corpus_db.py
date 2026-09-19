#!/usr/bin/env python3
"""The corpus as one SQLite file - `Spike/ReceiptSpike/fixtures/corpus.sqlite`.

The files in git stay the source of truth (`pump/expected.csv`,
`receipts/expected.csv`, `pump/windows.json`, the `pump-live/README.md`
pairing tables, `CorpusPairTests.swift`); the ratchets read them and nothing
else. This script folds them into one database for querying, for the
annotator and for the bucket, and rebuilds it from scratch every time - it is
derived, committed (product owner, 2026-09-19: browsable from a checkout without
a build), and never edited by hand - a rebuild from unchanged inputs is
byte-identical, so the diff is only ever real corpus change.

    scripts/corpus_db.py build            # -> fixtures/corpus.sqlite
    scripts/corpus_db.py build --s3       # also marks which media are in the bucket
    scripts/corpus_db.py sql "select field, count(*) from windows group by 1"

Tables: fixtures (every still with its truth row, size, sha256), entries
(the per-fixture annotation state), windows (one row per number window,
quad as JSON plus its bounding box), media (Live records and videos, with
their bucket key and pairing; whether a movie is on THIS machine is not
recorded - `ls` answers that), pairs (the matched pump/receipt fills).
"""
from __future__ import annotations

import csv
import hashlib
import json
import re
import sqlite3
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIX = ROOT / "Spike" / "ReceiptSpike" / "fixtures"
DB = FIX / "corpus.sqlite"
S3_ENDPOINT = "https://storage.yandexcloud.net"
S3_BUCKET = "tankbook-corpus"
S3_MEDIA_PREFIX = "pump-live/"

SCHEMA = """
create table meta (key text primary key, value text);
create table fixtures (
  name text primary key, kind text not null, path text not null, bytes integer, sha256 text,
  width integer, height integer,
  liters text, unitPrice text, total text, fuelKind text, currency text, station text,
  split text);
create table entries (
  fixture text primary key references fixtures(name),
  rotationCW integer not null default 0, reviewed integer not null default 0,
  notOnDisplay text, csvDisagrees text);
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


def previous(db: Path) -> tuple[dict[str, tuple[int, int]], dict[str, tuple[int, int]]]:
    """What the last build knew and this one may not recompute: dimensions
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


def load_fixtures(con: sqlite3.Connection, known: dict[str, tuple[int, int]]) -> None:
    # decision 9: the frozen heldout draw; a pump still not listed is train.
    split: dict[str, str] = {}
    with (FIX / "pump" / "split.csv").open() as f:
        split = {r["filename"]: r["split"] for r in csv.DictReader(f)}
    for kind in ("pump", "receipts"):
        folder = FIX / kind
        with (folder / "expected.csv").open() as f:
            for row in csv.DictReader(f):
                path = folder / row["filename"]
                digest = sha256(path) if path.exists() else None
                w, h = known.get(digest) if digest in known else (dimensions(path) if path.exists() else (None, None))
                con.execute(
                    "insert into fixtures values (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    (row["filename"], "pump" if kind == "pump" else "receipt",
                     str(path.relative_to(ROOT)), path.stat().st_size if path.exists() else None, digest, w, h,
                     row.get("liters") or None, row.get("unitPrice") or None, row.get("total") or None,
                     row.get("fuelKind") or None, row.get("currency") or None, row.get("station") or None,
                     (split.get(row["filename"], "train") if kind == "pump" else None)))


def load_windows(con: sqlite3.Connection) -> None:
    ann = json.loads((FIX / "pump" / "windows.json").read_text())
    for name, entry in ann.items():
        if name.startswith("_"):
            con.execute("insert into meta values (?,?)", ("windows.json" + name, entry))
            continue
        con.execute("insert into entries values (?,?,?,?,?)",
                    (name, entry.get("rotationCW", 0), int(bool(entry.get("reviewed"))),
                     json.dumps(entry["notOnDisplay"]) if entry.get("notOnDisplay") else None,
                     json.dumps(entry["csvDisagrees"]) if entry.get("csvDisagrees") else None))
        for i, w in enumerate(entry.get("windows", [])):
            xs = [p[0] for p in w["quad"]]
            ys = [p[1] for p in w["quad"]]
            con.execute("insert into windows (fixture, ord, field, text, legibility, quad, x0, y0, x1, y1) "
                        "values (?,?,?,?,?,?,?,?,?,?)",
                        (name, i, w["field"], w.get("text", ""), w.get("legibility"), json.dumps(w["quad"]),
                         min(xs), min(ys), max(xs), max(ys)))


LIVE_ROW = re.compile(r"^\|\s*`?((?:live|video)-\d+[\w-]*?)(?:\.mov|\.mp4)?`?\s*\|\s*(\d+)[^|]*\|(.*)$")


def load_media(con: sqlite3.Connection, in_bucket: set[str] | None, known: dict[str, tuple[int, int]]) -> None:
    """The README's pairing tables are the record of what each movie is; the
    folder says what is on this machine; the bucket key is deterministic."""
    readme = (FIX / "pump-live" / "README.md").read_text().splitlines()
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
    folder = FIX / "pump-live"
    for path in list(folder.glob("live-*.*")) + list(folder.glob("video-*.*")):
        if path.suffix.lower() in (".mov", ".heic", ".mp4"):
            rows.setdefault(path.stem, {"frames": None, "paired": None, "note": None, "batch": None})
    for stem, info in sorted(rows.items()):
        for suffix in ((".mp4",) if stem.startswith("video-") else (".mov", ".heic")):
            path = folder / f"{stem}{suffix}"
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
    source = (ROOT / "ios/Tests/TankbookCoreTests/CorpusPairTests.swift").read_text()
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


def build(with_s3: bool = False) -> Path:
    known, media_known = previous(DB)
    tmp = DB.with_suffix(".sqlite.tmp")
    tmp.unlink(missing_ok=True)
    with sqlite3.connect(tmp) as con:
        con.executescript(SCHEMA)
        load_fixtures(con, known)
        load_windows(con)
        load_media(con, bucket_keys() if with_s3 else None, media_known)
        load_pairs(con)
        # The file is committed: a rebuild from unchanged inputs must be
        # byte-identical, so no timestamps, no git revision, and a VACUUM to
        # settle page layout.
        con.commit()
        con.execute("vacuum")
    tmp.replace(DB)
    return DB


def main() -> int:
    args = sys.argv[1:]
    if not args or args[0] not in ("build", "sql"):
        print(__doc__)
        return 2
    if args[0] == "build":
        build(with_s3="--s3" in args)
        with sqlite3.connect(DB) as con:
            counts = {t: con.execute(f"select count(*) from {t}").fetchone()[0]
                      for t in ("fixtures", "entries", "windows", "media", "pairs")}
        print(f"{DB.relative_to(ROOT)}: " + ", ".join(f"{v} {k}" for k, v in counts.items()))
        return 0
    with sqlite3.connect(DB) as con:
        for row in con.execute(" ".join(args[1:])):
            print("\t".join("" if v is None else str(v) for v in row))
    return 0


if __name__ == "__main__":
    sys.exit(main())

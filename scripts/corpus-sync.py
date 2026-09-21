#!/usr/bin/env python3
"""Sync the large fixture media with the `tankbook-corpus` bucket (Yandex Object Storage).

The git repo holds every annotation, README and small still image; the Live
Photo records under `Spike/ReceiptSpike/fixtures/pump-live/` (hundreds of MB)
live in the bucket instead and are gitignored. This script moves them either
way, by content: an object is skipped when its size and MD5 already match.

    scripts/corpus-sync.py pull            # bucket -> working tree (what a fresh machine runs)
    scripts/corpus-sync.py push            # working tree -> bucket (after new captures land)
    scripts/corpus-sync.py list

`push` also rebuilds `corpus.sqlite` (`scripts/corpus_db.py`) and uploads it
with the annotation files under `index/`, so the bucket carries the whole
corpus - media and truth - and not only the bytes git refuses.

`push` uploads the extracted frame JPEGs of every registered record (a `media`
row) to `pump-live/frames/<record>/` and records each one's key on
`frames.s3_key`; `frames/` is gitignored, so the bucket is where a fresh machine
gets them. `pull` fetches a record's frames only on request:
`pull --frames <record>` or `pull --frames all`. Set `DRY_RUN=1` to report what
a push would send without touching the bucket.

Credentials: a static access key for the `tankbook-corpus-rw` service account,
read from `~/.config/tankbook/corpus-s3.env` (AWS_ACCESS_KEY_ID /
AWS_SECRET_ACCESS_KEY) or from the environment. Never in the repo
(`docs/SECURITY.md`). How to get one: Spike/ReceiptSpike/fixtures/pump-live/README.md.
Needs `boto3` (`pip install boto3`; the ml venv has it via the `corpus` extra).
"""

from __future__ import annotations

import hashlib
import os
import sys
from pathlib import Path

ENDPOINT = "https://storage.yandexcloud.net"
REGION = "ru-central1"
BUCKET = "tankbook-corpus"
ROOT = Path(__file__).resolve().parent.parent
# (bucket prefix, local folder, glob patterns) - extend as more media leaves git.
SETS = [
    # Only REGISTERED media leave the machine: a clip is named live-/video- by the
    # intake (corpus-intake skill) once it is in the README; a raw drop in the folder
    # is not the corpus yet and must not reach the bucket.
    ("pump-live/", ROOT / "Spike/ReceiptSpike/fixtures/pump-live", ("live-*.mov", "live-*.heic", "video-*.mp4")),
]
# The annotated data, pushed beside the media so the bucket is a complete copy.
FIX = ROOT / "Spike/ReceiptSpike/fixtures"
INDEX = [
    ("index/corpus.sqlite", FIX / "corpus.sqlite"),
    ("index/pump/windows.json", FIX / "pump/windows.json"),
    ("index/pump/expected.csv", FIX / "pump/expected.csv"),
    ("index/receipts/expected.csv", FIX / "receipts/expected.csv"),
    ("index/receipts/stations.md", FIX / "receipts/stations.md"),
    ("index/pump-live/README.md", FIX / "pump-live/README.md"),
    ("index/pump-live/videos.json", FIX / "pump-live/videos.json"),
    ("index/pump-live/video-labels.json", FIX / "pump-live/video-labels.json"),
    ("index/high-water.json", FIX / "high-water.json"),
]
# The extracted frame JPEGs (gitignored, 4.4 GB on 2026-09-21) of the records
# that are registered in the README; a raw folder drop is not corpus yet.
FRAMES_DIR = ROOT / "Spike/ReceiptSpike/fixtures/pump-live/frames"
FRAMES_PREFIX = "pump-live/frames/"
DRY_RUN = os.environ.get("DRY_RUN") == "1"


def credentials() -> None:
    env = Path.home() / ".config/tankbook/corpus-s3.env"
    if env.exists():
        for line in env.read_text().splitlines():
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())
    if not os.environ.get("AWS_ACCESS_KEY_ID"):
        sys.exit("no credentials: see Spike/ReceiptSpike/fixtures/pump-live/README.md -> Access")


def client():
    import boto3  # noqa: PLC0415 - optional dependency, imported when used

    return boto3.client("s3", endpoint_url=ENDPOINT, region_name=REGION)


def md5(path: Path) -> str:
    h = hashlib.md5()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def remote_index(s3, prefix: str) -> dict[str, tuple[int, str]]:
    out = {}
    token = None
    while True:
        kwargs = {"Bucket": BUCKET, "Prefix": prefix}
        if token:
            kwargs["ContinuationToken"] = token
        page = s3.list_objects_v2(**kwargs)
        for obj in page.get("Contents", []):
            out[obj["Key"]] = (obj["Size"], obj["ETag"].strip('"'))
        if not page.get("IsTruncated"):
            return out
        token = page["NextContinuationToken"]


def corpus_db():
    sys.path.insert(0, str(ROOT / "scripts"))
    import importlib
    return importlib.import_module("corpus_db")


def registered_records() -> list[str]:
    """The stems with a `media` row - the README names their clip, so their
    frames are corpus material."""
    con = corpus_db().connect()
    try:
        return sorted({Path(name).stem for (name,) in con.execute("select name from media")})
    finally:
        con.close()


def record_frame_key(record: str, name: str, key: str) -> None:
    """`frames.s3_key`: a frame's own row, the record's meta row for `sheet.jpg`."""
    corpus_db().set_frame_key(record, "" if name == "sheet.jpg" else name, key)


def push(s3, dry: bool = False) -> None:
    for prefix, folder, patterns in SETS:
        remote = remote_index(s3, prefix)
        files = sorted(p for pattern in patterns for p in folder.glob(pattern))
        sent = skipped = 0
        sent_bytes = 0
        for path in files:
            key = prefix + path.name
            size = path.stat().st_size
            # A multipart ETag (it carries a "-") is not an MD5: size alone
            # decides for those, as pull already does.
            if key in remote and remote[key][0] == size and ("-" in remote[key][1] or remote[key][1] == md5(path)):
                skipped += 1
                continue
            if not dry:
                s3.upload_file(str(path), BUCKET, key)
                print(f"  up {key} ({size // 1024} KB)")
            sent += 1
            sent_bytes += size
        label = "to upload" if dry else "uploaded"
        print(f"{prefix}: {sent} {label}, {skipped} already there, {sent_bytes // (1 << 20)} MB")


def push_frames(s3, dry: bool = False) -> None:
    """Every registered record's frame JPEGs (and its `sheet.jpg`) to
    `pump-live/frames/<record>/`. After an upload the key lands on
    `frames.s3_key`; a dry run only reports."""
    if not dry:
        corpus_db().ensure_schema()
    remote = remote_index(s3, FRAMES_PREFIX)
    sent = skipped = 0
    sent_bytes = 0
    for record in registered_records():
        folder = FRAMES_DIR / record
        if not folder.is_dir():
            continue
        for path in sorted(folder.glob("*.jpg")):
            key = f"{FRAMES_PREFIX}{record}/{path.name}"
            size = path.stat().st_size
            present = key in remote and remote[key][0] == size and ("-" in remote[key][1] or remote[key][1] == md5(path))
            if present:
                skipped += 1
            else:
                if not dry:
                    s3.upload_file(str(path), BUCKET, key)
                sent += 1
                sent_bytes += size
            # Set the key whenever the object is in the bucket, not only on a
            # fresh upload: a rebuild from the gitignored frames cannot carry it.
            if not dry:
                record_frame_key(record, path.name, key)
    label = "to upload" if dry else "uploaded"
    print(f"{FRAMES_PREFIX}: {sent} {label}, {skipped} already there, {sent_bytes // (1 << 20)} MB")


def pull_frames(s3, selector: str) -> None:
    """One record's frames (`--frames <record>`) or every registered record's
    (`--frames all`). A fresh machine can also re-extract from the movies."""
    records = registered_records()
    if selector == "all":
        wanted = records
    else:
        # A record's full stem, or its short id (`video-011` for
        # `video-011-gilbarco-...`).
        wanted = [r for r in records if r == selector or r.startswith(selector + "-")]
        if not wanted:
            sys.exit(f"unknown record: {selector} (use --frames all, or a media stem)")
    got = skipped = 0
    for record in wanted:
        prefix = f"{FRAMES_PREFIX}{record}/"
        folder = FRAMES_DIR / record
        folder.mkdir(parents=True, exist_ok=True)
        for key, (size, etag) in sorted(remote_index(s3, prefix).items()):
            path = folder / key[len(prefix):]
            if path.exists() and path.stat().st_size == size and ("-" in etag or md5(path) == etag):
                skipped += 1
                continue
            s3.download_file(BUCKET, key, str(path))
            got += 1
            print(f"  down {key} ({size // 1024} KB)")
    print(f"{FRAMES_PREFIX}: {got} downloaded, {skipped} already local")



def push_index(s3) -> None:
    sys.path.insert(0, str(ROOT / "scripts"))
    import corpus_db  # noqa: PLC0415

    # The database is the write store (PU.36a): it is never rebuilt from the
    # files here - a rebuild while the annotator writes it corrupted it once
    # (2026-09-21). Only the bucket flags are refreshed, and a stale dump is a
    # refusal, not something to repair silently.
    stale = corpus_db.check()
    if stale:
        for line in stale:
            print(line)
        raise SystemExit("corpus files are stale against the database - run scripts/corpus_db.py dump, then push again")
    corpus_db.mark_in_bucket(corpus_db.bucket_keys())
    remote = remote_index(s3, "index/")
    sent = skipped = 0
    for key, path in INDEX:
        size = path.stat().st_size
        if key in remote and remote[key][0] == size and remote[key][1] == md5(path):
            skipped += 1
            continue
        s3.upload_file(str(path), BUCKET, key)
        sent += 1
        print(f"  up {key} ({size // 1024} KB)")
    print(f"index/: {sent} uploaded, {skipped} already there")


def pull(s3) -> None:
    for prefix, folder, _ in SETS:
        folder.mkdir(parents=True, exist_ok=True)
        got = skipped = 0
        for key, (size, etag) in sorted(remote_index(s3, prefix).items()):
            path = folder / key[len(prefix):]
            if path.exists() and path.stat().st_size == size and ("-" in etag or md5(path) == etag):
                skipped += 1
                continue
            s3.download_file(BUCKET, key, str(path))
            got += 1
            print(f"  down {key} ({size // 1024} KB)")
        print(f"{prefix}: {got} downloaded, {skipped} already local")


def main() -> int:
    args = sys.argv[1:]
    if not args or args[0] not in ("push", "pull", "list"):
        print(__doc__)
        return 2
    credentials()
    s3 = client()
    if args[0] == "list":
        for prefix in [p for p, _, _ in SETS] + [FRAMES_PREFIX, "index/"]:
            index = remote_index(s3, prefix)
            print(f"{prefix}: {len(index)} objects, {sum(s for s, _ in index.values()) // (1 << 20)} MB")
        return 0
    if args[0] == "push":
        if DRY_RUN:
            push(s3, dry=True)
            push_frames(s3, dry=True)
            print("DRY_RUN=1: nothing uploaded")
            return 0
        push(s3)
        push_frames(s3)
        push_index(s3)
        return 0
    selector = None
    if "--frames" in args:
        i = args.index("--frames")
        if i + 1 >= len(args):
            print("usage: corpus-sync.py pull [--frames <record>|all]")
            return 2
        selector = args[i + 1]
    if selector is None:
        pull(s3)
    else:
        pull_frames(s3, selector)
    return 0


if __name__ == "__main__":
    sys.exit(main())

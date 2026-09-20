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
    ("index/high-water.json", FIX / "high-water.json"),
]


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


def push(s3) -> None:
    for prefix, folder, patterns in SETS:
        remote = remote_index(s3, prefix)
        files = sorted(p for pattern in patterns for p in folder.glob(pattern))
        sent = skipped = 0
        for path in files:
            key = prefix + path.name
            size = path.stat().st_size
            # A multipart ETag (it carries a "-") is not an MD5: size alone
            # decides for those, as pull already does.
            if key in remote and remote[key][0] == size and ("-" in remote[key][1] or remote[key][1] == md5(path)):
                skipped += 1
                continue
            s3.upload_file(str(path), BUCKET, key)
            sent += 1
            print(f"  up {key} ({size // 1024} KB)")
        print(f"{prefix}: {sent} uploaded, {skipped} already there")


def push_index(s3) -> None:
    sys.path.insert(0, str(ROOT / "scripts"))
    import corpus_db  # noqa: PLC0415

    corpus_db.build(with_s3=True)
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
    if len(sys.argv) != 2 or sys.argv[1] not in ("push", "pull", "list"):
        print(__doc__)
        return 2
    credentials()
    s3 = client()
    if sys.argv[1] == "list":
        for prefix in [p for p, _, _ in SETS] + ["index/"]:
            index = remote_index(s3, prefix)
            print(f"{prefix}: {len(index)} objects, {sum(s for s, _ in index.values()) // (1 << 20)} MB")
    elif sys.argv[1] == "push":
        push(s3)
        push_index(s3)
    else:
        pull(s3)
    return 0


if __name__ == "__main__":
    sys.exit(main())

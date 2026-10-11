#!/usr/bin/env python3
"""Sync the large fixture media with the `tankbook-corpus` container (Azure Blob Storage).

The git repo holds every annotation, README and small still image; the Live
Photo records under `Spike/ReceiptSpike/fixtures/pump-live/` (hundreds of MB)
live in the bucket instead and are gitignored. This script moves them either
way, by content: an object is skipped when its size and MD5 already match.

    scripts/corpus-sync.py pull            # bucket -> working tree (what a fresh machine runs)
    scripts/corpus-sync.py push            # working tree -> bucket (after new captures land)
    scripts/corpus-sync.py list
    scripts/corpus-sync.py push --models   # the trained models of ml/pump-reader/models.json
    scripts/corpus-sync.py pull --models <id>|all

`push` also rebuilds `corpus.sqlite` (`scripts/corpus_db.py`) and uploads it
with the annotation files under `index/`, so the bucket carries the whole
corpus - media and truth - and not only the bytes git refuses.

`push` uploads the extracted frame JPEGs of every registered record (a `media`
row) to `pump-live/frames/<record>/` and records each one's key on
`frames.s3_key`; `frames/` is gitignored, so the bucket is where a fresh machine
gets them. `pull` fetches a record's frames only on request:
`pull --frames <record>` or `pull --frames all`. Set `DRY_RUN=1` to report what
a push would send without touching the bucket.

`push --models` mirrors every model the pump reader has trained (the manifest
`ml/pump-reader/models.json`, the table in docs/EXTRACTION.md -> "Model registry")
to `models/<id>/`: each file under its repository-relative path, plus
`models/<id>/meta.json` - the manifest entry with every file's size and sha256 and
the commit it was pushed from. Candidate models live in gitignored `.out/`
folders, so the bucket is their only copy off the training machine.

The store is the `tankbook-corpus` container of the `tankbookstorage` account
(resource group `tankbook`, North Europe). "Bucket" below means that container.

Credentials, first match wins, read from `~/.config/tankbook/corpus-azure.env`
or from the environment - never in the repo (`docs/SECURITY.md`):
  AZURE_STORAGE_CONNECTION_STRING   the account's connection string
  AZURE_STORAGE_SAS_TOKEN           a container SAS (read/write/list)
  neither                           the `az login` session; needs the
                                    "Storage Blob Data Contributor" role on the account
How to get one: Spike/ReceiptSpike/fixtures/pump-live/README.md -> Access.
Needs `azure-storage-blob` and `azure-identity` (the ml venv has them via the
`corpus` extra).
"""

from __future__ import annotations

import hashlib
import mimetypes
import os
import sys
from pathlib import Path

ACCOUNT_URL = "https://tankbookstorage.blob.core.windows.net"
CONTAINER = "tankbook-corpus"
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
MODELS_FILE = ROOT / "ml/pump-reader/models.json"
MODELS_PREFIX = "models/"


def credentials() -> None:
    env = Path.home() / ".config/tankbook/corpus-azure.env"
    if env.exists():
        for line in env.read_text().splitlines():
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())


# A block is 4 MB and blocks go one at a time, so a dropped connection costs
# one block's retry instead of several parallel blocks competing for a thin
# link; long timeouts and many retries keep a 35 MB corpus.sqlite alive on a
# slow or lossy one.
BLOCK = 4 * 1024 * 1024
TRANSFER = {"max_single_put_size": BLOCK, "max_block_size": BLOCK, "max_single_get_size": BLOCK,
            "max_chunk_get_size": BLOCK, "connection_timeout": 60, "read_timeout": 600, "retry_total": 15}


def client():
    from azure.storage.blob import ContainerClient  # noqa: PLC0415 - optional dependency, imported when used

    if os.environ.get("AZURE_STORAGE_CONNECTION_STRING"):
        return ContainerClient.from_connection_string(os.environ["AZURE_STORAGE_CONNECTION_STRING"], CONTAINER,
                                                      **TRANSFER)
    if os.environ.get("AZURE_STORAGE_SAS_TOKEN"):
        return ContainerClient(ACCOUNT_URL, CONTAINER, credential=os.environ["AZURE_STORAGE_SAS_TOKEN"], **TRANSFER)
    from azure.identity import AzureCliCredential  # noqa: PLC0415

    return ContainerClient(ACCOUNT_URL, CONTAINER, credential=AzureCliCredential(), **TRANSFER)


def md5(path: Path) -> str:
    h = hashlib.md5()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def remote_index(blobs, prefix: str) -> dict[str, tuple[int, str]]:
    """Key -> (size, hex Content-MD5). The MD5 is "" for a blob stored without
    one; size alone decides for those."""
    out = {}
    for blob in blobs.list_blobs(name_starts_with=prefix):
        digest = blob.content_settings.content_md5
        out[blob.name] = (blob.size, bytes(digest).hex() if digest else "")
    return out


def same(path: Path, remote: tuple[int, str] | None) -> bool:
    """The local file and the blob hold the same bytes, by size and MD5."""
    return remote is not None and path.exists() and path.stat().st_size == remote[0] and (
        not remote[1] or md5(path) == remote[1])


def upload(blobs, path: Path, key: str) -> None:
    """One file to one blob, with its Content-MD5 set so the next run can skip it."""
    from azure.storage.blob import ContentSettings  # noqa: PLC0415

    settings = ContentSettings(content_type=mimetypes.guess_type(path.name)[0] or "application/octet-stream",
                               content_md5=bytearray.fromhex(md5(path)))
    with path.open("rb") as f:
        blobs.upload_blob(key, f, overwrite=True, max_concurrency=1, content_settings=settings)


def download(blobs, key: str, path: Path) -> None:
    """Into a temporary name first, so an interrupted pull never leaves a short
    file that a size check could mistake for a finished one."""
    part = path.with_name(path.name + ".part")
    with part.open("wb") as f:
        blobs.download_blob(key, max_concurrency=1).readinto(f)
    part.replace(path)


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


def push(blobs, dry: bool = False) -> None:
    for prefix, folder, patterns in SETS:
        remote = remote_index(blobs, prefix)
        files = sorted(p for pattern in patterns for p in folder.glob(pattern))
        sent = skipped = 0
        sent_bytes = 0
        for path in files:
            key = prefix + path.name
            size = path.stat().st_size
            if same(path, remote.get(key)):
                skipped += 1
                continue
            if not dry:
                upload(blobs, path, key)
                print(f"  up {key} ({size // 1024} KB)")
            sent += 1
            sent_bytes += size
        label = "to upload" if dry else "uploaded"
        print(f"{prefix}: {sent} {label}, {skipped} already there, {sent_bytes // (1 << 20)} MB")


def push_frames(blobs, dry: bool = False) -> None:
    """Every registered record's frame JPEGs (and its `sheet.jpg`) to
    `pump-live/frames/<record>/`. After an upload the key lands on
    `frames.s3_key`; a dry run only reports."""
    if not dry:
        corpus_db().ensure_schema()
    remote = remote_index(blobs, FRAMES_PREFIX)
    sent = skipped = 0
    sent_bytes = 0
    for record in registered_records():
        folder = FRAMES_DIR / record
        if not folder.is_dir():
            continue
        for path in sorted(folder.glob("*.jpg")):
            key = f"{FRAMES_PREFIX}{record}/{path.name}"
            size = path.stat().st_size
            if same(path, remote.get(key)):
                skipped += 1
            else:
                if not dry:
                    upload(blobs, path, key)
                sent += 1
                sent_bytes += size
            # Set the key whenever the object is in the bucket, not only on a
            # fresh upload: a rebuild from the gitignored frames cannot carry it.
            if not dry:
                record_frame_key(record, path.name, key)
    label = "to upload" if dry else "uploaded"
    print(f"{FRAMES_PREFIX}: {sent} {label}, {skipped} already there, {sent_bytes // (1 << 20)} MB")


def pull_frames(blobs, selector: str) -> None:
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
        for key, remote in sorted(remote_index(blobs, prefix).items()):
            path = folder / key[len(prefix):]
            if same(path, remote):
                skipped += 1
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            download(blobs, key, path)
            got += 1
            print(f"  down {key} ({remote[0] // 1024} KB)")
    print(f"{FRAMES_PREFIX}: {got} downloaded, {skipped} already local")



def push_index(blobs) -> None:
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
    remote = remote_index(blobs, "index/")
    sent = skipped = 0
    for key, path in INDEX:
        size = path.stat().st_size
        if same(path, remote.get(key)):
            skipped += 1
            continue
        upload(blobs, path, key)
        sent += 1
        print(f"  up {key} ({size // 1024} KB)")
    print(f"index/: {sent} uploaded, {skipped} already there")


def pull(blobs) -> None:
    for prefix, folder, _ in SETS:
        folder.mkdir(parents=True, exist_ok=True)
        got = skipped = 0
        for key, remote in sorted(remote_index(blobs, prefix).items()):
            path = folder / key[len(prefix):]
            if same(path, remote):
                skipped += 1
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            download(blobs, key, path)
            got += 1
            print(f"  down {key} ({remote[0] // 1024} KB)")
        print(f"{prefix}: {got} downloaded, {skipped} already local")


def model_files(entry: dict) -> list[Path]:
    """Every file of a manifest entry; a package directory contributes each file inside it."""
    out: list[Path] = []
    for rel in entry["files"]:
        path = ROOT / rel
        out += sorted(p for p in path.rglob("*") if p.is_file()) if path.is_dir() else [path]
    return out


def model_meta(entry: dict, commit: str, pushed_at: str) -> dict:
    """`meta.json` for one model: the manifest entry, and each file's size and sha256."""
    files = []
    for path in model_files(entry):
        h = hashlib.sha256()
        with path.open("rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        files.append({"path": str(path.relative_to(ROOT)), "size": path.stat().st_size, "sha256": h.hexdigest()})
    return dict(entry, files=files, totalBytes=sum(f["size"] for f in files), pushedFromCommit=commit,
                pushedAt=pushed_at)


def push_models(blobs, dry: bool = False) -> None:
    import json
    import subprocess
    from datetime import datetime, timezone

    manifest = json.loads(MODELS_FILE.read_text())
    commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    pushed_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    remote = remote_index(blobs, MODELS_PREFIX)
    sent = skipped = 0
    sent_bytes = 0
    for entry in manifest["models"]:
        missing = [rel for rel in entry["files"] if not (ROOT / rel).exists()]
        if missing:
            print(f"  skip {entry['id']}: missing {missing}")
            continue
        for path in model_files(entry):
            key = f"{MODELS_PREFIX}{entry['id']}/{path.relative_to(ROOT)}"
            size = path.stat().st_size
            if same(path, remote.get(key)):
                skipped += 1
                continue
            sent += 1
            sent_bytes += size
            if not dry:
                upload(blobs, path, key)
        meta = json.dumps(model_meta(entry, commit, pushed_at), indent=1).encode()
        if not dry:
            from azure.storage.blob import ContentSettings  # noqa: PLC0415

            blobs.upload_blob(f"{MODELS_PREFIX}{entry['id']}/meta.json", meta, overwrite=True,
                              content_settings=ContentSettings(content_type="application/json",
                                                               content_md5=bytearray(hashlib.md5(meta).digest())))
        print(f"  {entry['id']}: {entry['status']}")
    print(f"models/: {sent} files uploaded ({sent_bytes // (1 << 20)} MB), {skipped} already there"
          + (" (dry run)" if dry else ""))


def pull_models(blobs, selector: str) -> None:
    import json

    manifest = json.loads(MODELS_FILE.read_text())
    ids = [m["id"] for m in manifest["models"]] if selector == "all" else [selector]
    got = skipped = 0
    for model in ids:
        prefix = f"{MODELS_PREFIX}{model}/"
        for key, remote in sorted(remote_index(blobs, prefix).items()):
            rel = key[len(prefix):]
            if rel == "meta.json":
                continue
            path = ROOT / rel
            if same(path, remote):
                skipped += 1
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            download(blobs, key, path)
            got += 1
    print(f"models/: {got} downloaded, {skipped} already local")


def main() -> int:
    args = sys.argv[1:]
    if not args or args[0] not in ("push", "pull", "list"):
        print(__doc__)
        return 2
    credentials()
    blobs = client()
    if args[0] == "list":
        for prefix in [p for p, _, _ in SETS] + [FRAMES_PREFIX, "index/", MODELS_PREFIX]:
            index = remote_index(blobs, prefix)
            print(f"{prefix}: {len(index)} objects, {sum(s for s, _ in index.values()) // (1 << 20)} MB")
        return 0
    if args[0] == "push" and "--models" in args:
        push_models(blobs, dry=DRY_RUN)
        return 0
    if args[0] == "pull" and "--models" in args:
        i = args.index("--models")
        if i + 1 >= len(args):
            print("usage: corpus-sync.py pull --models <id>|all")
            return 2
        pull_models(blobs, args[i + 1])
        return 0
    if args[0] == "push":
        if DRY_RUN:
            push(blobs, dry=True)
            push_frames(blobs, dry=True)
            print("DRY_RUN=1: nothing uploaded")
            return 0
        push(blobs)
        push_frames(blobs)
        push_index(blobs)
        return 0
    selector = None
    if "--frames" in args:
        i = args.index("--frames")
        if i + 1 >= len(args):
            print("usage: corpus-sync.py pull [--frames <record>|all]")
            return 2
        selector = args[i + 1]
    if selector is None:
        pull(blobs)
    else:
        pull_frames(blobs, selector)
    return 0


if __name__ == "__main__":
    sys.exit(main())

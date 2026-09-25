"""`corpus-sync.py`'s model mirror: a manifest entry expands a package directory into its files,
and `meta.json` records every file's size and sha256 beside the entry's own fields."""

from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("corpus_sync", Path(__file__).with_name("corpus-sync.py"))
cs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cs)


def test_meta_expands_packages_and_hashes_every_file(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(cs, "ROOT", tmp_path)
    pkg = tmp_path / "Model.mlpackage" / "Data"
    pkg.mkdir(parents=True)
    (pkg / "weights.bin").write_bytes(b"abc")
    (tmp_path / "ckpt.pt").write_bytes(b"xyz!")
    entry = {"id": "m", "status": "shipped", "files": ["Model.mlpackage", "ckpt.pt"]}
    meta = cs.model_meta(entry, "deadbeef", "2026-09-25T00:00:00Z")
    by_path = {f["path"]: f for f in meta["files"]}
    assert set(by_path) == {"Model.mlpackage/Data/weights.bin", "ckpt.pt"}
    assert by_path["ckpt.pt"]["sha256"] == hashlib.sha256(b"xyz!").hexdigest()
    assert meta["totalBytes"] == 7 and meta["status"] == "shipped" and meta["pushedFromCommit"] == "deadbeef"


def test_manifest_lists_only_existing_files_for_shipped_models() -> None:
    import json

    manifest = json.loads((Path(__file__).resolve().parent.parent / "ml/pump-reader/models.json").read_text())
    shipped = [m for m in manifest["models"] if m["status"] == "shipped"]
    assert {m["id"] for m in shipped} == {"pumpsegments-r6", "rowseg-seg-r1"}
    assert all(m["files"][0].startswith("ios/App/Resources/") for m in shipped)

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


def test_shipped_models_are_exactly_the_models_the_app_bundles() -> None:
    import json

    root = Path(__file__).resolve().parent.parent
    manifest = json.loads((root / "ml/pump-reader/models.json").read_text())
    shipped = {m["files"][0] for m in manifest["models"] if m["status"] == "shipped"}
    bundled = {f"ios/App/Resources/{p.name}" for p in (root / "ios/App/Resources").iterdir()
               if p.suffix in (".mlpackage", ".mlmodel")}
    assert shipped == bundled

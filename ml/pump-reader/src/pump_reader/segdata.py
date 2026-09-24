"""CLI: ``python -m pump_reader.segdata [--out .out/seg] [--edge 1024] [--frame-step 1]``.

The oriented row segmenter's data (PU.76 spike, option B - PixelLink's pixel + link
formulation): the same sources as `detdata` - TRAIN stills, the owner-verified
(hand-placed) frames of train records, and the non-pump negatives - but each
window keeps its HAND QUAD, not the quad's upright bound. Masks and links are
rasterised from the quads at training time (`segtrain`), so rotation
augmentation carries them exactly.

Output: ``<out>/train/*.jpg``, ``<out>/heldout/*.jpg`` and one ``index.json`` per
directory: ``[{"image", "source", "quads": [[[x, y] x4] ...]}]`` with quads
normalised to the saved (upright) image. Heldout stills are written for the
measurement only; decision 9 is asserted as in `detdata`. ``heldout2`` is
neither trained on nor measured here.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageOps

from pump_reader.detdata import FIX, FRAMES, NEGATIVE_FOLDERS, ROOT, _image_path, rotate_quad, save

sys.path.insert(0, str(ROOT / "scripts"))
import corpus_db  # noqa: E402


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="pump_reader.segdata")
    parser.add_argument("--out", type=Path, default=ROOT / "ml" / "pump-reader" / ".out" / "seg")
    parser.add_argument("--edge", type=int, default=1024)
    parser.add_argument("--frame-step", type=int, default=1,
                        help="keep one in N owner-verified frames per record (1 = all)")
    parser.add_argument("--db", type=Path, default=None)
    args = parser.parse_args(argv)
    con = corpus_db.connect(args.db)
    train_dir, held_dir = args.out / "train", args.out / "heldout"
    for d in (train_dir, held_dir):
        d.mkdir(parents=True, exist_ok=True)
    train: list[dict] = []
    held: list[dict] = []
    counts = {"train_stills": 0, "heldout_stills": 0, "verified_frames": 0, "negatives": 0,
              "train_quads": 0, "heldout_quads": 0}
    try:
        stills = con.execute(
            "select e.fixture, e.rotationCW, f.split, f.path from entries e join fixtures f on f.name = e.fixture "
            "where f.kind = 'pump' and exists(select 1 from windows w where w.fixture = e.fixture) "
            "order by e.ord").fetchall()
        for row in stills:
            if row["split"] not in ("train", "heldout", None):
                continue
            heldout = row["split"] == "heldout"
            rotation = row["rotationCW"] or 0
            im = ImageOps.exif_transpose(Image.open(_image_path(row["path"])))
            if rotation:
                im = im.rotate(-rotation, expand=True)
            dst = (held_dir if heldout else train_dir) / (Path(row["fixture"]).stem + ".jpg")
            save(im, dst, args.edge)
            quads = [rotate_quad(json.loads(q["quad"]), rotation) for q in con.execute(
                "select quad from windows where fixture = ? order by ord", (row["fixture"],))]
            (held if heldout else train).append({"image": dst.name, "source": row["fixture"], "quads": quads})
            counts["heldout_stills" if heldout else "train_stills"] += 1
            counts["heldout_quads" if heldout else "train_quads"] += len(quads)

        # Owner-verified frames only: a tracker's box carries its drift (PU.66).
        for record in corpus_db.tracked_records(con):
            t = corpus_db.tracked(record, con=con)
            if "_video" not in t and t.get("_split") != "train":
                continue
            names = sorted((n for n, f in t["frames"].items()
                            if f.get("verified") and not f.get("skipped") and f.get("windows")),
                           key=lambda n: int(n[:-4]))
            for i, frame in enumerate(names):
                if i % args.frame_step:
                    continue
                dst = train_dir / f"{record}-{frame}"
                save(Image.open(FRAMES / record / frame), dst, args.edge)
                quads = [wd["quad"] for wd in t["frames"][frame]["windows"]]
                train.append({"image": dst.name, "source": f"{record}/{frame}", "quads": quads})
                counts["verified_frames"] += 1
                counts["train_quads"] += len(quads)

        for sub in NEGATIVE_FOLDERS:
            for path in sorted((FIX / sub).iterdir()):
                if path.suffix.lower() not in (".jpg", ".jpeg", ".png", ".heic"):
                    continue
                try:
                    im = ImageOps.exif_transpose(Image.open(path))
                except Exception:
                    continue
                dst = train_dir / f"neg-{sub}-{path.stem}.jpg"
                save(im, dst, args.edge)
                train.append({"image": dst.name, "source": f"{sub}/{path.name}", "quads": []})
                counts["negatives"] += 1

        heldout_names = corpus_db.heldout_names(con)
        heldout_records: set[str] = set()
        if heldout_names:
            placeholders = ",".join("?" * len(heldout_names))
            heldout_records = {r["record"] for r in con.execute(
                f"select record from frames where frame = '' and still in ({placeholders})", tuple(heldout_names))}
        for r in train:
            assert r["source"] not in heldout_names, f"heldout still in train: {r['source']}"
            assert r["source"].split("/")[0] not in heldout_records, f"heldout record in train: {r['source']}"
        (train_dir / "index.json").write_text(json.dumps(train))
        (held_dir / "index.json").write_text(json.dumps(held))
        (args.out / "counts.json").write_text(json.dumps(counts, indent=1))
        print(json.dumps(counts))
        return 0
    finally:
        con.close()


if __name__ == "__main__":
    sys.exit(main())

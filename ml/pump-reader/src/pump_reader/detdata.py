"""CLI: ``python -m pump_reader.detdata [--out .out/det] [--frame-step 5] [--edge 1024]``.

The row detector's training set (PU.33), built from the database and nothing else:

* every TRAIN still (`fixtures.split`, decision 9) with its annotated windows;
* every k-th tracked frame of a train still's Live record and of the labelled
  video frames (`frames` / `frame_windows` / `labels`) - neighbours at 30 fps are
  near copies, so one in ``--frame-step`` carries the information;
* negatives: the receipt, screenshot, fiscal and expense fixtures, which hold
  printed digits but no display row.

One class, ``digit-row``: the axis-aligned box of each window quad (the
detector proposes boxes; the reader warps by the box, so a skewed display
costs a little IoU, which the measurement in `detmeasure` reports). Written
in Create ML's object-detector layout: ``<out>/train/*.jpg`` +
``annotations.json`` with centre-based pixel coordinates. The HELDOUT stills
go to ``<out>/heldout/`` with their own annotations for the measurement only -
never into ``train``, asserted here.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageOps

try:
    import pillow_heif

    pillow_heif.register_heif_opener()
except Exception:  # pragma: no cover
    pass

ROOT = Path(__file__).resolve().parents[4]
FIX = ROOT / "Spike" / "ReceiptSpike" / "fixtures"
LIVE = FIX / "pump-live"
FRAMES = LIVE / "frames"
NEGATIVE_FOLDERS = ("receipts", "screenshots", "fiscal", "expenses")
LABEL = "digit-row"
sys.path.insert(0, str(ROOT / "scripts"))
import corpus_db  # noqa: E402


def rotate_quad(quad: list[list[float]], rotation: int) -> list[list[float]]:
    """A quad over the EXIF-oriented image, turned so the display reads upright
    (the same turn `PumpPanelLocator.rotatedRGB` applies to the pixels)."""
    r = ((rotation % 360) + 360) % 360
    out = []
    for x, y in quad:
        if r == 90:
            out.append([1 - y, x])
        elif r == 180:
            out.append([1 - x, 1 - y])
        elif r == 270:
            out.append([y, 1 - x])
        else:
            out.append([x, y])
    return out


def bbox(quad: list[list[float]], w: int, h: int) -> dict:
    xs = [p[0] * w for p in quad]
    ys = [p[1] * h for p in quad]
    x0, x1, y0, y1 = max(0, min(xs)), min(w, max(xs)), max(0, min(ys)), min(h, max(ys))
    return {"label": LABEL, "coordinates": {"x": (x0 + x1) / 2, "y": (y0 + y1) / 2, "width": x1 - x0, "height": y1 - y0}}


def save(im: Image.Image, dst: Path, edge: int) -> tuple[int, int]:
    im = im.convert("RGB")
    im.thumbnail((edge, edge))
    im.save(dst, "JPEG", quality=90)
    return im.size


def _image_path(path: str) -> Path:
    p = Path(path)
    return p if p.is_absolute() else ROOT / p


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="pump_reader.detdata")
    parser.add_argument("--out", type=Path, default=ROOT / "ml" / "pump-reader" / ".out" / "det")
    parser.add_argument("--frame-step", type=int, default=5)
    parser.add_argument("--edge", type=int, default=1024)
    parser.add_argument("--db", type=Path, default=None, help="corpus database (default: the committed one)")
    args = parser.parse_args(argv)
    con = corpus_db.connect(args.db)
    train_dir, held_dir = args.out / "train", args.out / "heldout"
    for d in (train_dir, held_dir):
        d.mkdir(parents=True, exist_ok=True)
    train_ann: list[dict] = []
    held_ann: list[dict] = []
    counts = {"train_stills": 0, "heldout_stills": 0, "frames": 0, "video_frames": 0, "negatives": 0, "boxes": 0}
    tracking = {r["fixture"]: r["tracking"] for r in con.execute("select fixture, tracking from entries")}
    labels = corpus_db.labels(con)

    try:
        # Stills.
        stills = con.execute(
            "select e.fixture, e.rotationCW, f.split, f.path from entries e join fixtures f on f.name = e.fixture "
            "where f.kind = 'pump' and exists(select 1 from windows w where w.fixture = e.fixture) "
            "order by e.ord").fetchall()
        for row in stills:
            name = row["fixture"]
            heldout = row["split"] == "heldout"
            rotation = row["rotationCW"] or 0
            im = ImageOps.exif_transpose(Image.open(_image_path(row["path"])))
            if rotation:
                im = im.rotate(-rotation, expand=True)  # PIL rotates counter-clockwise; the corpus' rotationCW is clockwise
            dst = (held_dir if heldout else train_dir) / (Path(name).stem + ".jpg")
            w, h = save(im, dst, args.edge)
            quads = con.execute("select quad from windows where fixture = ? order by ord", (name,)).fetchall()
            boxes = [bbox(rotate_quad(json.loads(q["quad"]), rotation), w, h) for q in quads]
            record = {"image": dst.name, "annotations": boxes, "source": name}
            (held_ann if heldout else train_ann).append(record)
            counts["heldout_stills" if heldout else "train_stills"] += 1
            counts["boxes"] += 0 if heldout else len(boxes)

        # Tracked frames of train records, and labelled video frames.
        for record in corpus_db.tracked_records(con):
            t = corpus_db.tracked(record, con=con)
            is_video = "_video" in t
            if not is_video and (t.get("_split") != "train" or tracking.get(t.get("_still", "")) == "bad"):
                continue
            folder = FRAMES / record
            names = sorted(t["frames"], key=lambda n: int(n[:-4]))
            if is_video:
                # A labelled frame (owner or arithmetic, never a skip) or one whose
                # quads the owner placed by hand (`verified`, a tracking anchor) -
                # the boxes are what the detector learns, so a hand-placed frame
                # counts whether or not its digits were labelled.
                allowed = {n for n, e in labels.get(record, {}).items() if e.get("total") != "skip"}
                allowed |= {n for n, f in t["frames"].items() if f.get("verified")}
                names = [n for n in names if n in allowed]
            for i, frame in enumerate(names):
                if i % args.frame_step:
                    continue
                im = Image.open(folder / frame)
                dst = train_dir / f"{record}-{frame}"
                w, h = save(im, dst, args.edge)
                boxes = [bbox(wd["quad"], w, h) for wd in t["frames"][frame]["windows"]]
                train_ann.append({"image": dst.name, "annotations": boxes, "source": f"{record}/{frame}"})
                counts["video_frames" if is_video else "frames"] += 1
                counts["boxes"] += len(boxes)

        # Negatives.
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
                train_ann.append({"image": dst.name, "annotations": [], "source": f"{sub}/{path.name}"})
                counts["negatives"] += 1

        # Decision 9: no heldout still, and no frame of a heldout still's record, trains the detector.
        heldout_names = corpus_db.heldout_names(con)
        heldout_records: set[str] = set()
        if heldout_names:
            placeholders = ",".join("?" * len(heldout_names))
            heldout_records = {r["record"] for r in con.execute(
                f"select record from frames where frame = '' and still in ({placeholders})", tuple(heldout_names))}
        for r in train_ann:
            assert r["source"] not in heldout_names, f"heldout still in the detector's train set: {r['source']}"
            assert r["source"].split("/")[0] not in heldout_records, f"heldout record in the detector's train set: {r['source']}"
        (train_dir / "annotations.json").write_text(json.dumps(train_ann, indent=1))
        (held_dir / "annotations.json").write_text(json.dumps(held_ann, indent=1))
        (args.out / "counts.json").write_text(json.dumps(counts, indent=1))
        print(json.dumps(counts))
        return 0
    finally:
        con.close()


if __name__ == "__main__":
    sys.exit(main())

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
import math
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


def rotated_quads(quads: list[list[list[float]]], w: int, h: int, angle: float,
                  size: tuple[int, int]) -> list[list[list[float]]]:
    """Normalised quads over a ``w`` x ``h`` image, carried onto the same image
    turned by PIL's ``rotate(angle, expand=True)`` (counter-clockwise, the
    canvas grown to hold it, centre to centre) whose size is ``size``."""
    a = math.radians(angle)
    c, s = math.cos(a), math.sin(a)
    cx, cy, cx2, cy2 = w / 2, h / 2, size[0] / 2, size[1] / 2
    out = []
    for quad in quads:
        pts = []
        for x, y in quad:
            dx, dy = x * w - cx, y * h - cy
            pts.append([(cx2 + dx * c + dy * s) / size[0], (cy2 - dx * s + dy * c) / size[1]])
        out.append(pts)
    return out


def add_rotations(src: Path, quads: list[list[list[float]]], angles: list[float], train_dir: Path,
                  edge: int, source: str, train_ann: list[dict], counts: dict) -> None:
    """Turned copies of one hand-boxed training image (PU.66): the detector was
    trained on nearly level rows and places boxes badly on a display shot from
    the side. Only hand-placed boxes are turned - a tracker's box carries its
    drift into every copy."""
    base = Image.open(src).convert("RGB")
    for angle in angles:
        turned = base.rotate(angle, expand=True, resample=Image.BICUBIC, fillcolor=(0, 0, 0))
        moved = rotated_quads(quads, base.width, base.height, angle, turned.size)
        dst = train_dir / f"{src.stem}@{angle:+g}.jpg"
        w, h = save(turned, dst, edge)
        boxes = [bbox(q, w, h) for q in moved]
        train_ann.append({"image": dst.name, "annotations": boxes, "source": f"{source}@{angle:+g}"})
        counts["rotated"] += 1
        counts["boxes"] += len(boxes)


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
    parser.add_argument("--hand-only", action="store_true",
                        help="only frames whose boxes the owner placed (verified); tracker-boxed frames are left out")
    parser.add_argument("--rotations", default="",
                        help="comma-separated angles; each hand-boxed train image also goes in turned by +/- each (PU.66)")
    args = parser.parse_args(argv)
    angles = sorted({sign * float(a) for a in args.rotations.split(",") if a.strip() for sign in (1, -1)})
    con = corpus_db.connect(args.db)
    train_dir, held_dir = args.out / "train", args.out / "heldout"
    for d in (train_dir, held_dir):
        d.mkdir(parents=True, exist_ok=True)
    train_ann: list[dict] = []
    held_ann: list[dict] = []
    counts = {"train_stills": 0, "heldout_stills": 0, "frames": 0, "video_frames": 0, "negatives": 0, "boxes": 0,
              "rotated": 0, "rotations": angles}
    tracking = {r["fixture"]: r["tracking"] for r in con.execute("select fixture, tracking from entries")}
    labels = corpus_db.labels(con)

    try:
        negatives_out: list[dict] = []
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
            # Judged negatives: regions the owner marked "not a window" (a board
            # cell that is not the price, a totem, a reflected display) and the
            # live-read rows the owner rejected. Not a Create ML input - the
            # detector's background is implicit - but the locator's ranker
            # (PU.24) needs judged boxes on both sides, and this is where they
            # are kept for it.
            entry_extra = con.execute("select extra from entries where fixture = ?", (name,)).fetchone()
            extra = json.loads(entry_extra["extra"]) if entry_extra and entry_extra["extra"] else {}
            for n in extra.get("negatives", []):
                negatives_out.append({"image": dst.name, "source": name, "heldout": heldout,
                                      "box": bbox(rotate_quad(n["quad"], rotation), w, h),
                                      "by": n.get("source", "operator"), "reason": n.get("reason", "")})
            (held_ann if heldout else train_ann).append(record)
            counts["heldout_stills" if heldout else "train_stills"] += 1
            counts["boxes"] += 0 if heldout else len(boxes)
            if angles and not heldout and quads:
                add_rotations(dst, [rotate_quad(json.loads(q["quad"]), rotation) for q in quads], angles,
                              train_dir, args.edge, name, train_ann, counts)

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
            # A frame the owner marked `skipped` shows no display (a hand, the
            # nozzle, a glare pass): its quads are wherever the tracker left
            # them, and a detector must not learn a box on nothing.
            names = [n for n in names if not t["frames"][n].get("skipped")]
            # --hand-only: a tracker's box carries its drift into the detector's
            # framing (PU.66: where the owner corrected it, median IoU 0.77), so
            # only frames the owner placed by hand stay in.
            if args.hand_only:
                names = [n for n in names if t["frames"][n].get("verified")]
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
                # Only a frame whose boxes the owner placed is turned; a tracked
                # frame's box is the tracker's and stays as it is, once.
                if angles and t["frames"][frame].get("verified") and t["frames"][frame]["windows"]:
                    add_rotations(dst, [wd["quad"] for wd in t["frames"][frame]["windows"]], angles,
                                  train_dir, args.edge, f"{record}/{frame}", train_ann, counts)

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
            source = r["source"].split("@")[0]  # a turned copy is its source's
            assert source not in heldout_names, f"heldout still in the detector's train set: {r['source']}"
            assert source.split("/")[0] not in heldout_records, f"heldout record in the detector's train set: {r['source']}"
        (args.out / "negatives.json").write_text(json.dumps(negatives_out, indent=1))
        counts["judged_negatives"] = len(negatives_out)
        (train_dir / "annotations.json").write_text(json.dumps(train_ann, indent=1))
        (held_dir / "annotations.json").write_text(json.dumps(held_ann, indent=1))
        (args.out / "counts.json").write_text(json.dumps(counts, indent=1))
        print(json.dumps(counts))
        return 0
    finally:
        con.close()


if __name__ == "__main__":
    sys.exit(main())

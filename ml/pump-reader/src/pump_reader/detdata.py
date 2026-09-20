"""CLI: ``python -m pump_reader.detdata [--out .out/det] [--frame-step 5] [--edge 1024]``.

The row detector's training set (PU.33), built from boxes the corpus already
holds and nothing else:

* every TRAIN still (`pump/split.csv`, decision 9) with its annotated windows;
* every k-th tracked frame of a train still's Live record and of the labelled
  video frames (`pump_reader.track` output) - neighbours at 30 fps are near
  copies, so one in ``--frame-step`` carries the information;
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
import csv
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
PUMP = FIX / "pump"
LIVE = FIX / "pump-live"
FRAMES = LIVE / "frames"
NEGATIVE_FOLDERS = ("receipts", "screenshots", "fiscal", "expenses")
LABEL = "digit-row"


def split() -> dict[str, str]:
    with (PUMP / "split.csv").open() as f:
        return {r["filename"]: r["split"] for r in csv.DictReader(f)}


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


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="pump_reader.detdata")
    parser.add_argument("--out", type=Path, default=ROOT / "ml" / "pump-reader" / ".out" / "det")
    parser.add_argument("--frame-step", type=int, default=5)
    parser.add_argument("--edge", type=int, default=1024)
    args = parser.parse_args(argv)
    sp = split()
    windows = json.loads((PUMP / "windows.json").read_text())
    train_dir, held_dir = args.out / "train", args.out / "heldout"
    for d in (train_dir, held_dir):
        d.mkdir(parents=True, exist_ok=True)
    train_ann: list[dict] = []
    held_ann: list[dict] = []
    counts = {"train_stills": 0, "heldout_stills": 0, "frames": 0, "video_frames": 0, "negatives": 0, "boxes": 0}

    # Stills.
    for name, entry in windows.items():
        if name.startswith("_") or not entry.get("windows"):
            continue
        heldout = sp.get(name) == "heldout"
        rotation = entry.get("rotationCW", 0)
        im = ImageOps.exif_transpose(Image.open(PUMP / name))
        if rotation:
            im = im.rotate(-rotation, expand=True)  # PIL rotates counter-clockwise; the corpus' rotationCW is clockwise
        dst = (held_dir if heldout else train_dir) / (Path(name).stem + ".jpg")
        w, h = save(im, dst, args.edge)
        boxes = [bbox(rotate_quad(wd["quad"], rotation), w, h) for wd in entry["windows"]]
        record = {"image": dst.name, "annotations": boxes, "source": name}
        (held_ann if heldout else train_ann).append(record)
        counts["heldout_stills" if heldout else "train_stills"] += 1
        counts["boxes"] += 0 if heldout else len(boxes)

    # Tracked frames of train records, and labelled video frames.
    labels = json.loads((LIVE / "video-labels.json").read_text()) if (LIVE / "video-labels.json").exists() else {}
    for folder in sorted(FRAMES.iterdir()):
        tracked = folder / "windows.json"
        if not tracked.exists():
            continue
        t = json.loads(tracked.read_text())
        is_video = "_video" in t
        if not is_video and (t.get("_split") != "train" or windows.get(t.get("_still", ""), {}).get("tracking") == "bad"):
            continue
        names = sorted(t["frames"], key=lambda n: int(n[:-4]))
        if is_video:
            allowed = {n for n, e in labels.get(folder.name, {}).items() if e.get("total") != "skip"}
            names = [n for n in names if n in allowed]
        for i, frame in enumerate(names):
            if i % args.frame_step:
                continue
            im = Image.open(folder / frame)
            dst = train_dir / f"{folder.name}-{frame}"
            w, h = save(im, dst, args.edge)
            boxes = [bbox(wd["quad"], w, h) for wd in t["frames"][frame]["windows"]]
            train_ann.append({"image": dst.name, "annotations": boxes, "source": f"{folder.name}/{frame}"})
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
    heldout_names = {n for n, s in sp.items() if s == "heldout"}
    heldout_records = set()
    for folder in FRAMES.iterdir():
        tracked = folder / "windows.json"
        if tracked.exists() and json.loads(tracked.read_text()).get("_still") in heldout_names:
            heldout_records.add(folder.name)
    for r in train_ann:
        assert r["source"] not in heldout_names, f"heldout still in the detector's train set: {r['source']}"
        assert r["source"].split("/")[0] not in heldout_records, f"heldout record in the detector's train set: {r['source']}"
    (train_dir / "annotations.json").write_text(json.dumps(train_ann, indent=1))
    (held_dir / "annotations.json").write_text(json.dumps(held_ann, indent=1))
    (args.out / "counts.json").write_text(json.dumps(counts, indent=1))
    print(json.dumps(counts))
    return 0


if __name__ == "__main__":
    sys.exit(main())

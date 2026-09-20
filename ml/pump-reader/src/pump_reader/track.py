"""CLI: ``python -m pump_reader.track [--only live-6229] [--min-inliers 30]``.

Carries a still's annotated number windows into every frame of its Live
Photo record. Each frame is registered to the still directly (ORB features
on the display region, RANSAC homography) - never chained frame to frame,
so there is no drift to accumulate - and the still's quads are mapped
through that homography. A frame whose registration has too few inliers,
or whose mapped quads leave the image or change area implausibly, is
dropped rather than guessed.

Output per record, beside the frames ``pump_reader.frames`` extracted:

* ``frames/<stem>/windows.json`` - the corpus ``windows.json`` shape keyed by
  frame file, with the still's ``field`` / ``text`` / ``legibility`` and the
  mapped ``quad`` (normalised over the frame), plus the inlier count;
* ``frames/<stem>/sheet.jpg`` - a contact sheet with the quads drawn, for
  the eye check that is the only human step here.

Every paired record is tracked, heldout stills' included, so the annotator
can show any record; the output carries the still's ``split`` and the glyph
extractor takes only ``train`` (decision 9): a heldout still's frames are
the same fill and must never train.
"""

from __future__ import annotations

import argparse
import csv
import json
import sqlite3
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[4]
FIX = ROOT / "Spike" / "ReceiptSpike" / "fixtures"
PUMP = FIX / "pump"
LIVE = FIX / "pump-live"
FRAMES = LIVE / "frames"
DB = FIX / "corpus.sqlite"
WORK_EDGE = 1200  # feature extraction resolution; quads are mapped in full coordinates

try:
    import pillow_heif

    pillow_heif.register_heif_opener()
except Exception:  # pragma: no cover
    pass


def paired_records() -> list[tuple[str, str, str]]:
    """(movie stem, still filename, split) for every Live record paired to a pump still."""
    with sqlite3.connect(DB) as con:
        rows = con.execute(
            "select m.name, m.paired_fixture, f.split from media m join fixtures f on f.name = m.paired_fixture "
            "where m.kind = 'live' and f.kind = 'pump' order by m.name").fetchall()
    return [(Path(name).stem, still, split) for name, still, split in rows]


def load_windows() -> dict:
    return json.loads((PUMP / "windows.json").read_text())


def oriented_gray(path: Path) -> tuple[np.ndarray, tuple[int, int]]:
    im = ImageOps.exif_transpose(Image.open(path)).convert("L")
    return np.asarray(im), im.size


def scaled(gray: np.ndarray) -> tuple[np.ndarray, float]:
    h, w = gray.shape
    s = min(1.0, WORK_EDGE / max(h, w))
    if s < 1.0:
        gray = cv2.resize(gray, (int(w * s), int(h * s)), interpolation=cv2.INTER_AREA)
    return gray, s


def display_mask(shape: tuple[int, int], quads: list[np.ndarray], grow: float = 1.5) -> np.ndarray:
    """Keypoints on the still come from the display panel, not the forecourt:
    the union of the windows grown by `grow` of its own size on every side."""
    h, w = shape
    pts = np.concatenate(quads)
    x0, y0 = pts.min(axis=0)
    x1, y1 = pts.max(axis=0)
    bw, bh = x1 - x0, y1 - y0
    mask = np.zeros((h, w), np.uint8)
    cv2.rectangle(mask, (int(max(0, x0 - grow * bw)), int(max(0, y0 - grow * bh))),
                  (int(min(w - 1, x1 + grow * bw)), int(min(h - 1, y1 + grow * bh))), 255, -1)
    return mask


class Registrar:
    def __init__(self, still_gray: np.ndarray, quads_px: list[np.ndarray]):
        self.orb = cv2.ORB_create(nfeatures=4000, scaleFactor=1.2, nlevels=8)
        self.small, self.scale = scaled(still_gray)
        mask = display_mask(self.small.shape, [q * self.scale for q in quads_px])
        self.kp, self.desc = self.orb.detectAndCompute(self.small, mask)
        self.matcher = cv2.BFMatcher(cv2.NORM_HAMMING)

    def homography(self, frame_gray: np.ndarray) -> tuple[np.ndarray | None, int, float]:
        """Still (full px) -> frame (full px), the inlier count, the frame's scale."""
        small, fscale = scaled(frame_gray)
        kp, desc = self.orb.detectAndCompute(small, None)
        if desc is None or self.desc is None or len(kp) < 8:
            return None, 0, fscale
        pairs = self.matcher.knnMatch(self.desc, desc, k=2)
        good = [m for m, n in (p for p in pairs if len(p) == 2) if m.distance < 0.75 * n.distance]
        if len(good) < 12:
            return None, len(good), fscale
        src = np.float32([self.kp[m.queryIdx].pt for m in good]) / self.scale
        dst = np.float32([kp[m.trainIdx].pt for m in good]) / fscale
        H, inl = cv2.findHomography(src, dst, cv2.RANSAC, 4.0)
        if H is None:
            return None, 0, fscale
        return H, int(inl.sum()), fscale


def map_quad(H: np.ndarray, quad_px: np.ndarray) -> np.ndarray:
    return cv2.perspectiveTransform(quad_px.reshape(-1, 1, 2).astype(np.float32), H).reshape(-1, 2)


def plausible(mapped: np.ndarray, orig: np.ndarray, frame_size: tuple[int, int], still_size: tuple[int, int]) -> bool:
    fw, fh = frame_size
    sw, sh = still_size
    if (mapped[:, 0] < -0.02 * fw).any() or (mapped[:, 0] > 1.02 * fw).any():
        return False
    if (mapped[:, 1] < -0.02 * fh).any() or (mapped[:, 1] > 1.02 * fh).any():
        return False
    area = abs(cv2.contourArea(mapped.astype(np.float32))) / (fw * fh)
    area0 = abs(cv2.contourArea(orig.astype(np.float32))) / (sw * sh)
    if area0 <= 0 or not (0.25 <= area / area0 <= 4.0):
        return False
    # Convex and not folded: the four corners keep their winding.
    return cv2.isContourConvex(mapped.astype(np.float32))


def track_record(stem: str, still: str, split: str, ann: dict, min_inliers: int) -> dict | None:
    folder = FRAMES / stem
    frames = sorted(folder.glob("*.jpg"))
    if not frames:
        return None
    entry = ann.get(still)
    if not entry or not entry.get("windows"):
        return None
    still_gray, (sw, sh) = oriented_gray(PUMP / still)
    quads_px = [np.array(w["quad"], dtype=np.float64) * [sw, sh] for w in entry["windows"]]
    reg = Registrar(still_gray, quads_px)
    out: dict = {"_still": still, "_movie": stem, "_split": split, "frames": {}}
    kept = dropped = 0
    for frame in frames:
        gray = cv2.imread(str(frame), cv2.IMREAD_GRAYSCALE)
        fh, fw = gray.shape
        H, inliers, _ = reg.homography(gray)
        if H is None or inliers < min_inliers:
            dropped += 1
            continue
        windows = []
        ok = True
        for w, q in zip(entry["windows"], quads_px):
            m = map_quad(H, q)
            if not plausible(m, q, (fw, fh), (sw, sh)):
                ok = False
                break
            cw = {"field": w["field"], "text": w.get("text", ""),
                  "quad": [[round(float(x) / fw, 4), round(float(y) / fh, 4)] for x, y in m]}
            if w.get("legibility"):
                cw["legibility"] = w["legibility"]
            windows.append(cw)
        if not ok:
            dropped += 1
            continue
        out["frames"][frame.name] = {"windows": windows, "inliers": inliers}
        kept += 1
    out["_kept"] = kept
    out["_dropped"] = dropped
    (folder / "windows.json").write_text(json.dumps(out, indent=1))
    sheet(folder, out)
    return out


def sheet(folder: Path, tracked: dict, cols: int = 6, rows: int = 2, tile: int = 320) -> None:
    names = list(tracked["frames"])
    if not names:
        return
    picks = [names[int(i * (len(names) - 1) / max(cols * rows - 1, 1))] for i in range(min(cols * rows, len(names)))]
    canvas = Image.new("RGB", (cols * tile, rows * tile), "black")
    colours = {"total": "#ff5a5f", "liters": "#4cc3ff", "unitPrice": "#ffc857", "board": "#9b8cff"}
    for i, name in enumerate(picks):
        im = Image.open(folder / name).convert("RGB")
        W, H = im.size
        dr = ImageDraw.Draw(im)
        for w in tracked["frames"][name]["windows"]:
            pts = [(x * W, y * H) for x, y in w["quad"]]
            dr.polygon(pts, outline=colours.get(w["field"], "white"), width=max(2, W // 400))
        dr.text((8, 8), f"{name} inl {tracked['frames'][name]['inliers']}", fill="yellow")
        im.thumbnail((tile, tile))
        canvas.paste(im, ((i % cols) * tile, (i // cols) * tile))
    canvas.save(folder / "sheet.jpg", quality=80)


VIDEOS = LIVE / "videos.json"


def track_video(stem: str, entry: dict, min_inliers: int) -> dict | None:
    """A running-display video has no still: its reference is one of its own
    frames (`videos.json`), annotated by hand, and the quads are carried from
    it exactly as a still's are. Texts stay empty except the constant price;
    `PumpVideoReadTests` fills the rest where the arithmetic closes."""
    folder = FRAMES / stem
    frames = sorted(folder.glob("*.jpg"), key=lambda p: int(p.stem))
    if not frames:
        return None
    ref = folder / entry["reference"]
    ref_gray = cv2.imread(str(ref), cv2.IMREAD_GRAYSCALE)
    sh, sw = ref_gray.shape
    quads_px = [np.array(w["quad"], dtype=np.float64) * [sw, sh] for w in entry["windows"]]
    reg = Registrar(ref_gray, quads_px)
    out: dict = {"_video": stem, "_reference": entry["reference"], "_split": "train", "frames": {}}
    kept = dropped = 0
    for frame in frames:
        gray = cv2.imread(str(frame), cv2.IMREAD_GRAYSCALE)
        fh, fw = gray.shape
        H, inliers, _ = reg.homography(gray)
        if H is None or inliers < min_inliers:
            dropped += 1
            continue
        windows = []
        ok = True
        for w, q in zip(entry["windows"], quads_px):
            m = map_quad(H, q)
            if not plausible(m, q, (fw, fh), (sw, sh)):
                ok = False
                break
            windows.append({"field": w["field"], "text": entry["unitPrice"] if w["field"] == "unitPrice" else "",
                            "quad": [[round(float(x) / fw, 4), round(float(y) / fh, 4)] for x, y in m]})
        if not ok:
            dropped += 1
            continue
        out["frames"][frame.name] = {"windows": windows, "inliers": inliers}
        kept += 1
    out["_kept"] = kept
    out["_dropped"] = dropped
    (folder / "windows.json").write_text(json.dumps(out, indent=1))
    sheet(folder, out)
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="pump_reader.track")
    parser.add_argument("--only", action="append", default=[])
    parser.add_argument("--min-inliers", type=int, default=30)
    parser.add_argument("--videos", action="store_true", help="track the running-display videos from videos.json")
    args = parser.parse_args(argv)
    if args.videos:
        videos = json.loads(VIDEOS.read_text())
        for stem, entry in videos.items():
            if stem.startswith("_") or (args.only and stem not in args.only):
                continue
            result = track_video(stem, entry, args.min_inliers)
            if result:
                print(f"{stem}: {result['_kept']} kept, {result['_dropped']} dropped")
        return 0
    ann = load_windows()
    records = paired_records()
    if args.only:
        records = [r for r in records if r[0] in args.only]
    summary = []
    for stem, still, split in records:
        result = track_record(stem, still, split, ann, args.min_inliers)
        if result is None:
            print(f"{stem}: no frames or no annotation for {still[:12]}")
            continue
        summary.append((stem, split, result["_kept"], result["_dropped"]))
        print(f"{stem} <- {still[:12]} [{split}]: {result['_kept']} kept, {result['_dropped']} dropped")
    kept = sum(k for _, _, k, _ in summary)
    dropped = sum(d for _, _, _, d in summary)
    print(f"{len(summary)} records: {kept} frames tracked, {dropped} dropped")
    with (FRAMES / "tracking.csv").open("w") as f:
        w = csv.writer(f)
        w.writerow(["movie", "split", "kept", "dropped"])
        w.writerows(summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())

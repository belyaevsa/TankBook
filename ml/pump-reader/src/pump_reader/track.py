"""CLI: ``python -m pump_reader.track [--only live-6229] [--min-inliers 30]``.

Carries a still's annotated number windows into every frame of its Live
Photo record. Each frame is registered to the still directly (ORB features
on the display region, RANSAC homography) - never chained frame to frame,
so there is no drift to accumulate - and the still's quads are mapped
through that homography. A frame whose registration has too few inliers,
or whose mapped quads leave the image or change area implausibly, is
dropped rather than guessed.

The record's frames / frame windows are written through
``corpus_db.save_tracked`` (one transaction), then ``corpus_db.dump`` writes
``frames/<stem>/windows.json`` for the Swift readers. Beside the frames
``pump_reader.frames`` extracted, each record also gets:

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
sys.path.insert(0, str(ROOT / "scripts"))
import corpus_db  # noqa: E402

WORK_EDGE = 1200  # feature extraction resolution; quads are mapped in full coordinates

try:
    import pillow_heif

    pillow_heif.register_heif_opener()
except Exception:  # pragma: no cover
    pass


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
    def __init__(self, still_gray: np.ndarray, quads_px: list[np.ndarray], samples: list[np.ndarray] = ()):
        self.orb = cv2.ORB_create(nfeatures=4000, scaleFactor=1.2, nlevels=8)
        self.small, self.scale = scaled(still_gray)
        mask = display_mask(self.small.shape, [q * self.scale for q in quads_px])
        self.kp, self.desc = self.orb.detectAndCompute(self.small, mask)
        self.matcher = cv2.BFMatcher(cv2.NORM_HAMMING)
        self.static_dropped = self.drop_static(samples)

    def drop_static(self, samples: list[np.ndarray], tolerance: float = 3.0, share: float = 0.7) -> int:
        """A burned-in overlay - a QR code, a caption band, a channel logo - sits
        at the same pixels in every frame, so its corners match the anchor at
        the identity and, being many, outvote the moving display in RANSAC:
        the tracked quads then never move. A keypoint whose match lands within
        `tolerance` px of its own position in more than `share` of the sampled
        frames is such an overlay and is dropped before any frame registers.
        A still camera keeps everything: then every keypoint is static, and
        dropping them all would leave nothing, so nothing is dropped."""
        if self.desc is None or len(samples) < 4:
            return 0
        hits = np.zeros(len(self.kp), np.int32)
        matched = np.zeros(len(self.kp), np.int32)
        seen = 0
        for gray in samples:
            small, fscale = scaled(gray)
            kp, desc = self.orb.detectAndCompute(small, None)
            if desc is None:
                continue
            seen += 1
            for pair in self.matcher.knnMatch(self.desc, desc, k=2):
                if len(pair) == 2 and pair[0].distance < 0.75 * pair[1].distance:
                    m = pair[0]
                    matched[m.queryIdx] += 1
                    a = np.array(self.kp[m.queryIdx].pt) / self.scale
                    b = np.array(kp[m.trainIdx].pt) / fscale
                    if np.linalg.norm(a - b) <= tolerance:
                        hits[m.queryIdx] += 1
        if seen < 4:
            return 0
        # The share is of the frames the keypoint matched in at all: a caption
        # that fades in is absent from the early frames and static after.
        static = (matched >= 4) & (hits > share * matched)
        if static.sum() == 0 or (~static).sum() < 50:
            return 0
        self.kp = [k for k, s in zip(self.kp, static) if not s]
        self.desc = self.desc[~static]
        return int(static.sum())

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


def carried(source: dict, quad: list) -> dict:
    """A frame window: the still's field, text and legibility on a new quad."""
    cw = {"field": source["field"], "text": source.get("text", ""), "quad": quad}
    if source.get("legibility"):
        cw["legibility"] = source["legibility"]
    return cw


def _box_iou(a: list, b: list) -> float:
    ax0, ax1 = min(p[0] for p in a), max(p[0] for p in a); ay0, ay1 = min(p[1] for p in a), max(p[1] for p in a)
    bx0, bx1 = min(p[0] for p in b), max(p[0] for p in b); by0, by1 = min(p[1] for p in b), max(p[1] for p in b)
    iw, ih = max(0.0, min(ax1, bx1) - max(ax0, bx0)), max(0.0, min(ay1, by1) - max(ay0, by0))
    inter = iw * ih
    union = (ax1 - ax0) * (ay1 - ay0) + (bx1 - bx0) * (by1 - by0) - inter
    return inter / union if union > 0 else 0.0


MOVED_IOU = 0.97


def moved(before: dict | None, after: dict | None) -> bool:
    """Whether a re-fit changed a frame enough to change what it reads: a frame
    that appeared or vanished, or any window whose box overlaps its stored self
    by less than MOVED_IOU. A re-read of a frame whose boxes did not move reads
    the same pixels and cannot change its label."""
    if (before is None) != (after is None):
        return True
    if before is None:
        return False
    a, b = before.get("windows", []), after.get("windows", [])
    if len(a) != len(b):
        return True
    return any(_box_iou(x["quad"], y["quad"]) < MOVED_IOU for x, y in zip(a, b))


def candidates(regs: list[dict], index: int) -> list[dict]:
    """The registrations a frame tries, in the order the owner's placements
    deserve: the nearest pinned frame AT OR BEFORE it (the correction being
    carried forward), then the nearest after it, then the rest by distance, and
    the still (index None) last. The first that fits wins - inliers are a gate,
    not a ranking: a far registration to the still can out-count a near anchor
    and still be the wrong one, which is how a fresh correction used to be
    ignored for the frames right after it."""
    timed = [r for r in regs if r["index"] is not None]
    before = sorted((r for r in timed if r["index"] <= index), key=lambda r: index - r["index"])
    after = sorted((r for r in timed if r["index"] > index), key=lambda r: r["index"] - index)
    order = before[:1] + after[:1] + sorted(before[1:] + after[1:], key=lambda r: abs(r["index"] - index))
    return order + [r for r in regs if r["index"] is None]


def fit(gray: np.ndarray, regs: list[dict], index: int, min_inliers: int):
    """The first candidate registration that clears the inlier gate and maps
    every window plausibly: (H, inliers, reg, mapped quads in frame pixels), or
    None when none does."""
    fh, fw = gray.shape
    for r in candidates(regs, index):
        # Built on first use: a record can carry dozens of pinned frames, and a
        # segment re-fit tries two or three of them - building every matcher up
        # front was most of a Save's wait.
        if r["reg"] is None:
            r["reg"] = r.pop("build")()
        H, inliers, _ = r["reg"].homography(gray)
        if H is None or inliers < min_inliers:
            continue
        mapped = [map_quad(H, q) for q in r["quads"]]
        if all(plausible(m, q, (fw, fh), r["size"]) for m, q in zip(mapped, r["quads"])):
            return H, inliers, r, mapped
    return None


def track_record(stem: str, still: str, split: str, entry: dict, min_inliers: int,
                 start_at: int = 0, stop_at: int | None = None) -> dict | None:
    """A Live Photo's frames take the still's quads and texts. The still is the
    reference; every frame the owner corrected in the annotator (`liveAnchors`
    on the still's entry) is a further anchor, written back verbatim, and each
    other frame registers to the still and to its nearest anchors and takes the
    registration with the most inliers - the same rule as a video's."""
    folder = FRAMES / stem
    frames = sorted(folder.glob("*.jpg"))
    if not frames:
        return None
    if not entry.get("windows"):
        return None
    still_gray, (sw, sh) = oriented_gray(PUMP / still)
    quads_px = [np.array(w["quad"], dtype=np.float64) * [sw, sh] for w in entry["windows"]]
    regs = [{"index": None, "reg": Registrar(still_gray, quads_px), "quads": quads_px, "size": (sw, sh),
             "windows": entry["windows"]}]
    anchors = [a for a in entry.get("liveAnchors", []) if (folder / a["frame"]).exists()]
    for a in anchors:
        gray = cv2.imread(str(folder / a["frame"]), cv2.IMREAD_GRAYSCALE)
        ah, aw = gray.shape
        aq = [np.array(w["quad"], dtype=np.float64) * [aw, ah] for w in a["windows"]]
        regs.append({"index": int(a["frame"][:-4]), "reg": None,
                     "build": (lambda g=gray, q=aq: Registrar(g, q)), "quads": aq, "size": (aw, ah),
                     "windows": a["windows"]})
    # Texts by window index, not by field: a head with two `board` cells has
    # two different texts under one field name.
    still_windows = entry["windows"]

    def source(index: int, fallback: dict) -> dict:
        return still_windows[index] if index < len(still_windows) else fallback
    out: dict = {"_still": still, "_movie": stem, "_split": split, "_anchors": [a["frame"] for a in anchors],
                 "frames": {}}
    kept = dropped = 0
    exact = {a["frame"]: a["windows"] for a in anchors}
    for frame in frames:
        # `--from`: a frame before the start keeps its database row (the merge
        # in main), so registering it is work thrown away.
        if frame.stem.isdigit() and (int(frame.stem) < start_at or (stop_at is not None and int(frame.stem) >= stop_at)):
            continue
        if frame.name in exact:
            out["frames"][frame.name] = {"windows": [carried(source(i, w), w["quad"]) for i, w in enumerate(exact[frame.name])],
                                        "inliers": -1, "anchor": int(frame.stem), "verified": True}
            kept += 1
            continue
        gray = cv2.imread(str(frame), cv2.IMREAD_GRAYSCALE)
        fh, fw = gray.shape
        index = int(frame.stem) if frame.stem.isdigit() else 0
        found = fit(gray, regs, index, min_inliers)
        if found is None:
            dropped += 1
            continue
        H, inliers, r, mapped = found
        windows = [carried(source(i, w), [[round(float(x) / fw, 4), round(float(y) / fh, 4)] for x, y in m])
                   for i, (w, m) in enumerate(zip(r["windows"], mapped))]
        out["frames"][frame.name] = {"windows": windows, "inliers": inliers,
                                     **({"anchor": r["index"]} if r["index"] is not None else {})}
        kept += 1
    out["_kept"] = kept
    out["_dropped"] = dropped
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


def track_video(stem: str, entry: dict, min_inliers: int, start_at: int = 0,
                stop_at: int | None = None) -> dict | None:
    """A running-display video has no still: its reference is one of its own
    frames (the database `videos` entry), annotated by hand, and the quads are carried from
    it exactly as a still's are. Texts stay empty except the constant price;
    `PumpVideoReadTests` fills the rest where the arithmetic closes."""
    folder = FRAMES / stem
    start = int(entry["firstFrame"][:-4]) if entry.get("firstFrame") else 1
    end = int(entry["lastFrame"][:-4]) if entry.get("lastFrame") else None
    frames = sorted((p for p in folder.glob("*.jpg")
                     if p.stem.isdigit() and int(p.stem) >= start and (end is None or int(p.stem) <= end)),
                    key=lambda p: int(p.stem))
    if not frames:
        return None
    # Anchors: the reference frame plus every frame the owner corrected in the
    # annotator (`anchors`); each frame is registered to the anchors nearest
    # in time and takes the one with the most inliers, so a correction fixes
    # the stretch of the clip around it.
    anchors = [{"frame": entry["reference"], "windows": entry["windows"]}] + [
        a for a in entry.get("anchors", []) if a["frame"] != entry["reference"]]
    step = max(1, len(frames) // 16)
    samples = [g for g in (cv2.imread(str(f), cv2.IMREAD_GRAYSCALE) for f in frames[::step][:16]) if g is not None]
    regs = []
    for a in anchors:
        gray = cv2.imread(str(folder / a["frame"]), cv2.IMREAD_GRAYSCALE)
        sh, sw = gray.shape
        quads_px = [np.array(w["quad"], dtype=np.float64) * [sw, sh] for w in a["windows"]]
        regs.append({"index": int(a["frame"][:-4]), "reg": None,
                     "build": (lambda g=gray, q=quads_px: Registrar(g, q, samples)), "quads": quads_px,
                     "size": (sw, sh), "windows": a["windows"]})
    out: dict = {"_video": stem, "_reference": entry["reference"], "_anchors": [a["frame"] for a in anchors],
                 "_split": "train", "frames": {},
                 "_staticKeypointsDropped": {}}
    kept = dropped = 0
    exact = {a["frame"]: a["windows"] for a in anchors}
    for frame in frames:
        # `--from`: a frame before the start keeps its database row (the merge
        # in main), so registering it is work thrown away.
        if int(frame.stem) < start_at or (stop_at is not None and int(frame.stem) >= stop_at):
            continue
        # A frame the owner placed by hand is written back verbatim - never
        # re-registered, so a retrack cannot move what a human verified.
        if frame.name in exact:
            out["frames"][frame.name] = {"windows": [{"field": w["field"],
                                                     "text": entry["unitPrice"] if w["field"] == "unitPrice" else "",
                                                     "quad": w["quad"]} for w in exact[frame.name]],
                                        "inliers": -1, "anchor": int(frame.stem), "verified": True}
            kept += 1
            continue
        gray = cv2.imread(str(frame), cv2.IMREAD_GRAYSCALE)
        fh, fw = gray.shape
        index = int(frame.stem)
        found = fit(gray, regs, index, min_inliers)
        if found is None:
            dropped += 1
            continue
        H, inliers, r, mapped = found
        windows = [{"field": w["field"], "text": entry["unitPrice"] if w["field"] == "unitPrice" else "",
                    "quad": [[round(float(x) / fw, 4), round(float(y) / fh, 4)] for x, y in m]}
                   for w, m in zip(r["windows"], mapped)]
        out["frames"][frame.name] = {"windows": windows, "inliers": inliers, "anchor": r["index"]}
        kept += 1
    out["_kept"] = kept
    out["_dropped"] = dropped
    # The static-overlay count of every matcher that was actually built (a
    # lazily skipped anchor matched nothing, so it has nothing to report).
    out["_staticKeypointsDropped"] = {a["frame"]: r["reg"].static_dropped
                                      for a, r in zip(anchors, regs) if r["reg"] is not None}
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="pump_reader.track")
    parser.add_argument("--only", action="append", default=[])
    parser.add_argument("--min-inliers", type=int, default=30)
    parser.add_argument("--videos", action="store_true", help="track the running-display videos in the database")
    parser.add_argument("--until-next-anchor", action="store_true",
                        help="with --from: stop at the next pinned frame after it - the frames past it are fitted from that one")
    parser.add_argument("--from", dest="from_frame", default=None,
                        help="re-register only this frame and the ones after it (e.g. 047.jpg); earlier frames keep their rows")
    args = parser.parse_args(argv)

    def keep_earlier(stem: str, result: dict, stop: int | None = None) -> dict:
        """With --from, the frames outside [from, stop) keep what the database
        holds; the ones inside whose boxes moved are listed in `_changed` - the
        only frames worth reading again."""
        if not args.from_frame:
            return result
        start = int(args.from_frame[:-4])
        inside = lambda n: int(n[:-4]) >= start and (stop is None or int(n[:-4]) < stop)
        existing = corpus_db.tracked(stem, con=con) or {"frames": {}}
        merged = {n: f for n, f in result["frames"].items() if inside(n)}
        for n, f in existing["frames"].items():
            if not inside(n):
                merged[n] = f
        result["_changed"] = sorted((n for n, f in merged.items() if inside(n) and moved(existing["frames"].get(n), f)),
                                    key=lambda n: int(n[:-4]))
        result["frames"] = dict(sorted(merged.items(), key=lambda kv: int(kv[0][:-4])))
        result["_earlier"] = len(result["frames"]) - result["_kept"]
        return result

    def next_anchor(indices: list[int]) -> int | None:
        """The first pinned frame after --from, when --until-next-anchor asks for it."""
        if not (args.from_frame and args.until_next_anchor):
            return None
        start = int(args.from_frame[:-4])
        later = [i for i in indices if i > start]
        return min(later) if later else None

    start_at = int(args.from_frame[:-4]) if args.from_frame else 0

    def report(stem: str, result: dict, prefix: str = "") -> str:
        # With --from the counts are the re-registered range's, and the frames
        # left alone are named as such - the whole record's total read as if
        # every frame had been redone.
        if args.from_frame:
            return (f"{prefix}{stem}: from {args.from_frame} {result['_kept']} re-registered, "
                    f"{result['_dropped']} dropped; {result.get('_earlier', 0)} earlier kept as they were")
        return f"{prefix}{stem}: {result['_kept']} kept, {result['_dropped']} dropped"
    con = corpus_db.connect()
    paths: list[Path] = []
    try:
        if args.videos:
            for stem in corpus_db.video_stems(con):
                if args.only and stem not in args.only:
                    continue
                entry = corpus_db.video(stem, con=con)
                stop = next_anchor([int(a["frame"][:-4]) for a in (entry or {}).get("anchors", [])]
                                   + ([int(entry["reference"][:-4])] if entry else []))
                result = track_video(stem, entry, args.min_inliers, start_at, stop) if entry else None
                if result is None:
                    print(f"{stem}: no frames or no entry")
                    continue
                result = keep_earlier(stem, result, stop)
                changed = result.pop("_changed", None)
                with con:
                    corpus_db.save_tracked(stem, result, con=con)
                sheet(FRAMES / stem, result)
                paths.append(FRAMES / stem / "windows.json")
                print(report(stem, result) + (f" (until {stop:03d}.jpg)" if stop else ""))
                if changed is not None:
                    # One machine-readable line for the annotator's read step.
                    print("CHANGED " + ",".join(changed))
            corpus_db.dump(paths)
            return 0
        records = corpus_db.paired_records(con)
        if args.only:
            records = [r for r in records if r[0] in args.only]
        summary = []
        for stem, still, split in records:
            entry = corpus_db.entry(still, con=con)
            stop = next_anchor([int(a["frame"][:-4]) for a in (entry or {}).get("liveAnchors", []) if a["record"] == stem])
            result = track_record(stem, still, split, entry, args.min_inliers, start_at, stop) if entry else None
            if result is None:
                print(f"{stem}: no frames or no annotation for {still[:12]}")
                continue
            result = keep_earlier(stem, result, stop)
            result.pop("_changed", None)
            with con:
                corpus_db.save_tracked(stem, result, con=con)
            sheet(FRAMES / stem, result)
            paths.append(FRAMES / stem / "windows.json")
            summary.append((stem, split, result["_kept"], result["_dropped"]))
            print(report(stem, result) if args.from_frame
                  else f"{stem} <- {still[:12]} [{split}]: {result['_kept']} kept, {result['_dropped']} dropped")
        corpus_db.dump(paths)
        kept = sum(k for _, _, k, _ in summary)
        dropped = sum(d for _, _, _, d in summary)
        print(f"{len(summary)} records: {kept} frames tracked, {dropped} dropped")
        with (FRAMES / "tracking.csv").open("w") as f:
            w = csv.writer(f)
            w.writerow(["movie", "split", "kept", "dropped"])
            w.writerows(summary)
        return 0
    finally:
        con.close()


if __name__ == "__main__":
    sys.exit(main())

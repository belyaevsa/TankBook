"""CLI: ``python -m pump_reader.score --model … --windows … --fixtures …``.

Scores the trained ``SegmentNet`` on the held-out number windows. This is the
one place the real corpus is touched, and it is measurement only: no weights are
changed, no hyperparameter is tuned here, and every fixture stays held-out.

The slicer is deliberately naive (PU.4 builds the real one): a window quad is
warped to a 48px-tall strip and sliced into N equal cells where N is the glyph
cell count of the annotated ``text``, so this row measures the classifier, not
the slicer.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
import torch
from PIL import Image, ImageOps

from .augment import homography_from_corners
from .dataset import bits_to_target, target_to_bits
from .glyph import decode_constrained
from .glyph import CELL_H, CELL_W, BLANK, DP_ONLY, SegmentLabel
from .model import SegmentNet

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "scripts"))
import corpus_db  # noqa: E402

try:
    import pillow_heif

    pillow_heif.register_heif_opener()
    HEIF_OK = True
except Exception:  # pragma: no cover - environment dependent
    HEIF_OK = False

_SEGMENT_NAMES = list("abcdefg") + ["dp"]

# The strip resolution the harness warps to and the slicer's grid is computed
# on (PumpReaderHarnessTests -> stripHeight: 96). Scoring at 48 px re-quantised
# the slicer's normalised rects and cost ~2 per-glyph points (PU.11 F5); one
# height across harness, scorer and training removes that skew.
STRIP_HEIGHT = 96


def _auc(pos: np.ndarray, neg: np.ndarray) -> float | None:
    """Rank-based AUC of two score arrays (Mann-Whitney U / (n_pos * n_neg))."""
    if pos.size == 0 or neg.size == 0:
        return None
    total = 0.0
    for p in pos:
        total += float((neg < p).sum()) + 0.5 * float((neg == p).sum())
    return float(total / (pos.size * neg.size))


def frontier_curve(items: list[tuple[float, bool]]) -> dict:
    """The abstention frontier over ``(margin, digit_correct)`` cells.

    Sorted by the decoder's margin, most confident first; digit accuracy at
    coverage deciles, and the largest coverage whose confident prefix still
    holds 0.99 / 0.95 accuracy - the coverage a commit rule may take at that
    precision. A ranking signal that works makes the curve fall with coverage;
    a useless one makes it flat at the overall accuracy.
    """
    n = len(items)
    if n == 0:
        return {"n": 0, "deciles": [], "coverage_0.99": 0.0, "coverage_0.95": 0.0}
    ordered = sorted(items, key=lambda t: -t[0])
    deciles = []
    for d in range(1, 11):
        k = max(1, int(round(d * n / 10)))
        deciles.append((d * 10, round(sum(1 for _, ok in ordered[:k] if ok) / k, 4)))
    best = {0.99: 0.0, 0.95: 0.0}
    correct = 0
    for i, (_, ok) in enumerate(ordered, 1):
        correct += ok
        for target in best:
            if correct / i >= target:
                best[target] = i / n
    return {"n": n, "deciles": deciles, "coverage_0.99": round(best[0.99], 3),
            "coverage_0.95": round(best[0.95], 3)}


def parse_cells(text: str) -> list[SegmentLabel]:
    """Split a window ``text`` into glyph cells (the naive slicer's truth).

    Each digit is a cell; a ``.`` or ``,`` sets the dp bit on the preceding cell;
    a space is a blank cell; other characters are ignored. This mirrors the
    annotation's decimal placement and never invents a dp-own cell.
    """
    cells: list[SegmentLabel] = []
    for ch in text:
        if ch in "0123456789":
            cells.append(SegmentLabel.from_digit(ch))
        elif ch in ".,":
            if cells and not cells[-1].dp:
                cells[-1] = SegmentLabel(cells[-1].bits | 0x80)
            else:
                cells.append(DP_ONLY)
        elif ch == " ":
            cells.append(BLANK)
    return cells


def make_of(filename: str) -> str:
    """The make token: the third dash-token (``pump-013-dresser…`` -> ``dresser``).

    ``pump-001.heic`` has no third token and is ``unknown``.
    """
    parts = Path(filename).stem.split("-")
    return parts[2] if len(parts) > 2 else "unknown"


def _rotated_size(w: int, h: int, rot_cw: int) -> tuple[int, int]:
    rot = rot_cw % 360
    return (h, w) if rot in (90, 270) else (w, h)


def reading_order(quad: np.ndarray, rot_cw: int) -> np.ndarray:
    """Reorder an annotated quad (TL, TR, BR, BL in image space) into reading order.

    The warp is a homography from these four corners, so a display that reads
    upright only after a clockwise rotation needs its corners rolled, not the
    image rotated: 90 degrees clockwise makes the image's left edge the top edge,
    so the upright top-left is the image's bottom-left. Mirrors
    ``PumpQuadWarp.readingOrder``.
    """
    rot = rot_cw % 360
    shift = {0: 0, 90: 1, 180: 2, 270: -1}[rot]
    return np.roll(np.asarray(quad, dtype=np.float64), shift, axis=0)


def rotate_points_cw(
    points: list[list[float]], rot_cw: int, old_size: tuple[int, int]
) -> np.ndarray:
    """Rotate pixel coords clockwise by ``rot_cw`` degrees, matching PIL ``rotate(-rot)``."""
    rot = rot_cw % 360
    if rot == 0:
        return np.asarray(points, dtype=np.float64)
    w, h = old_size
    a = math.radians(-rot)  # PIL angle is CCW, so clockwise = negative
    ca, sa = math.cos(a), math.sin(a)
    cx, cy = w / 2.0, h / 2.0
    nw, nh = _rotated_size(w, h, rot)
    ncx, ncy = nw / 2.0, nh / 2.0
    out = []
    for x, y in points:
        dx, dy = x - cx, y - cy
        out.append([ca * dx - sa * dy + ncx, sa * dx + ca * dy + ncy])
    return np.asarray(out, dtype=np.float64)


def _quad_size(quad: np.ndarray) -> tuple[float, float]:
    tl, tr, br, bl = quad
    width = (np.linalg.norm(tr - tl) + np.linalg.norm(br - bl)) / 2.0
    height = (np.linalg.norm(bl - tl) + np.linalg.norm(br - tr)) / 2.0
    return float(width), float(height)


TTA_OFFSETS: tuple[tuple[float, float], ...] = (
    (0.0, 0.0), (-0.06, 0.0), (0.06, 0.0), (0.0, -0.06), (0.0, 0.06),
)
"""Test-time augmentation: the centre crop and four shifted by 6 % of the cell's
width / height - the slicer's own placement uncertainty. Probabilities are
averaged over the crops before decoding."""


def slice_cells_from_boxes(
    img: Image.Image, quad: np.ndarray, cell_boxes: list[dict], *, tta: bool = False
) -> list[Image.Image] | list[list[Image.Image]]:
    """Slice a window from PU.4's slicer rects (normalised [0,1] over the strip).

    The strip is warped exactly as ``slice_cells`` warps it, then each cell is
    cropped from its normalised rect and resized to the classifier's 32x48 cell.
    This is the ``--boxes`` path: the slicer's real pitch cells replace the
    equal-width fallback, so the score measures the classifier rather than the
    naive slicer.
    """
    width, height = _quad_size(quad)
    aspect = width / height if height > 0 else 1.0
    sw = max(1, int(round(STRIP_HEIGHT * aspect)))
    sh = STRIP_HEIGHT

    dst = np.array([[0, 0], [sw, 0], [sw, sh], [0, sh]], dtype=np.float64)
    hmat = homography_from_corners(dst, quad)
    coeffs = [
        hmat[0, 0], hmat[0, 1], hmat[0, 2],
        hmat[1, 0], hmat[1, 1], hmat[1, 2],
        hmat[2, 0], hmat[2, 1],
    ]
    strip = img.transform(
        (sw, sh), Image.Transform.PERSPECTIVE, data=coeffs, resample=Image.BILINEAR, fillcolor=0
    )

    cells: list = []
    for box in cell_boxes:
        bw = (box["x1"] - box["x0"]) * sw
        bh = (box["y1"] - box["y0"]) * sh
        crops = []
        for dx, dy in (TTA_OFFSETS if tta else TTA_OFFSETS[:1]):
            x0 = max(0, min(sw - 1, int(round(box["x0"] * sw + dx * bw))))
            x1 = max(x0 + 1, min(sw, int(round(box["x1"] * sw + dx * bw))))
            y0 = max(0, min(sh - 1, int(round(box["y0"] * sh + dy * bh))))
            y1 = max(y0 + 1, min(sh, int(round(box["y1"] * sh + dy * bh))))
            crops.append(strip.crop((x0, y0, x1, y1)).resize((CELL_W, CELL_H), Image.BILINEAR))
        cells.append(crops if tta else crops[0])
    return cells


def slice_cells(
    img: Image.Image, quad: np.ndarray, n_cells: int
) -> tuple[list[Image.Image], list[tuple[float, float]]]:
    """Warp a quad to a 96px strip and slice it into ``n_cells`` equal 32x48 cells.

    Returns the cells and each cell's centre in the original image (for the test
    that checks the centres land inside PU.1's rendered boxes).
    """
    width, height = _quad_size(quad)
    aspect = width / height if height > 0 else 1.0
    sw = max(1, int(round(STRIP_HEIGHT * aspect)))
    sh = STRIP_HEIGHT

    dst = np.array([[0, 0], [sw, 0], [sw, sh], [0, sh]], dtype=np.float64)
    hmat = homography_from_corners(dst, quad)  # strip -> image
    coeffs = [
        hmat[0, 0], hmat[0, 1], hmat[0, 2],
        hmat[1, 0], hmat[1, 1], hmat[1, 2],
        hmat[2, 0], hmat[2, 1],
    ]
    strip = img.transform(
        (sw, sh), Image.Transform.PERSPECTIVE, data=coeffs, resample=Image.BILINEAR, fillcolor=0
    )

    cell_w = sw / n_cells
    cells: list[Image.Image] = []
    centres: list[tuple[float, float]] = []
    for i in range(n_cells):
        x0 = int(round(i * cell_w))
        x1 = int(round((i + 1) * cell_w))
        cells.append(strip.crop((x0, 0, x1, sh)).resize((CELL_W, CELL_H), Image.BILINEAR))
        sx = (i + 0.5) * cell_w
        p = hmat @ np.array([sx, sh / 2.0, 1.0])
        centres.append((float(p[0] / p[2]), float(p[1] / p[2])))
    return cells, centres


def _load_image(path: Path) -> Image.Image:
    with Image.open(path) as img:
        img = ImageOps.exif_transpose(img)
        return img.convert("RGB")


def _to_tensor(img: Image.Image) -> torch.Tensor:
    arr = np.asarray(img, dtype=np.float32).transpose(2, 0, 1) / 255.0
    return torch.from_numpy(arr).unsqueeze(0)


def _cell_label_text(label: SegmentLabel) -> str:
    if label.bits == 0:
        return "blank"
    if label.bits == 0x80:
        return "dp"
    digit = label.digit
    if digit is None:
        return "?"
    return digit + ("dp" if label.dp else "")


def _read_string(bits_list: list[int]) -> str:
    out: list[str] = []
    for bits in bits_list:
        label = SegmentLabel(bits)
        if label.bits == 0:
            out.append(" ")
        else:
            digit = label.digit or "?"
            out.append(digit + ("." if label.dp else ""))
    return "".join(out).rstrip()


def classify_cells(
    model: SegmentNet, cells: list, *, constrained: bool = True
) -> tuple[list[int], list[np.ndarray], list[float]]:
    """Classify cells; returns per-cell (bits, 8-probability-vector).

    ``constrained`` decodes over the valid seven-segment patterns (the shipped
    decoder); ``False`` is the per-bit threshold kept for the A/B.
    """
    model.eval()
    bits: list[int] = []
    probs: list[np.ndarray] = []
    margins: list[float] = []
    with torch.no_grad():
        for cell in cells:
            crops = cell if isinstance(cell, list) else [cell]
            batch = torch.cat([_to_tensor(c) for c in crops])
            p = torch.sigmoid(model(batch)).mean(dim=0).cpu().numpy()
            probs.append(p)
            if constrained:
                b, m = decode_constrained(p, allow_blank=False)
            else:
                b, m = target_to_bits(p), 0.0
            bits.append(b)
            margins.append(m)
    return bits, probs, margins


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="pump_reader.score")
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--windows", type=Path, default=None,
                        help="a windows.json file; omit to read the stills from the database")
    parser.add_argument("--db", type=Path, default=None, help="corpus database (default: the committed one)")
    parser.add_argument("--fixtures", type=Path, required=True)
    parser.add_argument("--dump", type=Path, default=None)
    parser.add_argument("--boxes", type=Path, default=None,
                        help="PU.4 slices.json: slice from the slicer's cell rects")
    parser.add_argument("--fields", default="total,liters,unitPrice",
                        type=lambda v: set(v.split(",")),
                        help="window fields in the headline; the grade-price board is NOT in the "
                             "ship gate (product owner, 2026-09-19) - pass 'board' to see it")
    parser.add_argument("--tta", action="store_true",
                        help="average the probabilities over five shifted crops per cell")
    parser.add_argument("--threshold-decode", action="store_true",
                        help="per-bit 0.5 threshold instead of the constrained decode (A/B only)")
    parser.add_argument("--only-count-correct", action="store_true",
                        help="score only windows whose slicer cell count matches the annotation")
    args = parser.parse_args(argv)

    state = torch.load(args.model, map_location="cpu")
    model = SegmentNet()
    model.load_state_dict(state["state_dict"])
    model.eval()

    if args.windows is not None:
        if not args.windows.exists():
            print(f"windows.json absent: {args.windows}")
            return 1
        windows = json.loads(args.windows.read_text(encoding="utf-8"))
    else:
        con = corpus_db.connect(args.db)
        try:
            windows = corpus_db.entries(con)
        finally:
            con.close()
    boxes = None
    if args.boxes is not None and args.boxes.exists():
        boxes = json.loads(args.boxes.read_text(encoding="utf-8"))

    per_make: dict[str, dict[str, int]] = {}
    seg_correct = np.zeros(8, dtype=np.int64)
    glyph_total = 0
    digit_correct = 0
    frontier_items: list[tuple[float, bool]] = []
    window_digits_correct = 0
    glyph_correct = 0
    window_total = 0
    window_correct = 0
    by_name: dict[str, dict] = {}
    skipped_empty = 0
    dp_y: list[int] = []
    dp_score: list[float] = []

    for filename, ann in windows.items():
        if filename == "_about":
            continue
        path = args.fixtures / filename
        if not path.exists():
            print(f"missing fixture {filename}")
            continue
        img = _load_image(path)
        w, h = img.size
        rot = int(ann.get("rotationCW", 0) or 0)
        make = make_of(filename)
        for wi, win in enumerate(ann.get("windows", [])):
            text = win.get("text", "")
            if not text:
                skipped_empty += 1
                continue
            if win.get("field") not in args.fields:
                continue
            quad = np.asarray(win["quad"], dtype=np.float64) * np.array([w, h])
            quad = reading_order(quad, rot)
            cells_truth = parse_cells(text)
            n = len(cells_truth)
            if n == 0:
                continue
            cell_boxes = None
            if boxes is not None:
                fixture_boxes = boxes.get(filename, [])
                if wi < len(fixture_boxes) and fixture_boxes[wi] is not None:
                    cell_boxes = fixture_boxes[wi].get("cells")
            if args.only_count_correct and (cell_boxes is None or len(cell_boxes) != n):
                continue
            if cell_boxes:
                cells = slice_cells_from_boxes(img, quad, cell_boxes, tta=args.tta)
            else:
                cells, _ = slice_cells(img, quad, n)
            pred_bits, probs, margins = classify_cells(model, cells, constrained=not args.threshold_decode)

            truth_bits = [c.bits for c in cells_truth]
            window_total += 1
            all_correct = True
            digits_ok = True
            for tb, pb, prob, mg in zip(truth_bits, pred_bits, probs, margins):
                glyph_total += 1
                dp_y.append((tb >> 7) & 1)
                dp_score.append(float(prob[7]))
                ok = (pb & 0x7F) == (tb & 0x7F)
                frontier_items.append((mg, ok))
                if ok:
                    digit_correct += 1
                else:
                    digits_ok = False
                seg_correct += (
                    (np.array([(pb >> i) & 1 for i in range(8)]) == bits_to_target(tb)).astype(np.int64)
                )
                if pb == tb:
                    glyph_correct += 1
                else:
                    all_correct = False
            if all_correct:
                window_correct += 1
            if digits_ok:
                window_digits_correct += 1

            field = win.get("field", "?")
            per_make.setdefault(make, {"windows": 0, "correct": 0})
            per_make[make]["windows"] += 1
            if all_correct:
                per_make[make]["correct"] += 1

            # One entry per window, never per fixture: a fixture has up to
            # three transaction windows and the last one used to overwrite.
            key = f"{filename.split('.')[0]}/{field}"
            read = _read_string(pred_bits)
            by_name[key] = {
                "field": field,
                "truth": text,
                "read": read,
                "correct": all_correct,
                "digits_correct": digits_ok,
            }

            if args.dump is not None:
                args.dump.mkdir(parents=True, exist_ok=True)
                for i, (tb, pb, cell) in enumerate(zip(truth_bits, pred_bits, cells)):
                    cell.save(
                        args.dump
                        / f"{key}-{field}-{i}-{_cell_label_text(SegmentLabel(tb))}-"
                        f"{_cell_label_text(SegmentLabel(pb))}.png"
                    )

    per_segment = (seg_correct / glyph_total).tolist() if glyph_total else [0.0] * 8
    dp_pos = np.asarray([s for y, s in zip(dp_y, dp_score) if y == 1])
    dp_neg = np.asarray([s for y, s in zip(dp_y, dp_score) if y == 0])
    dp_auc = _auc(dp_pos, dp_neg)
    result = {
        "fixtures": len(windows),
        "windows_scored": window_total,
        "skipped_empty": skipped_empty,
        "per_segment_accuracy": {_SEGMENT_NAMES[i]: round(per_segment[i], 4) for i in range(8)},
        "per_segment_mean": round(float(np.mean(per_segment)), 4),
        "per_glyph_accuracy": round(glyph_correct / glyph_total, 4) if glyph_total else 0.0,
        # The digit alone (a-g), the dp bit aside: the number PU.5's arithmetic
        # decimal recovery needs, since it places the point itself.
        "per_digit_accuracy": round(digit_correct / glyph_total, 4) if glyph_total else 0.0,
        "frontier": frontier_curve(frontier_items),
        "per_window_digits_accuracy": round(window_digits_correct / window_total, 4) if window_total else 0.0,
        "per_window_accuracy": round(window_correct / window_total, 4) if window_total else 0.0,
        # The dp bit is what keeps per-window near zero (PU.11 F2): its AUC on
        # real cells was a coin flip (0.52) before the comma re-render.
        "dp_auc": round(dp_auc, 4) if dp_auc is not None else None,
        "per_make": {
            m: {"windows": v["windows"], "correct": v["correct"]}
            for m, v in sorted(per_make.items())
        },
        "by_name": by_name,
    }

    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())

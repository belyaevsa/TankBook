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
from .glyph import CELL_H, CELL_W, BLANK, DP_ONLY, SegmentLabel
from .model import SegmentNet

try:
    import pillow_heif

    pillow_heif.register_heif_opener()
    HEIF_OK = True
except Exception:  # pragma: no cover - environment dependent
    HEIF_OK = False

_SEGMENT_NAMES = list("abcdefg") + ["dp"]


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


def slice_cells_from_boxes(
    img: Image.Image, quad: np.ndarray, cell_boxes: list[dict]
) -> list[Image.Image]:
    """Slice a window from PU.4's slicer rects (normalised [0,1] over the strip).

    The strip is warped exactly as ``slice_cells`` warps it, then each cell is
    cropped from its normalised rect and resized to the classifier's 32x48 cell.
    This is the ``--boxes`` path: the slicer's real pitch cells replace the
    equal-width fallback, so the score measures the classifier rather than the
    naive slicer.
    """
    width, height = _quad_size(quad)
    aspect = width / height if height > 0 else 1.0
    sw = max(1, int(round(CELL_H * aspect)))
    sh = CELL_H

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

    cells: list[Image.Image] = []
    for box in cell_boxes:
        x0 = max(0, min(sw - 1, int(round(box["x0"] * sw))))
        x1 = max(x0 + 1, min(sw, int(round(box["x1"] * sw))))
        y0 = max(0, min(sh - 1, int(round(box["y0"] * sh))))
        y1 = max(y0 + 1, min(sh, int(round(box["y1"] * sh))))
        cells.append(strip.crop((x0, y0, x1, y1)).resize((CELL_W, CELL_H), Image.BILINEAR))
    return cells


def slice_cells(
    img: Image.Image, quad: np.ndarray, n_cells: int
) -> tuple[list[Image.Image], list[tuple[float, float]]]:
    """Warp a quad to a 48px strip and slice it into ``n_cells`` equal 32x48 cells.

    Returns the cells and each cell's centre in the original image (for the test
    that checks the centres land inside PU.1's rendered boxes).
    """
    width, height = _quad_size(quad)
    aspect = width / height if height > 0 else 1.0
    sw = max(1, int(round(CELL_H * aspect)))
    sh = CELL_H

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
    model: SegmentNet, cells: list[Image.Image]
) -> tuple[list[int], list[np.ndarray]]:
    """Classify cells; returns per-cell (bits, 8-probability-vector)."""
    model.eval()
    bits: list[int] = []
    probs: list[np.ndarray] = []
    with torch.no_grad():
        for cell in cells:
            p = torch.sigmoid(model(_to_tensor(cell)))[0].cpu().numpy()
            probs.append(p)
            bits.append(target_to_bits(p))
    return bits, probs


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="pump_reader.score")
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--windows", type=Path, required=True)
    parser.add_argument("--fixtures", type=Path, required=True)
    parser.add_argument("--dump", type=Path, default=None)
    parser.add_argument("--boxes", type=Path, default=None,
                        help="PU.4 slices.json: slice from the slicer's cell rects")
    args = parser.parse_args(argv)

    state = torch.load(args.model, map_location="cpu")
    model = SegmentNet()
    model.load_state_dict(state["state_dict"])
    model.eval()

    if not args.windows.exists():
        print(f"windows.json absent: {args.windows}")
        return 1

    windows = json.loads(args.windows.read_text(encoding="utf-8"))
    boxes = None
    if args.boxes is not None and args.boxes.exists():
        boxes = json.loads(args.boxes.read_text(encoding="utf-8"))

    per_make: dict[str, dict[str, int]] = {}
    seg_correct = np.zeros(8, dtype=np.int64)
    glyph_total = 0
    glyph_correct = 0
    window_total = 0
    window_correct = 0
    by_name: dict[str, dict] = {}
    skipped_empty = 0

    for filename, ann in windows.items():
        path = args.fixtures / filename
        if not path.exists():
            print(f"missing fixture {filename}")
            continue
        img = _load_image(path)
        w, h = img.size
        rot = int(ann.get("rotationCW", 0) or 0)
        if rot:
            img = img.rotate(-rot, expand=True)
        make = make_of(filename)
        for wi, win in enumerate(ann.get("windows", [])):
            text = win.get("text", "")
            if not text:
                skipped_empty += 1
                continue
            quad = np.asarray(win["quad"], dtype=np.float64) * np.array([w, h])
            quad = rotate_points_cw(quad.tolist(), rot, (w, h))
            cells_truth = parse_cells(text)
            n = len(cells_truth)
            if n == 0:
                continue
            cell_boxes = None
            if boxes is not None:
                fixture_boxes = boxes.get(filename, [])
                if wi < len(fixture_boxes) and fixture_boxes[wi] is not None:
                    cell_boxes = fixture_boxes[wi].get("cells")
            if cell_boxes:
                cells = slice_cells_from_boxes(img, quad, cell_boxes)
            else:
                cells, _ = slice_cells(img, quad, n)
            pred_bits, _ = classify_cells(model, cells)

            truth_bits = [c.bits for c in cells_truth]
            window_total += 1
            all_correct = True
            for tb, pb in zip(truth_bits, pred_bits):
                glyph_total += 1
                seg_correct += (
                    (np.array([(pb >> i) & 1 for i in range(8)]) == bits_to_target(tb)).astype(np.int64)
                )
                if pb == tb:
                    glyph_correct += 1
                else:
                    all_correct = False
            if all_correct:
                window_correct += 1

            field = win.get("field", "?")
            per_make.setdefault(make, {"windows": 0, "correct": 0})
            per_make[make]["windows"] += 1
            if all_correct:
                per_make[make]["correct"] += 1

            key = filename.split(".")[0]
            read = _read_string(pred_bits)
            by_name[key] = {
                "field": field,
                "truth": text,
                "read": read,
                "correct": all_correct,
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
    result = {
        "fixtures": len(windows),
        "windows_scored": window_total,
        "skipped_empty": skipped_empty,
        "per_segment_accuracy": {_SEGMENT_NAMES[i]: round(per_segment[i], 4) for i in range(8)},
        "per_segment_mean": round(float(np.mean(per_segment)), 4),
        "per_glyph_accuracy": round(glyph_correct / glyph_total, 4) if glyph_total else 0.0,
        "per_window_accuracy": round(window_correct / window_total, 4) if window_total else 0.0,
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

"""CLI: ``python -m pump_reader.segeval --data .out/seg --run .out/seg-r1``.

Scores a trained segmenter with `rotgate` (decision 10 restated for oriented
boxes). The decode thresholds are chosen on the VALIDATION stills (`segtrain`'s
every-10th train still): the pair with the highest recall @ IoU 0.7, ties to
median IoU, among those whose false rows per photo stay at or under
``--max-false`` (default: the shipped detector's heldout 0.647). The heldout
split is then scored once, at the chosen pair; its quads are written to
``<run>/heldout-quads.json`` (normalised to each image) for the Swift arms.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import cv2
import numpy as np
import torch

from pump_reader import rotgate, segnet
from pump_reader.segtrain import GRID, is_val, letterbox


def predict(model: torch.nn.Module, folder: Path, entries: list[dict], device: torch.device):
    out = []
    model.eval()
    with torch.no_grad():
        for e in entries:
            img = cv2.cvtColor(cv2.imread(str(folder / e["image"])), cv2.COLOR_BGR2RGB)
            x, s = letterbox(img)
            t = torch.from_numpy(x.transpose(2, 0, 1) / 255.0).float().unsqueeze(0).to(device)
            p = torch.sigmoid(model(t))[0].cpu().numpy()
            out.append((e, img.shape[1], img.shape[0], s, p))
    return out


def truth_and_found(preds, pixel_t: float, link_t: float, min_short: float, min_area: float, shape: str = "rect"):
    truth, found, normalised = {}, {}, {}
    for e, w, h, s, p in preds:
        truth[e["image"]] = [[(x * w, y * h) for x, y in q] for q in e["quads"]]
        quads = segnet.decode(p[0], p[1:], pixel_t, link_t, min_short, min_area, shape)
        # Output grid -> input canvas (x2) -> original image (/ s).
        found[e["image"]] = [[(float(x) * 2 / s, float(y) * 2 / s) for x, y in q] for q, _ in quads]
        normalised[e["image"]] = [{"quad": [[float(x) * 2 / s / w, float(y) * 2 / s / h] for x, y in q],
                                   "confidence": c} for q, c in quads]
    return truth, found, normalised


def size_floor(entries: list[dict], folder: Path) -> tuple[float, float]:
    """The train split's 1st percentiles of row short side and area on the output
    grid at eval scale (PixelLink §3.4's filter rule, re-fitted - adaptation B7)."""
    shorts, areas = [], []
    for e in entries:
        if not e["quads"]:
            continue
        h, w = cv2.imread(str(folder / e["image"])).shape[:2]
        s = (512 / max(w, h)) / 2
        for q in e["quads"]:
            box = np.array(q, np.float32) * [w * s, h * s]
            (_, _), (rw, rh), _ = cv2.minAreaRect(box.astype(np.float32))
            shorts.append(min(rw, rh))
            areas.append(rw * rh)
    return float(np.percentile(shorts, 1)), float(np.percentile(areas, 1))


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="pump_reader.segeval")
    p.add_argument("--data", type=Path, required=True)
    p.add_argument("--run", type=Path, required=True)
    p.add_argument("--max-false", type=float, default=0.647)
    p.add_argument("--shape", choices=["rect", "quad"], default="rect")
    args = p.parse_args(argv)
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    ck = torch.load(args.run / "segnet.pt", map_location="cpu")
    model = segnet.SegNet(ck["width"])
    model.load_state_dict(ck["state_dict"])
    model.to(device)
    train_dir, held_dir = args.data / "train", args.data / "heldout"
    entries = json.loads((train_dir / "index.json").read_text())
    val = [e for e in entries if is_val(e)]
    held = json.loads((held_dir / "index.json").read_text())
    min_short, min_area = size_floor([e for e in entries if not is_val(e)], train_dir)
    print(f"size floor (output grid): short side >= {min_short:.2f}, area >= {min_area:.1f}")

    val_preds = predict(model, train_dir, val, device)
    best = None
    for pt in (0.5, 0.6, 0.7, 0.8, 0.9):
        for lt in (0.5, 0.7, 0.8, 0.9):
            truth, found, _ = truth_and_found(val_preds, pt, lt, min_short, min_area, args.shape)
            sc = rotgate.score(truth, found)
            fr = sc.false_rows / max(sc.photos, 1)
            print(sc.line(f"val pixel {pt} link {lt}"))
            key = (sc.hit70 / max(sc.rows, 1), sc.median_iou)
            if fr <= args.max_false and (best is None or key > best[0]):
                best = (key, pt, lt)
    if best is None:
        print("no threshold pair keeps false rows under the ceiling on val")
        return 1
    _, pt, lt = best
    t0 = time.time()
    held_preds = predict(model, held_dir, held, device)
    t_model = (time.time() - t0) / max(len(held), 1)
    truth, found, normalised = truth_and_found(held_preds, pt, lt, min_short, min_area, args.shape)
    sc = rotgate.score(truth, found)
    print(f"chosen on val: pixel {pt}, link {lt}")
    print(sc.line("HELDOUT segmenter (rotated metric)"))
    print(f"mean per-image model time (MPS, incl. load and letterbox): {t_model * 1000:.1f} ms")
    for line in sc.per_photo:
        print("  " + line)
    (args.run / f"heldout-quads{'' if args.shape == 'rect' else '-' + args.shape}.json").write_text(json.dumps(
        {"pixel_t": pt, "link_t": lt, "min_short": min_short, "min_area": min_area, "images": normalised}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

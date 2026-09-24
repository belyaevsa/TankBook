"""CLI: ``python -m pump_reader.segtrain --data .out/seg --out .out/seg-run [--steps 20000]``.

Trains the PU.76 spike's pixel + link segmenter (`segnet`) on `segdata`'s train
directory. Every 10th train STILL (by a stable hash of its name) is held out as
a validation set for choosing the decode thresholds - never the heldout split,
which only scores. Augmentation (adaptation B4): a random scale and placement on
the 512 canvas, an in-plane turn (mostly within +-6 deg, sometimes +-12..25 deg,
the train split's tilted rows), and photometric jitter; quads are carried by the
same affine map, so the masks stay exact.
"""

from __future__ import annotations

import argparse
import json
import math
import time
import zlib
from pathlib import Path

import cv2
import numpy as np
import torch
from torch.utils.data import DataLoader, Dataset

from pump_reader import segnet

SIZE = 512
GRID = SIZE // 2


def is_val(entry: dict) -> bool:
    """Every 10th train still (not a frame, not a negative), stable across runs."""
    src = entry["source"]
    return "/" not in src and src.startswith("pump-") and zlib.crc32(src.encode()) % 10 == 0


def letterbox(img: np.ndarray) -> tuple[np.ndarray, float]:
    """The eval-time input: the image fitted into the canvas at the top left."""
    h, w = img.shape[:2]
    s = SIZE / max(h, w)
    canvas = np.zeros((SIZE, SIZE, 3), np.uint8)
    small = cv2.resize(img, (round(w * s), round(h * s)), interpolation=cv2.INTER_AREA)
    canvas[: small.shape[0], : small.shape[1]] = small
    return canvas, s


class SegDataset(Dataset):
    def __init__(self, folder: Path, entries: list[dict], seed: int, augment: bool):
        self.folder, self.entries, self.augment = folder, entries, augment
        self.rng = np.random.default_rng(seed)

    def __len__(self) -> int:
        return len(self.entries)

    def __getitem__(self, i: int):
        e = self.entries[i]
        img = cv2.cvtColor(cv2.imread(str(self.folder / e["image"])), cv2.COLOR_BGR2RGB)
        h, w = img.shape[:2]
        quads = [np.array(q, np.float64) * [w, h] for q in e["quads"]]
        rng = np.random.default_rng(self.rng.integers(1 << 31) + i) if self.augment else None
        if self.augment:
            u = rng.random()
            angle = rng.uniform(-6, 6) if u < 0.55 else (rng.choice([-1, 1]) * rng.uniform(12, 25) if u < 0.75 else 0.0)
            scale = SIZE / max(h, w) * rng.uniform(0.7, 1.25)
            m = cv2.getRotationMatrix2D((w / 2, h / 2), angle, scale)
            # Place the turned, scaled centre somewhere that keeps most of the frame on the canvas.
            m[0, 2] += SIZE / 2 - w / 2 + rng.uniform(-0.2, 0.2) * SIZE
            m[1, 2] += SIZE / 2 - h / 2 + rng.uniform(-0.2, 0.2) * SIZE
            x = cv2.warpAffine(img, m, (SIZE, SIZE), flags=cv2.INTER_LINEAR, borderValue=(0, 0, 0))
            x = x.astype(np.float32) * rng.uniform(0.7, 1.3) + rng.uniform(-25, 25)
            if rng.random() < 0.2:
                x = np.repeat(x.mean(axis=2, keepdims=True), 3, axis=2)
            if rng.random() < 0.2:
                x = cv2.GaussianBlur(x, (0, 0), rng.uniform(0.5, 1.5))
            x = np.clip(x, 0, 255)
            quads = [np.c_[q, np.ones(4)] @ m.T for q in quads]
        else:
            x, s = letterbox(img)
            x = x.astype(np.float32)
            quads = [q * s for q in quads]
        pixel, links, weight = segnet.targets([q / 2 for q in quads], GRID)
        t = torch.from_numpy(x.transpose(2, 0, 1) / 255.0).float()
        return t, torch.from_numpy(pixel), torch.from_numpy(links), torch.from_numpy(weight)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="pump_reader.segtrain")
    p.add_argument("--data", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--steps", type=int, default=20_000)
    p.add_argument("--batch", type=int, default=8)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--width", type=int, default=16)
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--workers", type=int, default=6)
    args = p.parse_args(argv)
    torch.manual_seed(args.seed)
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    folder = args.data / "train"
    entries = json.loads((folder / "index.json").read_text())
    train = [e for e in entries if not is_val(e)]
    val = [e for e in entries if is_val(e)]
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "split.json").write_text(json.dumps({"train": len(train), "val": [e["source"] for e in val]}))
    loader = DataLoader(SegDataset(folder, train, args.seed, True), batch_size=args.batch, shuffle=True,
                        num_workers=args.workers, persistent_workers=args.workers > 0, drop_last=True)
    model = segnet.SegNet(args.width).to(device)
    opt = torch.optim.Adam(model.parameters(), lr=args.lr)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=args.lr, total_steps=args.steps, pct_start=0.05)
    step, t0, running = 0, time.time(), []
    print(f"train {len(train)} images, val {len(val)} stills, device {device}, "
          f"params {sum(q.numel() for q in model.parameters())}", flush=True)
    while step < args.steps:
        for x, pixel, links, weight in loader:
            x, pixel, links, weight = (v.to(device) for v in (x, pixel, links, weight))
            model.train()
            loss = segnet.loss(model(x), pixel, links, weight)
            opt.zero_grad()
            loss.backward()
            opt.step()
            sched.step()
            running.append(float(loss.detach()))
            step += 1
            if step % 100 == 0:
                print(f"step {step} loss {np.mean(running):.4f} {time.time() - t0:.0f}s", flush=True)
                running = []
            if step % 2000 == 0 or step == args.steps:
                torch.save({"state_dict": model.state_dict(), "width": args.width, "step": step},
                           args.out / "segnet.pt")
            if step >= args.steps:
                break
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

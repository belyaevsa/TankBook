"""CLI: ``python -m pump_reader.train --steps N --seed S --out DIR``.

Trains ``SegmentNet`` on ``SyntheticDataset`` renders only, with AdamW and a
cosine learning-rate schedule, and writes ``DIR/segmentnet.pt`` and
``DIR/metrics.json``. ``--smoke`` runs 20 steps for the test; validation is a
fixed 5 000-sample seed range disjoint from the training range.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
import torch
from torch import nn
from torch.utils.data import DataLoader

from .dataset import SyntheticDataset
from .glyph import SEGMENTS
from .model import SegmentNet

VAL_SEED_OFFSET = 1_000_000
VAL_SIZE = 5_000
SMOKE_VAL_SIZE = 512
LOG_EVERY = 200
SEGMENT_NAMES = list(SEGMENTS) + ["dp"]


def _collate(batch: list[tuple[np.ndarray, np.ndarray]]) -> tuple[torch.Tensor, torch.Tensor]:
    xs = torch.from_numpy(np.stack([b[0] for b in batch]))
    ys = torch.from_numpy(np.stack([b[1] for b in batch]))
    return xs, ys


def _predict(model: nn.Module, xs: torch.Tensor) -> torch.Tensor:
    model.eval()
    with torch.no_grad():
        return torch.sigmoid(model(xs))


def _metrics(model: nn.Module, loader: DataLoader, device: torch.device) -> dict:
    """Loss and per-segment / per-digit accuracy over a full loader."""
    loss_fn = nn.BCEWithLogitsLoss()
    total = 0
    loss_sum = 0.0
    seg_correct = np.zeros(8, dtype=np.int64)
    digit_correct = 0
    with torch.no_grad():
        for xs, ys in loader:
            xs = xs.to(device)
            ys = ys.to(device)
            logits = model(xs)
            loss_sum += float(loss_fn(logits, ys)) * xs.shape[0]
            probs = torch.sigmoid(logits)
            pred = (probs >= 0.5).float()
            seg_correct += (pred == ys).sum(dim=0).cpu().numpy().astype(np.int64)
            digit_correct += int((pred == ys).all(dim=1).sum().item())
            total += xs.shape[0]
    per_segment = seg_correct / total
    return {
        "loss": loss_sum / total,
        "per_segment_accuracy": float(per_segment.mean()),
        "per_digit_accuracy": digit_correct / total,
        "per_bit_accuracy": {SEGMENT_NAMES[i]: float(per_segment[i]) for i in range(8)},
        "samples": total,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="pump_reader.train")
    parser.add_argument("--steps", type=int, default=6_000)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--lr", type=float, default=3e-3)
    parser.add_argument("--train-size", type=int, default=60_000)
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--spill-prob", type=float, default=0.0)
    parser.add_argument("--contrast-prob", type=float, default=0.15)
    parser.add_argument("--framing", type=str, default="slicer", choices=["slicer", "glyph"])
    args = parser.parse_args(argv)

    smoke = args.smoke
    steps = 20 if smoke else args.steps
    val_size = SMOKE_VAL_SIZE if smoke else VAL_SIZE
    args.out.mkdir(parents=True, exist_ok=True)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    rng = np.random.default_rng(args.seed)
    torch.manual_seed(args.seed)

    recipe = {
        "spill_prob": args.spill_prob,
        "contrast_prob": args.contrast_prob,
        "framing": args.framing,
    }
    train_ds = SyntheticDataset(seed=args.seed, length=args.train_size, cache=True, **recipe)
    val_ds = SyntheticDataset(
        seed=args.seed + VAL_SEED_OFFSET, length=val_size, cache=True, **recipe
    )
    train_loader = DataLoader(
        train_ds, batch_size=args.batch_size, shuffle=True, collate_fn=_collate, num_workers=0
    )
    val_loader = DataLoader(
        val_ds, batch_size=args.batch_size, shuffle=False, collate_fn=_collate, num_workers=0
    )

    model = SegmentNet().to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr)
    loss_fn = nn.BCEWithLogitsLoss()

    def lr_at(step: int) -> float:
        if steps <= 1:
            return args.lr
        progress = step / steps
        return args.lr * 0.5 * (1.0 + np.cos(np.pi * progress))

    initial = _metrics(model, val_loader, device)
    history: list[dict] = []
    t0 = time.time()

    train_iter = iter(train_loader)
    for step in range(1, steps + 1):
        for group in optimizer.param_groups:
            group["lr"] = lr_at(step - 1)
        try:
            xs, ys = next(train_iter)
        except StopIteration:
            train_iter = iter(train_loader)
            xs, ys = next(train_iter)
        xs = xs.to(device)
        ys = ys.to(device)
        model.train()
        optimizer.zero_grad()
        loss = loss_fn(model(xs), ys)
        loss.backward()
        optimizer.step()

        if step % LOG_EVERY == 0 or step == steps:
            m = _metrics(model, val_loader, device)
            history.append({"step": step, **m})
            print(
                f"step {step:5d}/{steps}  loss {m['loss']:.4f}  "
                f"seg {m['per_segment_accuracy']:.4f}  "
                f"digit {m['per_digit_accuracy']:.4f}",
                flush=True,
            )

    final = history[-1] if history else _metrics(model, val_loader, device)
    wall = time.time() - t0

    torch.save(
        {"state_dict": model.state_dict(), "seed": args.seed, "steps": steps},
        args.out / "segmentnet.pt",
    )
    metrics = {
        "steps": steps, "spill_prob": args.spill_prob, "contrast_prob": args.contrast_prob,
        "framing": args.framing,
        "seed": args.seed,
        "wall_seconds": round(wall, 1),
        "train_size": args.train_size,
        "val_size": val_size,
        "initial_val_loss": round(initial["loss"], 6),
        "initial_val_per_segment_accuracy": round(initial["per_segment_accuracy"], 6),
        "initial_val_per_digit_accuracy": round(initial["per_digit_accuracy"], 6),
        "final_val_loss": round(final["loss"], 6),
        "final_val_per_segment_accuracy": round(final["per_segment_accuracy"], 6),
        "final_val_per_digit_accuracy": round(final["per_digit_accuracy"], 6),
        "final_val_per_bit_accuracy": final["per_bit_accuracy"],
        "history": history,
    }
    (args.out / "metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    print(f"done: {wall:.1f}s  final digit acc {final['per_digit_accuracy']:.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

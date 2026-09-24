"""CLI: ``python -m pump_reader.train --steps N --seed S --out DIR``.

Trains ``SegmentNet`` on ``SyntheticDataset`` renders - and, with
``--real DIR``, on the real glyphs ``pump_reader.realglyphs`` cut from the
train split (decision 9), mixed in at ``--real-frac`` of every batch with
light augmentation - with AdamW and a cosine learning-rate schedule, and
writes ``DIR/segmentnet.pt`` and ``DIR/metrics.json``. ``--smoke`` runs 20
steps for the test; validation is a fixed 5 000-sample synthetic seed range
disjoint from the training range (the real set is never validated on here:
the held-out corpus ratchets are its measurement).
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

from .dataset import SyntheticDataset, bits_to_target
from .glyph import SEGMENTS
from .model import SegmentNet

VAL_SEED_OFFSET = 1_000_000
VAL_SIZE = 5_000
SMOKE_VAL_SIZE = 512
LOG_EVERY = 200
SEGMENT_NAMES = list(SEGMENTS) + ["dp"]


def _parse_priors(value: str) -> dict[str, float]:
    lcd, led, vfd = (float(v) for v in value.split(","))
    return {"lcd": lcd, "led": led, "vfd": vfd}


def _collate(batch: list[tuple[np.ndarray, np.ndarray]]) -> tuple[torch.Tensor, torch.Tensor]:
    xs = torch.from_numpy(np.stack([b[0] for b in batch]))
    ys = torch.from_numpy(np.stack([b[1] for b in batch]))
    return xs, ys


class RealGlyphs:
    """The real-glyph set as a sampler: a random batch of ``n`` cells, each
    with a small photometric and geometric jitter (the renders get the same
    kind through ``augment``), as float tensors ready to concatenate with a
    synthetic batch."""

    def __init__(self, folder: Path, seed: int, *, dp_bits: bool = True):
        data = np.load(folder / "cells.npz")
        self.x = data["x"]  # [n, 3, 48, 32] uint8
        self.y = np.stack([bits_to_target(int(b)) for b in data["y"]]).astype(np.float32)
        if not dp_bits:
            self.y[:, 7] = 0.0
        self.rng = np.random.default_rng(seed + 7)

    def __len__(self) -> int:
        return len(self.x)

    def batch(self, n: int) -> tuple[torch.Tensor, torch.Tensor]:
        idx = self.rng.integers(0, len(self.x), size=n)
        x = self.x[idx].astype(np.float32) / 255.0
        # Brightness / contrast jitter per sample, an occasional polarity flip
        # (dark-on-light and light-on-dark LCDs both exist), and a 1-2 px shift.
        gain = self.rng.uniform(0.75, 1.25, size=(n, 1, 1, 1)).astype(np.float32)
        bias = self.rng.uniform(-0.12, 0.12, size=(n, 1, 1, 1)).astype(np.float32)
        x = np.clip(x * gain + bias, 0.0, 1.0)
        flip = self.rng.random(n) < 0.15
        x[flip] = 1.0 - x[flip]
        dx = self.rng.integers(-2, 3, size=n)
        dy = self.rng.integers(-2, 3, size=n)
        for i in range(n):
            if dx[i] or dy[i]:
                x[i] = np.roll(x[i], (int(dy[i]), int(dx[i])), axis=(1, 2))
        return torch.from_numpy(x), torch.from_numpy(self.y[idx])


def _predict(model: nn.Module, xs: torch.Tensor) -> torch.Tensor:
    model.eval()
    with torch.no_grad():
        return torch.sigmoid(model(xs))


def _metrics(model: nn.Module, loader: DataLoader, device: torch.device, n_bits: int = 8) -> dict:
    """Loss and per-segment / per-digit accuracy over a full loader.

    ``n_bits`` is 8, or 7 when the dp bit is dropped from training
    (``--dp-bits 7``): the untrained dp output is not scored."""
    loss_fn = nn.BCEWithLogitsLoss()
    total = 0
    loss_sum = 0.0
    seg_correct = np.zeros(n_bits, dtype=np.int64)
    digit_correct = 0
    with torch.no_grad():
        for xs, ys in loader:
            xs = xs.to(device)
            ys = ys.to(device)
            logits = model(xs)[:, :n_bits]
            ys = ys[:, :n_bits]
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
        "per_bit_accuracy": {SEGMENT_NAMES[i]: float(per_segment[i]) for i in range(n_bits)},
        "samples": total,
    }


def dp_pos_weight_vector(n_bits: int, dp_weight: float) -> torch.Tensor:
    """Unit positive weights on every segment bit and `dp_weight` on the
    decimal point (bit 7) alone, when the model has one."""
    weights = torch.ones(n_bits)
    if n_bits == 8:
        weights[7] = dp_weight
    return weights


def pool_framing(folder: Path) -> dict:
    """The dp framing a realglyphs pool was built with, from its manifest. A
    manifest from before `--dp-bits` existed carries `dp_crop: none` for a
    cleared pool."""
    manifest = json.loads((folder / "manifest.json").read_text())
    crop = manifest.get("dp_crop", "off")
    bits = manifest.get("dp_bits", "clear" if crop == "none" else "keep")
    return {"dp_crop": "off" if crop == "none" else crop, "dp_bits": bits}


def resolve_dp_bits(requested: int | None, pool_bits: str | None) -> int:
    """7 or 8 output bits to train: the request, else the pool's choice, else 8.
    An 8-bit run on a pool whose dp bits were cleared is refused."""
    if requested == 8 and pool_bits == "clear":
        raise SystemExit("--dp-bits 8 on a pool built with --dp-bits clear: the dp bit would train on zeros")
    if requested is not None:
        return requested
    return 7 if pool_bits == "clear" else 8


def build_parser() -> argparse.ArgumentParser:
    """The training CLI; split out so its defaults can be asserted."""
    return _PARSER


def segment_loss(pos_weight: torch.Tensor, gamma: float, alpha: float | None):
    """The training loss over the per-segment logits. With `pos_weight` all ones,
    `gamma` 0 and no `alpha` it is `BCEWithLogitsLoss()` exactly. The focal factor
    `(1 - p_t) ** gamma` is taken from the HARD target so label smoothing does not
    soften it; the cross-entropy term keeps the smoothed target."""
    def loss(logits: torch.Tensor, targets: torch.Tensor, hard: torch.Tensor) -> torch.Tensor:
        ce = nn.functional.binary_cross_entropy_with_logits(
            logits, targets, pos_weight=pos_weight, reduction="none")
        if gamma > 0 or alpha is not None:
            p = torch.sigmoid(logits)
            p_t = p * hard + (1 - p) * (1 - hard)
            weight = (1 - p_t) ** gamma if gamma > 0 else torch.ones_like(p_t)
            if alpha is not None:
                weight = weight * (alpha * hard + (1 - alpha) * (1 - hard))
            ce = ce * weight
        return ce.mean()
    return loss


def _make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="pump_reader.train")
    parser.add_argument("--steps", type=int, default=6_000)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--lr", type=float, default=3e-3)
    parser.add_argument("--train-size", type=int, default=60_000)
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--spill-prob", type=float, default=0.0)
    parser.add_argument("--contrast-prob", type=float, default=0.5)
    # Synthetic data is separable, so plain BCE drives the logits to saturation
    # and the model is then confidently wrong on real cells; smoothing the
    # targets keeps a margin that still ranks (the abstention frontier).
    parser.add_argument("--label-smoothing", type=float, default=0.05)
    parser.add_argument("--framing", type=str, default="slicer", choices=["slicer", "glyph"])
    parser.add_argument("--real", type=Path, default=None, help="pump_reader.realglyphs output folder")
    parser.add_argument("--real-frac", type=float, default=0.3, help="share of each batch drawn from --real")
    # 8 trains the decimal-point output; 7 clears the synthetic dp target and
    # drops the dp term from the loss, so the 8th output is untrained and
    # unscored. The default follows the --real pool's manifest (a pool built
    # with `realglyphs --dp-bits clear` trains 7), else 8; asking for 8 on a
    # cleared pool is refused, since the dp bit would learn from zeros.
    parser.add_argument("--dp-bits", type=int, choices=[7, 8], default=None)
    # PU.73 Round A (agents/research/PU.73.md §3.1): the dp bit is ~22 % positive.
    # `--dp-pos-weight` is class-balanced cross-entropy on dp alone (Lin et al.
    # 2017 eq. 3, as a positive weight); `--focal-gamma` is the focal loss (eq. 5),
    # its modulating factor from the hard target, with `--focal-alpha` balancing
    # positives. The defaults (1.0, 0, none) are exactly the unweighted BCE the
    # shipped model trained with.
    parser.add_argument("--head", choices=["gap", "flatten", "coord"], default="gap")
    parser.add_argument("--dp-pos-weight", type=float, default=1.0)
    parser.add_argument("--focal-gamma", type=float, default=0.0)
    parser.add_argument("--focal-alpha", type=float, default=None)
    parser.add_argument("--priors", type=str, default=None,
                        help="technology priors as lcd,led,vfd (default: dataset.py's LCD-heavy prior)")
    return parser


_PARSER = _make_parser()


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    smoke = args.smoke
    steps = 20 if smoke else args.steps
    val_size = SMOKE_VAL_SIZE if smoke else VAL_SIZE
    args.out.mkdir(parents=True, exist_ok=True)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    rng = np.random.default_rng(args.seed)
    torch.manual_seed(args.seed)

    pool = pool_framing(args.real) if args.real else {"dp_crop": None, "dp_bits": None}
    n_bits = resolve_dp_bits(args.dp_bits, pool["dp_bits"])
    dp_bits = n_bits == 8
    priors = _parse_priors(args.priors) if args.priors else None
    recipe = {
        "spill_prob": args.spill_prob,
        "contrast_prob": args.contrast_prob,
        "framing": args.framing,
        "technology_priors": priors,
        "dp_bits": dp_bits,
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

    real = RealGlyphs(args.real, args.seed, dp_bits=dp_bits) if args.real else None
    real_n = int(round(args.batch_size * args.real_frac)) if real else 0
    if real:
        print(f"real glyphs: {len(real)} cells from {args.real}, {real_n} of every {args.batch_size}")

    model = SegmentNet(args.head).to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr)
    pos_weight = dp_pos_weight_vector(n_bits, args.dp_pos_weight).to(device)
    loss_fn = segment_loss(pos_weight, args.focal_gamma, args.focal_alpha)

    def lr_at(step: int) -> float:
        if steps <= 1:
            return args.lr
        progress = step / steps
        return args.lr * 0.5 * (1.0 + np.cos(np.pi * progress))

    initial = _metrics(model, val_loader, device, n_bits)
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
        if real and real_n:
            rx, ry = real.batch(real_n)
            xs = torch.cat([xs[: args.batch_size - real_n], rx])
            ys = torch.cat([ys[: args.batch_size - real_n], ry])
        xs = xs.to(device)
        ys = ys.to(device)
        model.train()
        optimizer.zero_grad()
        hard = ys[:, :n_bits]
        if args.label_smoothing > 0:
            ys = ys * (1 - args.label_smoothing) + 0.5 * args.label_smoothing
        loss = loss_fn(model(xs)[:, :n_bits], ys[:, :n_bits], hard)
        loss.backward()
        optimizer.step()

        if step % LOG_EVERY == 0 or step == steps:
            m = _metrics(model, val_loader, device, n_bits)
            history.append({"step": step, **m})
            print(
                f"step {step:5d}/{steps}  loss {m['loss']:.4f}  "
                f"seg {m['per_segment_accuracy']:.4f}  "
                f"digit {m['per_digit_accuracy']:.4f}",
                flush=True,
            )

    final = history[-1] if history else _metrics(model, val_loader, device, n_bits)
    wall = time.time() - t0

    torch.save(
        {"state_dict": model.state_dict(), "seed": args.seed, "steps": steps, "head": args.head},
        args.out / "segmentnet.pt",
    )
    metrics = {
        "steps": steps, "spill_prob": args.spill_prob, "contrast_prob": args.contrast_prob,
        "framing": args.framing, "dp_bits": n_bits,
        "pool_dp_crop": pool["dp_crop"], "pool_dp_bits": pool["dp_bits"],
        "head": args.head, "dp_pos_weight": args.dp_pos_weight,
        "focal_gamma": args.focal_gamma, "focal_alpha": args.focal_alpha, "loss_reduction": "mean",
        "priors": priors or "default",
        "real": str(args.real) if args.real else None,
        "real_cells": len(real) if real else 0,
        "real_frac": args.real_frac if real else 0.0,
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

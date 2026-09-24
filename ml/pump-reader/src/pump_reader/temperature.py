"""Temperature scaling for the segment classifier: a per-model confidence unit.

Not ``calibrate.py`` - that module calibrates the synthetic RENDERER's geometry;
this one calibrates the MODEL's probabilities (agents/research/PU.72.md §3.2).

One shared temperature ``T`` per exported model, fitted by negative log-likelihood
on the TRAIN split's real glyph cells (Guo et al., ICML 2017, arXiv:1706.04599,
§4.2 eq. 9; fit by NLL, never by a calibration error - Nixon et al.,
arXiv:1904.01685). Over eight independent sigmoids a shared ``T`` scales every
digit-pattern log-likelihood difference by ``1/T``, so it changes no ranking and
no decision of the reader's law; what it gives is a common unit in which two
candidate models' margins can be compared (PU.72 §3.1, §5.3). It is fitted
in-sample - the classifier trained on these cells - and for the shipped model a
train-fitted ``T`` measurably worsens heldout calibration (PU.72 §5.2 F4), so it
is a comparison unit for candidates, not a correction shipped to the device.

Three calibration errors are reported, none fitted: Guo's M=15 confidence ECE
(mass-weighted), a per-label fixed-width ECE, and Henning et al.'s ECE_ML
(arXiv 2026, eq. 7, adaptive bins, unweighted - the tail the law dies on).

    python -m pump_reader.temperature <segmentnet.pt> <cells.npz> [--out temperature.json]
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

PATTERNS = [0b0111111, 0b0000110, 0b1011011, 0b1001111, 0b1100110,
            0b1101101, 0b1111101, 0b0000111, 0b1111111, 0b1101111]


def sigmoid(z: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-z))


def nll(z: np.ndarray, y: np.ndarray, T: float) -> float:
    """Mean binary cross-entropy of labels ``y`` under logits ``z / T``, in a stable form."""
    w = z / T
    loss = np.where(w >= 0, (1 - y) * w + np.log1p(np.exp(-np.clip(w, 0, None))),
                    -y * w + np.log1p(np.exp(np.clip(w, None, 0))))
    return float(loss.mean())


def fit_temperature(z: np.ndarray, y: np.ndarray, iterations: int = 200) -> float:
    """The shared ``T`` minimising NLL: golden-section on ``log T`` over [0.05, 20]
    (a one-dimensional convex problem, Guo §5)."""
    lo, hi = np.log(0.05), np.log(20.0)
    for _ in range(iterations):
        m1 = lo + (hi - lo) / 3
        m2 = hi - (hi - lo) / 3
        if nll(z, y, float(np.exp(m1))) < nll(z, y, float(np.exp(m2))):
            hi = m2
        else:
            lo = m1
    return float(np.exp((lo + hi) / 2))


def ece_confidence(y: np.ndarray, p: np.ndarray, bins: int = 15) -> float:
    """Guo eq. 3 over the binary predictions of every label."""
    y, p = y.ravel(), p.ravel()
    conf = np.where(p >= 0.5, p, 1 - p)
    correct = ((p >= 0.5) == (y == 1)).astype(float)
    edges = np.linspace(0.5, 1.0, bins + 1)
    index = np.clip(np.digitize(conf, edges[1:-1]), 0, bins - 1)
    total = 0.0
    for m in range(bins):
        sel = index == m
        if sel.any():
            total += sel.sum() / len(p) * abs(correct[sel].mean() - conf[sel].mean())
    return float(total)


def ece_per_label(y: np.ndarray, p: np.ndarray, bins: int = 10) -> float:
    """Per-label fixed-width ECE over [0, 1], averaged over labels."""
    values = []
    for k in range(p.shape[1]):
        pk, yk = p[:, k], y[:, k]
        edges = np.linspace(0, 1, bins + 1)
        index = np.clip(np.digitize(pk, edges[1:-1]), 0, bins - 1)
        total = 0.0
        for m in range(bins):
            sel = index == m
            if sel.any():
                total += sel.sum() / len(pk) * abs(yk[sel].mean() - pk[sel].mean())
        values.append(total)
    return float(np.mean(values))


def ece_ml(y: np.ndarray, p: np.ndarray, b: int = 10, b_min: int = 5) -> float:
    """Henning et al. eq. 7 with adaptive_ML binning: per label, positives and
    negatives binned separately, b/2 adaptive bins each of at least b_min; the
    bins are averaged UNWEIGHTED, so the confident-wrong tail counts."""
    per_label = []
    for k in range(p.shape[1]):
        pk, yk = p[:, k], y[:, k]
        errors = []
        for side in (1, 0):
            ps = pk[yk == side]
            if len(ps) == 0:
                continue
            count = b // 2
            while count > 1 and len(ps) / count < b_min:
                count -= 1
            order = np.argsort(ps)
            for group in np.array_split(order, count):
                if len(group):
                    errors.append(abs(float(side) - ps[group].mean()))
        if errors:
            per_label.append(float(np.mean(errors)))
    return float(np.mean(per_label)) if per_label else float("nan")


def digit_ranks(p: np.ndarray) -> np.ndarray:
    """The digit each cell ranks first by pattern log-likelihood (the Swift decoder's rule)."""
    q = np.clip(p[:, :7], 1e-6, 1 - 1e-6)
    log_odds = np.log(q) - np.log(1 - q)
    scores = np.stack([sum(((pattern >> i) & 1) * log_odds[:, i] for i in range(7))
                       for pattern in PATTERNS], axis=1)
    return np.argmax(scores, axis=1)


def report(z: np.ndarray, y: np.ndarray) -> dict:
    """Fit ``T`` and report calibration before and after; ``digitFlips`` must be 0."""
    T = fit_temperature(z, y)
    before, after = sigmoid(z), sigmoid(z / T)
    return {
        "temperature": round(T, 4),
        "cells": int(len(y)),
        "nll": [round(nll(z, y, 1.0), 5), round(nll(z, y, T), 5)],
        "eceConfidence15": [round(ece_confidence(y, before), 4), round(ece_confidence(y, after), 4)],
        "ecePerLabel10": [round(ece_per_label(y, before), 4), round(ece_per_label(y, after), 4)],
        "eceML": [round(ece_ml(y, before), 4), round(ece_ml(y, after), 4)],
        "digitFlips": int((digit_ranks(before) != digit_ranks(after)).sum()),
        "note": "fitted in-sample on the train split; a comparison unit, not shipped (PU.72)",
    }


def logits(checkpoint: Path, x: np.ndarray) -> np.ndarray:
    import torch

    from pump_reader.model import SegmentNet

    state = torch.load(checkpoint, map_location="cpu")
    net = SegmentNet(state.get("head", "gap"))
    net.load_state_dict(state["state_dict"])
    net.eval()
    out = []
    with torch.no_grad():
        for i in range(0, len(x), 1024):
            out.append(net(torch.from_numpy(x[i:i + 1024].astype(np.float32) / 255.0)).numpy())
    return np.concatenate(out, axis=0)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("cells", type=Path, help="a real-glyph pool (cells.npz) of the TRAIN split")
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args()
    pool = np.load(args.cells)
    y = np.stack([(pool["y"] >> i) & 1 for i in range(8)], axis=1).astype(np.float64)
    result = report(logits(args.checkpoint, pool["x"]), y)
    text = json.dumps(result, indent=1)
    print(text)
    out = args.out or args.checkpoint.parent / "temperature.json"
    out.write_text(text + "\n")


if __name__ == "__main__":
    main()

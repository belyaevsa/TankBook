"""The row-level sequence reader (PU.77 spike): CRNN (Shi, Bai, Yao, TPAMI 2017) trained with CTC
(Graves et al., ICML 2006), as `agents/research/PU.77.md` §4 settles it.

* Input: the 96 px strip the reader warps from a row's quad, scaled to height 32 with its aspect
  kept, right-padded with its own edge column to at least 100 px (CRNN §3.2's test rule; CTC needs
  ``T >= 2U + 1``, note §4.2), capped at 160.
* Alphabet (note §4.3): CTC blank, the ten digits, one separator for ``.`` and ``,``.
* Network (note §4.1 table, adaptation A1): seven convs [16, 32, 64, 64, 128, 128, 128] with the
  paper's pools (two 2x2, two height-only) and BN after conv5 and conv6, conv7 2x2 to height 1,
  a two-layer bidirectional LSTM of 128, a linear head to 12 - about 1.01 M parameters. RGB (A2).
* Decoding (note §4.4): prefix search over the per-frame distributions, best path as the control;
  the law's per-cell posteriors are the substitution marginals around the decoded string - for each
  digit position, ``p(l* with that digit replaced by d | x)`` for d in 0-9 by the forward recursion
  (Graves eqs. 5-8), normalised, and the separator after each digit by inserting or removing it
  (adaptation A4).
"""

from __future__ import annotations

import json
import math
import zlib
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import torch
from PIL import Image
from torch import nn

BLANK = 0
SEP = 11
N_CLASSES = 12
HEIGHT = 32
MIN_WIDTH = 100
MAX_WIDTH = 160


def encode(text: str) -> list[int] | None:
    """Digits -> 1..10, `.`/`,` -> SEP; spaces dropped; any other character -> None (filtered)."""
    out: list[int] = []
    for ch in text:
        if ch.isdigit():
            out.append(int(ch) + 1)
        elif ch in ".,":
            out.append(SEP)
        elif ch == " ":
            continue
        else:
            return None
    return out or None


def decode_tokens(tokens: list[int]) -> str:
    return "".join("." if t == SEP else str(t - 1) for t in tokens)


# MARK: - Input geometry


def to_input(strip: Image.Image) -> np.ndarray:
    """The strip at height 32, aspect kept, right-padded with its own edge column to MIN_WIDTH,
    capped at MAX_WIDTH; HWC uint8."""
    strip = strip.convert("RGB")
    w = max(1, round(strip.width * HEIGHT / strip.height))
    w = min(w, MAX_WIDTH)
    arr = np.asarray(strip.resize((w, HEIGHT), Image.BILINEAR))
    if w < MIN_WIDTH:
        arr = np.concatenate([arr, np.repeat(arr[:, -1:], MIN_WIDTH - w, axis=1)], axis=1)
    return arr


def batch(arrays: list[np.ndarray]) -> tuple[torch.Tensor, torch.Tensor]:
    """Right-pad each to the batch's max width with its own edge column; returns NCHW float and
    each sample's frame count T (width / 4 - 1)."""
    width = max(a.shape[1] for a in arrays)
    padded = [np.concatenate([a, np.repeat(a[:, -1:], width - a.shape[1], axis=1)], axis=1)
              if a.shape[1] < width else a for a in arrays]
    x = torch.from_numpy(np.stack(padded).transpose(0, 3, 1, 2).astype(np.float32) / 255.0)
    lengths = torch.tensor([frames(a.shape[1]) for a in arrays], dtype=torch.long)
    return x, lengths


def frames(width: int) -> int:
    """Frames the network emits for an input `width`: two 2x2 pools, then the 2x2 conv7."""
    return width // 4 - 1


# MARK: - Network


class CRNN(nn.Module):
    def __init__(self) -> None:
        super().__init__()

        def conv(cin: int, cout: int, k: int = 3, bn: bool = False) -> list[nn.Module]:
            layers: list[nn.Module] = [nn.Conv2d(cin, cout, k, padding=1 if k == 3 else 0)]
            if bn:
                layers.append(nn.BatchNorm2d(cout))
            layers.append(nn.ReLU(inplace=True))
            return layers

        self.cnn = nn.Sequential(
            *conv(3, 16), nn.MaxPool2d(2, 2),
            *conv(16, 32), nn.MaxPool2d(2, 2),
            *conv(32, 64),
            *conv(64, 64), nn.MaxPool2d((2, 1), (2, 1)),
            *conv(64, 128, bn=True),
            *conv(128, 128, bn=True), nn.MaxPool2d((2, 1), (2, 1)),
            *conv(128, 128, k=2),
        )
        self.rnn = nn.LSTM(128, 128, num_layers=2, bidirectional=True)
        self.head = nn.Linear(256, N_CLASSES)
        for m in self.modules():
            if isinstance(m, nn.Conv2d):
                nn.init.kaiming_normal_(m.weight, nonlinearity="relu")  # He init (Baek §4.1)
                nn.init.zeros_(m.bias)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """Logits [T, N, C]."""
        f = self.cnn(x)                       # [N, 128, 1, T]
        f = f.squeeze(2).permute(2, 0, 1)     # [T, N, 128]
        y, _ = self.rnn(f)
        return self.head(y)


# MARK: - CTC: the forward recursion (Graves eqs. 5-8), log space


def ctc_log_likelihood(log_probs: np.ndarray, label: list[int]) -> float:
    """ln p(label | x) for one sequence; `log_probs` [T, C] log-softmax."""
    t_len = log_probs.shape[0]
    ext = [BLANK]
    for token in label:
        ext += [token, BLANK]
    s_len = len(ext)
    if t_len == 0:
        return -math.inf
    neg = -math.inf
    alpha = np.full(s_len, neg)
    alpha[0] = log_probs[0, ext[0]]
    if s_len > 1:
        alpha[1] = log_probs[0, ext[1]]
    for t in range(1, t_len):
        prev = alpha
        alpha = np.full(s_len, neg)
        for s in range(s_len):
            a = prev[s]
            if s >= 1:
                a = np.logaddexp(a, prev[s - 1])
            # eq. 6's skip: from s-2 when the label at s is not blank and differs from s-2.
            if s >= 2 and ext[s] != BLANK and ext[s] != ext[s - 2]:
                a = np.logaddexp(a, prev[s - 2])
            alpha[s] = a + log_probs[t, ext[s]]
    return float(np.logaddexp(alpha[-1], alpha[-2]) if s_len > 1 else alpha[-1])


# MARK: - Decoding


def best_path(log_probs: np.ndarray) -> list[int]:
    out, prev = [], BLANK
    for c in log_probs.argmax(axis=1):
        if c != prev and c != BLANK:
            out.append(int(c))
        prev = c
    return out


def prefix_search(log_probs: np.ndarray, beam: int = 32) -> list[int]:
    """CTC prefix beam search (the tractable form of Graves §3.2's prefix search at our T <= 40):
    each prefix keeps its blank-ending and non-blank-ending path mass."""
    beams: dict[tuple, tuple[float, float]] = {(): (0.0, -math.inf)}
    for t in range(log_probs.shape[0]):
        lp = log_probs[t]
        nxt: dict[tuple, list[float]] = {}

        def add(prefix: tuple, pb: float, pnb: float) -> None:
            cur = nxt.setdefault(prefix, [-math.inf, -math.inf])
            cur[0] = float(np.logaddexp(cur[0], pb))
            cur[1] = float(np.logaddexp(cur[1], pnb))

        for prefix, (pb, pnb) in beams.items():
            total = np.logaddexp(pb, pnb)
            add(prefix, total + lp[BLANK], -math.inf)
            for c in range(1, N_CLASSES):
                ext = prefix + (c,)
                if prefix and prefix[-1] == c:
                    add(ext, -math.inf, pb + lp[c])       # a repeat needs a blank between
                    add(prefix, -math.inf, pnb + lp[c])   # the same symbol continues
                else:
                    add(ext, -math.inf, total + lp[c])
        ranked = sorted(nxt.items(), key=lambda kv: -np.logaddexp(*kv[1]))[:beam]
        beams = {k: (v[0], v[1]) for k, v in ranked}
    best = max(beams.items(), key=lambda kv: np.logaddexp(*kv[1]))
    return list(best[0])


@dataclass
class Posteriors:
    """Per digit position of the decoded string: the ten digits' log posteriors (the substitution
    marginal, normalised) and the probability that a separator follows it."""
    ranked: list[list[tuple[int, float]]]
    sep: list[float]


def posteriors(log_probs: np.ndarray, tokens: list[int]) -> Posteriors:
    digits = [i for i, t in enumerate(tokens) if t != SEP]
    ranked: list[list[tuple[int, float]]] = []
    sep: list[float] = []
    for i in digits:
        scores = []
        for d in range(10):
            variant = list(tokens)
            variant[i] = d + 1
            scores.append(ctc_log_likelihood(log_probs, variant))
        s = np.array(scores)
        z = np.logaddexp.reduce(s)
        ranked.append(sorted(((d, float(s[d] - z)) for d in range(10)), key=lambda p: -p[1]))
        with_sep = list(tokens)
        without = list(tokens)
        if i + 1 < len(tokens) and tokens[i + 1] == SEP:
            del without[i + 1]
        else:
            with_sep.insert(i + 1, SEP)
        a = ctc_log_likelihood(log_probs, with_sep)
        b = ctc_log_likelihood(log_probs, without)
        sep.append(float(1 / (1 + math.exp(min(50.0, b - a)))) if math.isfinite(a) else 0.0)
    return Posteriors(ranked=ranked, sep=sep)


def levenshtein(a: str, b: str) -> int:
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def group_of(source: str) -> str:
    """The split group of a real strip: its record or its still, so no fixture straddles."""
    return source.split("/")[0].split("#")[0]


def is_val_group(group: str) -> bool:
    return zlib.crc32(group.encode()) % 10 == 0


def load_real(export_dir: Path) -> list[dict]:
    """The re-exported TRAIN strips (`PumpTrainSliceExportTests`): text, strip path, source group."""
    out = []
    for manifest in ("train-slices.json", "train-videos.json"):
        path = export_dir / manifest
        if not path.exists():
            continue
        data = json.loads(path.read_text())
        for w in data.get("windows", []):
            tokens = encode(w.get("text", ""))
            if tokens is None:
                continue
            source = w.get("frame") or w.get("fixture") or ""
            out.append({"strip": str(export_dir / w["strip"]), "tokens": tokens,
                        "group": group_of(str(w.get("fixture", source))), "field": w.get("field")})
    return out

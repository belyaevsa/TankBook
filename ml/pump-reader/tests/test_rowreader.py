"""The PU.77 row reader's F1 checks (`agents/research/PU.77.md` §6.4): the hand-rolled CTC
forward recursion reproduces `nn.CTCLoss`; the substitution marginal ranks the true digit first on
a peaked posterior; decoding, encoding and the geometry are what the note fixes.
"""

from __future__ import annotations

import numpy as np
import torch
from PIL import Image

from pump_reader import rowreader as rr


def _random_case(rng: np.random.Generator) -> tuple[torch.Tensor, list[int], int]:
    t = int(rng.integers(12, 30))
    label = [int(v) for v in rng.integers(1, rr.N_CLASSES, size=int(rng.integers(1, 6)))]
    logits = torch.tensor(rng.normal(size=(t, 1, rr.N_CLASSES)), dtype=torch.float64)
    return logits.log_softmax(2), label, t


def test_forward_recursion_matches_ctc_loss() -> None:
    rng = np.random.default_rng(0)
    ctc = torch.nn.CTCLoss(blank=rr.BLANK, reduction="none")
    for _ in range(30):
        lp, label, t = _random_case(rng)
        ref = -ctc(lp, torch.tensor([label]), torch.tensor([t]), torch.tensor([len(label)])).item()
        assert abs(ref - rr.ctc_log_likelihood(lp[:, 0].numpy(), label)) < 1e-5


def _peaked(tokens: list[int], per_frame: int = 3) -> np.ndarray:
    """Frames that say each token (separated by blanks) with probability 0.9."""
    frames = []
    for tok in tokens:
        frames += [tok] * per_frame + [rr.BLANK]
    lp = np.full((len(frames), rr.N_CLASSES), np.log(0.1 / (rr.N_CLASSES - 1)))
    for t, tok in enumerate(frames):
        lp[t, tok] = np.log(0.9)
    return lp


def test_substitution_marginal_ranks_the_true_digit_first() -> None:
    tokens = rr.encode("12.38")
    lp = _peaked(tokens)
    assert rr.prefix_search(lp) == tokens and rr.best_path(lp) == tokens
    post = rr.posteriors(lp, tokens)
    assert [r[0][0] for r in post.ranked] == [1, 2, 3, 8]
    assert post.sep[1] > 0.9 and max(post.sep[0], post.sep[2], post.sep[3]) < 0.1


def test_encoding_and_geometry() -> None:
    assert rr.encode("12,38") == rr.encode("12.38") == [2, 3, rr.SEP, 4, 9]
    assert rr.encode("closed") is None and rr.encode("-00-") is None
    arr = rr.to_input(Image.new("RGB", (60, 96), "white"))
    assert arr.shape == (rr.HEIGHT, rr.MIN_WIDTH, 3)
    # CTC needs T >= 2U + 1 for the longest corpus string (8 tokens) at the minimum width.
    assert rr.frames(rr.MIN_WIDTH) >= 2 * 8 + 1

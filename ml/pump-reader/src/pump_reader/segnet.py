"""The oriented row segmenter (PU.76 spike, option B): PixelLink's pixel + link
formulation (Deng et al., AAAI 2018, arXiv:1801.01315) on a small backbone.

Model: a conv encoder to 1/32 and a top-down decoder with lateral skips back to
1/2 of the input (the paper's "2s" resolution - our median row is ~30 px tall at
512, so 1/4 would leave ~7 px of mask). Output: 1 pixel logit + 8 link logits
per cell (sigmoid; equivalent to the paper's two-way softmax per map).

Targets (paper §4.1): a pixel inside exactly one row quad is positive, inside two
(an overlap) is negative; a link from a positive pixel is positive when its
neighbour belongs to the same row. Loss (§4.2, eqs. 1-4): instance-balanced
pixel weights (every row gets the same total weight), online hard-negative
mining at r = 3 x the positives, link loss split into positive and negative
parts each normalised by its weight sum, total = lambda * pixel + link with
lambda = 2.

Decode (§3.3): pixel and link thresholds, union-find over positive pixels joined
by a positive link in either direction, one min-area rectangle per connected
component, small components dropped by the train split's 1st percentiles of
row short side and area (§3.4's rule, re-fitted). Confidence is the component's
mean pixel probability (the paper publishes none - adaptation B3).
"""

from __future__ import annotations

import cv2
import numpy as np
import torch
from torch import nn
from torch.nn import functional as F

# The 8 neighbours in PixelLink's order: (dy, dx).
NEIGHBOURS = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
LAMBDA = 2.0
OHEM_RATIO = 3


def _block(cin: int, cout: int, stride: int) -> nn.Sequential:
    return nn.Sequential(
        nn.Conv2d(cin, cout, 3, stride=stride, padding=1, bias=False), nn.BatchNorm2d(cout), nn.ReLU(inplace=True),
        nn.Conv2d(cout, cout, 3, padding=1, bias=False), nn.BatchNorm2d(cout), nn.ReLU(inplace=True),
    )


class SegNet(nn.Module):
    def __init__(self, width: int = 16):
        super().__init__()
        c = [width, width * 2, width * 4, width * 8, width * 12]
        self.enc = nn.ModuleList([_block(3, c[0], 2), _block(c[0], c[1], 2), _block(c[1], c[2], 2),
                                  _block(c[2], c[3], 2), _block(c[3], c[4], 2)])
        d = width * 4
        self.lateral = nn.ModuleList([nn.Conv2d(ch, d, 1) for ch in c])
        self.smooth = nn.Sequential(nn.Conv2d(d, d, 3, padding=1, bias=False), nn.BatchNorm2d(d), nn.ReLU(inplace=True))
        self.head = nn.Conv2d(d, 9, 1)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        feats = []
        for block in self.enc:
            x = block(x)
            feats.append(x)
        y = self.lateral[-1](feats[-1])
        for i in range(len(feats) - 2, -1, -1):
            y = F.interpolate(y, size=feats[i].shape[-2:], mode="bilinear", align_corners=False)
            y = y + self.lateral[i](feats[i])
        return self.head(self.smooth(y))  # [n, 9, H/2, W/2]


def targets(quads: list[np.ndarray], size: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Pixel label, link labels and instance-balanced pixel weights at `size` x
    `size` (the 1/2 output grid). `quads` are pixel quads on that grid."""
    ids = np.zeros((size, size), np.int32)
    count = np.zeros((size, size), np.int32)
    for i, q in enumerate(quads, start=1):
        m = np.zeros((size, size), np.uint8)
        cv2.fillPoly(m, [np.round(q).astype(np.int32)], 1)
        count += m
        ids[m > 0] = i
    ids[count != 1] = 0
    pixel = (ids > 0).astype(np.float32)
    links = np.zeros((8, size, size), np.float32)
    padded = np.pad(ids, 1)
    for k, (dy, dx) in enumerate(NEIGHBOURS):
        nb = padded[1 + dy:1 + dy + size, 1 + dx:1 + dx + size]
        links[k] = ((ids > 0) & (nb == ids)).astype(np.float32)
    weight = np.zeros((size, size), np.float32)
    n = ids.max()
    total = pixel.sum()
    if n > 0 and total > 0:
        per = total / n
        for i in range(1, n + 1):
            area = (ids == i).sum()
            if area:
                weight[ids == i] = per / area
    return pixel, links, weight


def loss(logits: torch.Tensor, pixel: torch.Tensor, links: torch.Tensor, weight: torch.Tensor) -> torch.Tensor:
    """PixelLink's loss for a batch: logits [n,9,h,w], pixel [n,h,w], links [n,8,h,w], weight [n,h,w]."""
    pix_logit = logits[:, 0]
    ce = F.binary_cross_entropy_with_logits(pix_logit, pixel, reduction="none")
    total = logits.new_zeros(())
    for b in range(logits.shape[0]):
        pos = pixel[b] > 0
        n_pos = int(pos.sum())
        neg_ce = ce[b][~pos]
        n_neg = min(neg_ce.numel(), max(OHEM_RATIO * n_pos, 10_000 if n_pos == 0 else 0))
        hard = torch.topk(neg_ce, n_neg).values if n_neg > 0 else neg_ce[:0]
        # Selected negatives weigh 1 (paper eq. 2's W for mined negatives).
        pix = ((ce[b][pos] * weight[b][pos]).sum() + hard.sum()) / max((1 + OHEM_RATIO) * n_pos, 1 if n_pos else n_neg)
        if n_pos:
            lk = F.binary_cross_entropy_with_logits(logits[b, 1:], links[b], reduction="none")
            w = weight[b].unsqueeze(0) * pos.unsqueeze(0)
            wp, wn = w * links[b], w * (1 - links[b])
            link = (lk * wp).sum() / wp.sum().clamp(min=1e-6) + (lk * wn).sum() / wn.sum().clamp(min=1e-6)
        else:
            link = logits.new_zeros(())
        total = total + LAMBDA * pix + link
    return total / logits.shape[0]


def decode(pixel_prob: np.ndarray, link_prob: np.ndarray, pixel_t: float, link_t: float,
           min_short: float, min_area: float, shape: str = "rect") -> list[tuple[np.ndarray, float]]:
    """Quads (4x2, output-grid pixels, TL TR BR BL in reading order) with a
    confidence, from one image's maps."""
    h, w = pixel_prob.shape
    pos = pixel_prob >= pixel_t
    parent = np.arange(h * w)

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    ys, xs = np.nonzero(pos)
    for k, (dy, dx) in enumerate(NEIGHBOURS):
        if (dy, dx) < (0, 0):
            continue  # each unordered pair once; the reverse link is read below
        rk = NEIGHBOURS.index((-dy, -dx))
        for y, x in zip(ys, xs):
            ny, nx = y + dy, x + dx
            if not (0 <= ny < h and 0 <= nx < w) or not pos[ny, nx]:
                continue
            if link_prob[k, y, x] >= link_t or link_prob[rk, ny, nx] >= link_t:
                a, b = find(y * w + x), find(ny * w + nx)
                if a != b:
                    parent[a] = b
    groups: dict[int, list[tuple[int, int]]] = {}
    for y, x in zip(ys, xs):
        groups.setdefault(find(y * w + x), []).append((x, y))
    out = []
    for pts in groups.values():
        arr = np.array(pts, np.float32)
        (cx, cy), (rw, rh), angle = cv2.minAreaRect(arr)
        # A pixel is a cell of width 1: grow the rectangle by one cell.
        rw, rh = rw + 1, rh + 1
        if min(rw, rh) < min_short or rw * rh < min_area:
            continue
        box = cv2.boxPoints(((cx, cy), (rw, rh), angle))
        quad = reading_order(box)
        if shape == "quad":
            quad = fit_quad(arr, quad)
        out.append((quad, float(pixel_prob[arr[:, 1].astype(int), arr[:, 0].astype(int)].mean())))
    return out


def fit_quad(points: np.ndarray, rect: np.ndarray) -> np.ndarray:
    """A quadrilateral over a component instead of its rectangle (adaptation B9:
    a hand quad follows the display's perspective, a trapezoid, which no
    rectangle reproduces). In the rectangle's frame, each of the four sides is a
    least-squares line through the component's boundary: the extreme across-
    coordinate per along-bin for the top and bottom, the extreme along-
    coordinate per across-bin for the ends; the corners are the lines'
    intersections, grown by half a cell outward. Falls back to `rect` when a
    side has too few bins to fit."""
    tl, tr, br, bl = rect
    d = tr - tl
    d = d / (np.linalg.norm(d) + 1e-9)
    n = np.array([-d[1], d[0]])
    if n @ (bl - tl) < 0:
        n = -n
    o = tl
    a = (points - o) @ d
    c = (points - o) @ n

    def side(key: np.ndarray, val: np.ndarray, pick) -> tuple[float, float] | None:
        bins: dict[int, float] = {}
        for k, v in zip(np.round(key).astype(int), val):
            bins[k] = v if k not in bins else pick(bins[k], v)
        if len(bins) < 3:
            return None
        ks = np.array(list(bins)); vs = np.array(list(bins.values()))
        # Drop the outer 10 % of bins at each end: the corners are rounded.
        lo, hi = np.percentile(ks, 10), np.percentile(ks, 90)
        keep = (ks >= lo) & (ks <= hi)
        if keep.sum() < 2:
            keep[:] = True
        slope, icpt = np.polyfit(ks[keep], vs[keep], 1)
        return float(slope), float(icpt)

    top = side(a, c, min)
    bottom = side(a, c, max)
    left = side(c, a, min)
    right = side(c, a, max)
    if None in (top, bottom, left, right):
        return rect

    def meet(h: tuple[float, float], v: tuple[float, float], dc: float, da: float) -> np.ndarray:
        # c = h0 * a + h1 and a = v0 * c + v1  ->  solve for (a, c).
        (h0, h1), (v0, v1) = h, v
        cc = (h0 * v1 + h1) / (1 - h0 * v0)
        aa = v0 * cc + v1
        return o + (aa + da) * d + (cc + dc) * n

    g = 0.5
    return np.array([meet(top, left, -g, -g), meet(top, right, -g, g),
                     meet(bottom, right, g, g), meet(bottom, left, g, -g)], np.float32)


def reading_order(box: np.ndarray) -> np.ndarray:
    """TL, TR, BR, BL for a row: the long side is the reading direction, taken
    left to right; within each end the upper corner comes first."""
    c = box.mean(axis=0)
    e0, e1 = box[1] - box[0], box[2] - box[1]
    d = e0 if np.linalg.norm(e0) >= np.linalg.norm(e1) else e1
    d = d / (np.linalg.norm(d) + 1e-9)
    if d[0] < 0:
        d = -d
    along = (box - c) @ d
    order = np.argsort(along)
    left, right = order[:2], order[2:]
    tl, bl = sorted(left, key=lambda k: box[k][1])
    tr, br = sorted(right, key=lambda k: box[k][1])
    return np.array([box[tl], box[tr], box[br], box[bl]], np.float32)

"""The PU.76 spike's segmenter pieces against oracles they must reproduce:
polygon IoU on shapes with a known answer, PixelLink targets on two stacked rows,
the decode recovering those rows from perfect maps (and merging them when the
link between them is on), and the gate's merge count.
"""

from __future__ import annotations

import numpy as np
import torch

from pump_reader import rotgate, segnet


def test_polygon_iou_known_answers() -> None:
    square = [(0.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 2.0)]
    shifted = [(1.0, 0.0), (3.0, 0.0), (3.0, 2.0), (1.0, 2.0)]
    assert abs(rotgate.iou(square, square) - 1.0) < 1e-9
    assert abs(rotgate.iou(square, shifted) - 1 / 3) < 1e-9  # overlap 2, union 6
    diamond = [(1.0, -1.0), (3.0, 1.0), (1.0, 3.0), (-1.0, 1.0)]
    assert abs(rotgate.intersection(square, diamond) - 4.0) < 1e-9  # the square sits inside
    assert rotgate.iou(square, [(5.0, 5.0), (6.0, 5.0), (6.0, 6.0), (5.0, 6.0)]) == 0.0


ROW_A = np.array([[20, 20], [200, 30], [198, 60], [18, 50]], float)
ROW_B = np.array([[20, 70], [200, 80], [198, 110], [18, 100]], float)


def test_targets_links_stay_inside_a_row() -> None:
    pixel, links, weight = segnet.targets([ROW_A, ROW_B], 256)
    assert pixel[40, 100] == 1 and pixel[90, 100] == 1 and pixel[65, 100] == 0
    # The down link from row A's bottom edge must not cross into row B.
    down = segnet.NEIGHBOURS.index((1, 0))
    ys = np.nonzero(pixel[:, 100])[0]
    bottom_a = max(y for y in ys if y < 65)
    assert links[down, bottom_a, 100] == 0 and links[down, bottom_a - 1, 100] == 1
    # Instance balance: both rows carry the same total weight.
    ids_a = np.zeros_like(pixel, bool)
    ids_a[:65] = pixel[:65] > 0
    assert abs(weight[ids_a].sum() - weight[(pixel > 0) & ~ids_a].sum()) < 1e-3


def test_decode_recovers_rows_and_merges_without_links() -> None:
    pixel, links, _ = segnet.targets([ROW_A, ROW_B], 256)
    rows = segnet.decode(pixel, links, 0.5, 0.5, 2, 10)
    assert len(rows) == 2
    for truth in (ROW_A, ROW_B):
        best = max(rotgate.iou([tuple(p) for p in truth], [tuple(p) for p in q]) for q, _ in rows)
        assert best > 0.85
    # Touching rows with every link on join into one component: the link head is what separates them.
    touching = [np.array([[20, 20], [200, 20], [200, 40], [20, 40]], float),
                np.array([[20, 41], [200, 41], [200, 60], [20, 60]], float)]
    pixel2, _, _ = segnet.targets(touching, 256)
    assert len(segnet.decode(pixel2, np.ones((8, 256, 256), np.float32), 0.5, 0.5, 2, 10)) == 1
    pixel3, links3, _ = segnet.targets(touching, 256)
    assert len(segnet.decode(pixel3, links3, 0.5, 0.5, 2, 10)) == 2


def test_gate_counts_a_merged_pair() -> None:
    a = [(0.0, 0.0), (10.0, 0.0), (10.0, 2.0), (0.0, 2.0)]
    b = [(0.0, 3.0), (10.0, 3.0), (10.0, 5.0), (0.0, 5.0)]
    both = [(0.0, 0.0), (10.0, 0.0), (10.0, 5.0), (0.0, 5.0)]
    s = rotgate.score({"x": [a, b]}, {"x": [both]})
    assert s.merged_photos == 1 and s.false_rows == 1 and s.hit50 == 0  # unmatched, so also a false row


def test_model_output_shape_and_loss_is_finite() -> None:
    model = segnet.SegNet(8)
    y = model(torch.zeros(1, 3, 128, 128))
    assert y.shape == (1, 9, 64, 64)
    pixel, links, weight = segnet.targets([ROW_A / 4], 64)
    loss = segnet.loss(y, torch.tensor(pixel)[None], torch.tensor(links)[None], torch.tensor(weight)[None])
    assert torch.isfinite(loss)

"""Score slicer: the scorer's slicing of a window produces one cell per glyph and
each cell's centre lands inside PU.1's rendered box (oracle: ``render_row``'s
boxes, which are true even under perspective).

A fake number row is rendered without augmentation so its boxes are axis-aligned;
the window quad is the tight bounding box of the glyph cells; slicing then must
recover one cell per glyph with centres inside the corresponding box.
"""

from __future__ import annotations

import numpy as np

from pump_reader.profiles import PROFILES
from pump_reader.row import render_row
from pump_reader.score import parse_cells, slice_cells


def test_slice_cells_match_rendered_boxes() -> None:
    rng = np.random.default_rng(0)
    text = "12.38"
    img, boxes = render_row(text, PROFILES["wayne"], rng, augment=False)

    cells_truth = parse_cells(text)
    n = len(cells_truth)
    assert n == len(boxes)

    x0, y0 = boxes[0].x, boxes[0].y
    x1, y1 = boxes[-1].x + boxes[-1].w, boxes[0].y + boxes[0].h
    quad = np.array([[x0, y0], [x1, y0], [x1, y1], [x0, y1]], dtype=np.float64)

    cells, centres = slice_cells(img, quad, n)
    assert len(cells) == n
    for (cx, cy), b in zip(centres, boxes):
        assert b.x <= cx <= b.x + b.w, f"centre x {cx} outside box [{b.x}, {b.x + b.w}]"
        assert b.y <= cy <= b.y + b.h, f"centre y {cy} outside box [{b.y}, {b.y + b.h}]"

"""Decision 10's gate restated for oriented boxes (PU.76 spike, note §5.6).

IoU is the convex-polygon IoU between a found quad and the HAND QUAD, in pixel
space on the upright image; matching is `measure.swift`'s (each truth row takes
the best still-unmatched found box; a match needs IoU >= 0.5); false rows are
found boxes left unmatched. The primaries are median IoU and recall @ IoU 0.7,
with false rows per photo beside them; recall @ 0.5 is reported and never
decides. An upright box is a quad too, so the shipped detector and a candidate
are scored in one metric.

``merged`` (falsifier F4): a found quad that covers at least half of two or more
truth rows - stacked rows joined into one instance.
"""

from __future__ import annotations

import statistics
from dataclasses import dataclass, field

Point = tuple[float, float]


def _area(poly: list[Point]) -> float:
    s = 0.0
    for i in range(len(poly)):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % len(poly)]
        s += x0 * y1 - x1 * y0
    return abs(s) / 2


def _ccw(poly: list[Point]) -> list[Point]:
    s = sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
            for i in range(len(poly)))
    return poly if s >= 0 else poly[::-1]


def _clip(subject: list[Point], clipper: list[Point]) -> list[Point]:
    """Sutherland-Hodgman: `subject` clipped by the convex, counter-clockwise `clipper`."""
    out = subject
    for i in range(len(clipper)):
        a, b = clipper[i], clipper[(i + 1) % len(clipper)]
        inp, out = out, []
        if not inp:
            break

        def inside(p: Point) -> bool:
            return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= 0

        def cross(p: Point, q: Point) -> Point:
            dx1, dy1 = q[0] - p[0], q[1] - p[1]
            dx2, dy2 = b[0] - a[0], b[1] - a[1]
            den = dx1 * dy2 - dy1 * dx2
            if den == 0:
                return q
            t = ((a[0] - p[0]) * dy2 - (a[1] - p[1]) * dx2) / den
            return (p[0] + t * dx1, p[1] + t * dy1)

        for j in range(len(inp)):
            p, q = inp[j], inp[(j + 1) % len(inp)]
            if inside(q):
                if not inside(p):
                    out.append(cross(p, q))
                out.append(q)
            elif inside(p):
                out.append(cross(p, q))
    return out


def intersection(a: list[Point], b: list[Point]) -> float:
    return _area(_clip(_ccw(a), _ccw(b)))


def iou(a: list[Point], b: list[Point]) -> float:
    inter = intersection(a, b)
    union = _area(a) + _area(b) - inter
    return inter / union if union > 0 else 0.0


@dataclass
class GateScore:
    rows: int = 0
    photos: int = 0
    hit50: int = 0
    hit70: int = 0
    false_rows: int = 0
    photos_any: int = 0
    photos_all: int = 0
    merged_photos: int = 0
    ious: list[float] = field(default_factory=list)
    per_photo: list[str] = field(default_factory=list)

    @property
    def median_iou(self) -> float:
        return statistics.median(self.ious) if self.ious else 0.0

    def line(self, label: str) -> str:
        n = max(self.rows, 1)
        return (f"{label}: median IoU {self.median_iou:.3f} | recall@0.7 {self.hit70}/{self.rows} = "
                f"{self.hit70 / n:.3f} | false rows/photo {self.false_rows / max(self.photos, 1):.3f} "
                f"({self.false_rows} over {self.photos}) | recall@0.5 {self.hit50}/{self.rows} = "
                f"{self.hit50 / n:.3f} (never decides) | photos any row {self.photos_any}, all rows "
                f"{self.photos_all} | photos with a merged pair {self.merged_photos}")


def score(truth: dict[str, list[list[Point]]], found: dict[str, list[list[Point]]],
          score_: GateScore | None = None) -> GateScore:
    """`truth` and `found` map an image name to pixel-space quads; `found` must
    already be filtered to the operating confidence."""
    s = score_ or GateScore()
    for name, rows in truth.items():
        boxes = found.get(name, [])
        s.photos += 1
        matched: set[int] = set()
        hits = 0
        for t in rows:
            s.rows += 1
            best, best_i = 0.0, -1
            for i, f in enumerate(boxes):
                if i in matched:
                    continue
                v = iou(t, f)
                if v > best:
                    best, best_i = v, i
            s.ious.append(best)
            if best >= 0.5:
                s.hit50 += 1
                matched.add(best_i)
                hits += 1
            if best >= 0.7:
                s.hit70 += 1
        s.false_rows += len(boxes) - len(matched)
        s.photos_any += hits > 0
        s.photos_all += hits == len(rows)
        merged = any(sum(intersection(t, f) >= 0.5 * _area(t) for t in rows if _area(t) > 0) >= 2
                     for f in boxes)
        s.merged_photos += merged
        s.per_photo.append(f"{name[:40]}: truth {len(rows)}, found {len(boxes)}, matched {hits}"
                           + (" MERGED" if merged else ""))
    return s

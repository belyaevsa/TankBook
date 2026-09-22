#!/usr/bin/env python3
"""Cross-check the pump number-window annotations against the corpus ground truth.

`Spike/ReceiptSpike/fixtures/pump/windows.json` names, for every fixture in
`expected.csv`, the quadrilateral of each number window and the string the
display shows. This script is what keeps the two files from disagreeing:

  * every fixture in expected.csv has an entry, and every entry names a fixture;
  * each `total` / `liters` / `unitPrice` window's string equals the CSV cell
    once display notation is normalised (comma decimal, zero padding, a dropped
    trailing zero on a truncated total). A blank CSV cell is unscored and not
    checked; an entry marked `pendingWindows` (still in, windows not drawn) is
    skipped until the flag goes; an entry's `notOnDisplay` names a CSV field the display does not
    show, and `csvDisagrees` names one where the display and the CSV differ on
    purpose, with the reason - both are read as declared exceptions;
  * liters x unitPrice ~ total within the precision the display shows;
  * a `board` window's string is price-shaped (digits with at most one
    separator, or the `-00-` idle marker) or empty - a board cell has no CSV
    truth, so only the shape can be checked;
  * every quad is four points inside [0, 1].

`--check` exits 1 on any disagreement, which is how CI keeps the annotations
honest; without it the script prints the summary and exits 0.
"""
from __future__ import annotations

import csv
import json
import re
import sys
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
FIX = ROOT / "Spike" / "ReceiptSpike" / "fixtures" / "pump"
FIELDS = ("total", "liters", "unitPrice")
BOARD_PRICE = re.compile(r"^[0-9]+(?:[.,][0-9]+)?$")
BOARD_IDLE = re.compile(r"^-[0-9]+-$")


def board_problem(text: str) -> str | None:
    """A `board` window's text is a price-shaped number (digits with at most
    one separator) or empty - the shape the display shows, since a board cell
    has no CSV truth to compare against. `-00-` is the idle/closed marker the
    Wayne heads show (`pump-263`)."""
    t = text.strip()
    if not t or BOARD_PRICE.match(t) or BOARD_IDLE.match(t):
        return None
    return f"board text {text!r} is not a price-shaped number"


def normalise(text: str) -> Decimal | None:
    """`0020,15` -> 20.15; `3765,7` -> 3765.7; `1789` (no point shown) -> 1789."""
    t = text.strip().replace(",", ".").replace(" ", "")
    if not t:
        return None
    return Decimal(t)


def matches(shown: Decimal, truth: Decimal) -> bool:
    if shown == truth:
        return True
    # A display without a decimal point shows a price like 1.789 as `1789`; a
    # truncated total shows 3765.65 as `3765,7` (rounded to one place).
    for scale in (10, 100, 1000):
        if shown == truth * scale:
            return True
    if shown.as_tuple().exponent > truth.as_tuple().exponent:
        return abs(shown - truth) < Decimal("0.11")
    return False


def quad_iou(a, b):
    """Axis-aligned overlap of two quads' bounding boxes over their union."""
    ax0, ax1 = min(p[0] for p in a), max(p[0] for p in a); ay0, ay1 = min(p[1] for p in a), max(p[1] for p in a)
    bx0, bx1 = min(p[0] for p in b), max(p[0] for p in b); by0, by1 = min(p[1] for p in b), max(p[1] for p in b)
    iw, ih = max(0, min(ax1, bx1) - max(ax0, bx0)), max(0, min(ay1, by1) - max(ay0, by0))
    inter = iw * ih; union = (ax1 - ax0) * (ay1 - ay0) + (bx1 - bx0) * (by1 - by0) - inter
    return inter / union if union > 0 else 0.0


def main() -> int:
    check = "--check" in sys.argv
    problems: list[str] = []
    ann = json.loads((FIX / "windows.json").read_text())
    rows = {r["filename"]: r for r in csv.DictReader((FIX / "expected.csv").open())}
    for name in rows:
        if name not in ann:
            problems.append(f"{name}: no annotation")
    for name in ann:
        if name.startswith("_"):
            continue
        if name not in rows:
            problems.append(f"{name}: annotated but not in expected.csv")
    windows = 0
    for name, entry in ann.items():
        row = rows.get(name)
        if row is None:
            continue
        if entry.get("pendingWindows"):
            # The still is in the corpus, its truth is in expected.csv, and its
            # windows are not all drawn yet (none, or the reader's auto-placed
            # ones missing an asserted cell): the comparison waits for the owner.
            continue
        not_on_display = set(entry.get("notOnDisplay", ()))
        csv_disagrees = entry.get("csvDisagrees", {})
        # A "not a window" region: a quad in [0,1] that overlaps no window - a
        # negative over a window is a contradiction, not a judgement.
        for n in entry.get("negatives", []):
            q = n.get("quad", [])
            if len(q) != 4 or any(not (0 <= x <= 1 and 0 <= y <= 1) for x, y in q):
                problems.append(f"{name}: bad negative quad")
                continue
            for w in entry["windows"]:
                if quad_iou(q, w["quad"]) > 0.5:
                    problems.append(f"{name}: a negative covers the {w['field']} window")
        byfield = {}
        for w in entry["windows"]:
            windows += 1
            q = w["quad"]
            if len(q) != 4 or any(not (0 <= x <= 1 and 0 <= y <= 1) for x, y in q):
                problems.append(f"{name}: bad quad on {w['field']}")
            if w["field"] in FIELDS:
                if w["field"] in byfield:
                    problems.append(f"{name}: two {w['field']} windows")
                byfield[w["field"]] = w["text"]
            elif w["field"] == "board":
                problem = board_problem(w.get("text", ""))
                if problem:
                    problems.append(f"{name}: {problem}")
        for f in FIELDS:
            truth = row[f].strip()
            shown = byfield.get(f)
            if shown is None:
                if truth and f not in not_on_display:
                    problems.append(f"{name}: {f} in expected.csv but no window")
                continue
            if not truth:
                # A blank cell is UNSCORED, not unreadable: the README leaves a
                # cell blank when the receipt and the photo disagree on a digit.
                continue
            if not shown.strip():
                problems.append(f"{name}: {f} window is blank but expected.csv says {truth}")
                continue
            if f in csv_disagrees:
                continue
            if not matches(normalise(shown), Decimal(truth)):
                problems.append(f"{name}: {f} window {shown!r} != expected {truth}")
        t, l, p = (row[f].strip() for f in FIELDS)
        if t and l and p:
            prod = Decimal(l) * Decimal(p)
            tol = Decimal("0.05") * max(1, len(t.split(".")[0]) // 3)
            if abs(prod - Decimal(t)) > max(tol, Decimal(t) * Decimal("0.005")):
                problems.append(f"{name}: {l} x {p} = {prod} vs total {t}")
    if check:
        # SQLite-first (product owner, 2026-09-21): the JSON is a dump of
        # corpus.sqlite, so a file that no longer matches the database is stale.
        import corpus_db  # noqa: PLC0415
        try:
            problems.extend(corpus_db.check())
        except Exception as exc:  # noqa: BLE001
            problems.append(f"corpus.sqlite: cannot check the dump ({exc}); run scripts/corpus_db.py import")
    print(f"{sum(1 for k in ann if not k.startswith(chr(95)))} fixtures, {windows} windows, {len(problems)} problems")
    for p in problems:
        print("  " + p)
    return 1 if (check and problems) else 0


if __name__ == "__main__":
    sys.exit(main())

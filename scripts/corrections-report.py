#!/usr/bin/env python3
"""What the operator corrected in the annotator, and what it says about the tools.

    scripts/corrections-report.py            # the whole ledger
    scripts/corrections-report.py --since 2026-09-21

Reads `Spike/ReceiptSpike/fixtures/pump-live/corrections.jsonl` (one line per
field the operator changed against a proposal - written by tools/pump-annotate)
and prints: the tracker's quad error as an IoU histogram per record and per make
(a low-IoU record needs anchors, or the tracker has a bezel problem on that head);
the reader's pre-fill accuracy per build and per field, with the corrections split
into "mark or leading zero only" (a slicer miss) and "digits differ" (a classifier
miss); and the list of frames corrected - the hard examples the next training
export should weight.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEDGER = ROOT / "Spike" / "ReceiptSpike" / "fixtures" / "pump-live" / "corrections.jsonl"
FRAMES = LEDGER.parent / "frames"


def make_of(record: str) -> str:
    """The still's make for a Live record, from its tracked file; a video's make from its name."""
    tracked = FRAMES / record / "windows.json"
    if tracked.exists():
        still = json.loads(tracked.read_text()).get("_still", "")
        parts = still.split("-")
        return parts[2] if len(parts) > 2 else "?"
    parts = record.split("-")
    return parts[2] if len(parts) > 2 else "?"


def digits_only(text: str) -> str:
    return re.sub(r"[^0-9]", "", text).lstrip("0")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--since", default="")
    args = parser.parse_args()
    if not LEDGER.exists():
        print("no corrections yet")
        return 0
    rows = [json.loads(line) for line in LEDGER.read_text().splitlines() if line.strip()]
    rows = [r for r in rows if r["at"] >= args.since]
    print(f"{len(rows)} corrections" + (f" since {args.since}" if args.since else ""))

    quads = [r for r in rows if r["kind"] == "quad" and r.get("proposedBy") == "tracker"]
    if quads:
        print(f"\nTracker: {len(quads)} quads corrected")
        bins = Counter(("<0.5" if r["iou"] < 0.5 else "0.5-0.7" if r["iou"] < 0.7 else "0.7-0.9" if r["iou"] < 0.9 else ">=0.9") for r in quads)
        print("  IoU of the tracked quad against the hand-placed one:", dict(sorted(bins.items())))
        per_record: dict[str, list[float]] = defaultdict(list)
        for r in quads:
            per_record[r["record"]].append(r["iou"])
        worst = sorted(per_record.items(), key=lambda kv: sum(kv[1]) / len(kv[1]))[:8]
        print("  worst records (mean IoU, corrections):", [(k, round(sum(v) / len(v), 2), len(v)) for k, v in worst])
        per_make: dict[str, list[float]] = defaultdict(list)
        for r in quads:
            per_make[make_of(r["record"])].append(r["iou"])
        print("  by make:", {k: (round(sum(v) / len(v), 2), len(v)) for k, v in sorted(per_make.items())})

    texts = [r for r in rows if r["kind"] == "text" and r.get("proposedBy") == "reader"]
    if texts:
        print(f"\nReader pre-fills corrected: {len(texts)}")
        by_build: dict[str, Counter] = defaultdict(Counter)
        for r in texts:
            same_digits = digits_only(str(r["proposed"])) == digits_only(str(r["final"]))
            by_build[r.get("build", "?")]["mark or leading zero only (slicer)" if same_digits else "digits differ (classifier or count)"] += 1
            by_build[r.get("build", "?")][f"field {r['field']}"] += 1
        for build, counts in sorted(by_build.items()):
            print(f"  build {build}: {dict(counts)}")
        hard = sorted({(r.get("video") or r.get("still") or r.get("record"), r.get("frame", "")) for r in texts})
        print(f"  hard examples ({len(hard)} frames/stills):", hard[:20], "..." if len(hard) > 20 else "")

    tracking = Counter(r["final"] for r in rows if r["kind"] == "tracking")
    if tracking:
        print("\nTracking verdicts:", dict(tracking))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""The beta's scan-outcome readout: how often each kind of pre-filled pump field
was kept, edited or cleared on real fills (docs/CONFIG.md -> the `scanOutcome`
experiment; ScanOutcome in TankbookCore).

Reads the debug cases already downloaded by the debug-case skill
(`~/.cache/tankbook/cases/<id>/`, each holding `scan-N-record.json` and, since
the experiment shipped, `scan-N-outcome.json`) and prints one table: pre-fill
kind by action, then how the entries ended, then the `scanShadow` experiment's
tallies from the records: whether the Vision route closed where the shipped
read did, and how often the printed currency disagreed with the reader's. A
scan is counted once even when it appears in several cases (keyed by its
capture time).

Usage: scripts/scan-outcomes.py [cases-dir]      # default ~/.cache/tankbook/cases
       scripts/scan-outcomes.py --list            # also list every scan's fields

Nothing here leaves the machine; the numbers are counts, never a value.
"""
import collections
import json
import sys
from pathlib import Path

KINDS = ["closed", "warned", "cautioned", "rules", "empty"]
ACTIONS = ["kept", "edited", "cleared", "added", "untouched"]


def scans(root: Path):
    seen = set()
    for case in sorted(p for p in root.iterdir() if p.is_dir()):
        for outcome in sorted(case.glob("scan-*-outcome.json")):
            record_path = outcome.with_name(outcome.name.replace("-outcome.json", "-record.json"))
            try:
                body = json.loads(outcome.read_text())
                record = json.loads(record_path.read_text()) if record_path.exists() else {}
            except (OSError, json.JSONDecodeError):
                continue
            key = record.get("capturedAt") or f"{case.name}/{outcome.name}"
            if key in seen:
                continue
            seen.add(key)
            yield case.name, outcome.name.split("-outcome")[0], body, record


def shadow_tally(record: dict, body: dict, tally: collections.Counter) -> None:
    shadow = record.get("shadow")
    if not shadow:
        return
    tally["with shadow"] += 1
    kinds = {e.get("prefill") for e in (body.get("fields") or {}).values()}
    shipped = "closed" if kinds & {"closed", "cautioned"} else "warned" if "warned" in kinds else "no read"
    vision = "vision closes" if (shadow.get("vision") or {}).get("closes") else "vision does not close"
    tally[(shipped, vision)] += 1
    if all(e.get("action") == "kept" for e in (body.get("fields") or {}).values() if e.get("prefill") != "empty"):
        tally[(shipped, vision, "all kept")] += 1
    currency = shadow.get("currency") or {}
    display, reader = currency.get("display"), currency.get("reader")
    if display:
        tally["display prints a currency"] += 1
        tally["display != reader" if display != reader else "display == reader"] += 1


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    root = Path(args[0]).expanduser() if args else Path("~/.cache/tankbook/cases").expanduser()
    if not root.is_dir():
        print(f"no cases under {root} - fetch them with the debug-case skill first", file=sys.stderr)
        return 1
    table = collections.Counter()
    results = collections.Counter()
    shadow = collections.Counter()
    count = 0
    for case, scan, body, record in scans(root):
        count += 1
        results[body.get("result", "?")] += 1
        shadow_tally(record, body, shadow)
        for field, entry in (body.get("fields") or {}).items():
            if "action" in entry:
                table[(entry.get("prefill", "empty"), entry["action"])] += 1
        if "--list" in sys.argv:
            fields = " ".join(f"{f}={e.get('prefill')}/{e.get('action', '-')}"
                              for f, e in sorted((body.get("fields") or {}).items()))
            print(f"{case} {scan} {body.get('result')}: {fields}")
    if count == 0:
        print(f"no scan outcomes under {root}")
        return 0
    print(f"{count} scans with an outcome: " + ", ".join(f"{k} {v}" for k, v in sorted(results.items())))
    print()
    print("| pre-fill | " + " | ".join(ACTIONS) + " |")
    print("|---|" + "---|" * len(ACTIONS))
    for kind in KINDS:
        row = [table[(kind, a)] for a in ACTIONS]
        if any(row):
            print(f"| {kind} | " + " | ".join(str(n) for n in row) + " |")
    if shadow["with shadow"]:
        print()
        print(f"scanShadow on {shadow['with shadow']} scans (all kept = every pre-filled field kept):")
        print("| shipped | vision closes | all kept | vision does not close | all kept |")
        print("|---|---|---|---|---|")
        for shipped in ["closed", "warned", "no read"]:
            cells = [shadow[(shipped, v)] for v in ("vision closes", "vision does not close")]
            if any(cells):
                kept = [shadow[(shipped, v, "all kept")] for v in ("vision closes", "vision does not close")]
                print(f"| {shipped} | {cells[0]} | {kept[0]} | {cells[1]} | {kept[1]} |")
        print(f"display prints a currency on {shadow['display prints a currency']}: "
              f"same as the reader's {shadow['display == reader']}, different {shadow['display != reader']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

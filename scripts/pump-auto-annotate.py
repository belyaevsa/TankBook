#!/usr/bin/env python3
"""Auto-annotate every `pendingWindows` still through the app's live path.

The same call the annotator's `A` makes: `pump-read` with no windows runs the
detector -> verifier -> row assignment, and every row it assigns a field to
becomes a window with the CSV's text (a board row an empty one), `placedBy:
auto`, unreviewed. A still where an asserted cell got no row keeps
`pendingWindows` for the owner's hand. Run after `corpus-intake` has written the
truth rows; then `corpus_db.py import` and `dump`.
"""
import collections
import csv
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIX = ROOT / "Spike" / "ReceiptSpike" / "fixtures"
TOOL = ROOT / "ios" / ".build" / "opt" / "debug" / "pump-read"
if not TOOL.exists():
    TOOL = ROOT / "ios" / ".build" / "debug" / "pump-read"


def main() -> int:
    path = FIX / "pump" / "windows.json"
    ann = json.loads(path.read_text(), object_pairs_hook=collections.OrderedDict)
    rows = {r["filename"]: r for r in csv.DictReader(open(FIX / "pump" / "expected.csv"))}
    done, pending = [], []
    for name, entry in ann.items():
        if not isinstance(entry, dict) or not entry.get("pendingWindows") or entry.get("windows"):
            continue
        row = rows.get(name)
        if row is None:
            continue
        request = {"rotationCW": entry.get("rotationCW", 0), "currency": row.get("currency") or None, "windows": None}
        r = subprocess.run([str(TOOL), str(FIX / "pump" / name), "--classifier", str(ROOT / "ios/App/Resources/PumpSegments.mlpackage"),
                            "--detector", str(ROOT / "ios/App/Resources/DigitRows.mlmodel")],
                           input=json.dumps(request), capture_output=True, text=True, timeout=300)
        if r.returncode or not r.stdout.strip():
            pending.append((name, "read failed"))
            continue
        res = json.loads(r.stdout)
        have, wins = set(), []
        for rr in res.get("rows", []):
            field = rr.get("field")
            if field not in ("total", "liters", "unitPrice", "board") or (field != "board" and field in have):
                continue
            text = (row.get(field) or "") if field != "board" else ""
            wins.append(collections.OrderedDict([("field", field), ("text", text),
                                                 ("quad", [[round(x, 4), round(y, 4)] for x, y in rr["quad"]]),
                                                 ("placedBy", "auto")]))
            have.add(field)
        if not wins:
            pending.append((name, "no rows"))
            continue
        entry["windows"] = wins
        entry["reviewed"] = False
        missing = [f for f in ("liters", "unitPrice", "total") if row[f].strip() and f not in have]
        if missing:
            pending.append((name, "no row for " + ", ".join(missing)))
        else:
            entry.pop("pendingWindows", None)
        done.append(name)
        print(f"{name[:48]:48} {[w['field'][0] for w in wins]} committed {res.get('committed')}", flush=True)
    path.write_text(json.dumps(ann, indent=1, ensure_ascii=False) + "\n")
    print(f"annotated {len(done)}; still pending: " + (", ".join(f"{n[:20]} ({why})" for n, why in pending) or "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Diff two pump live-arm ledgers: which stills flipped, and to which reason.

Usage: scripts/pump-live-diff.py BEFORE.json AFTER.json

A ledger is what `PumpReaderPipelineTests.livePath` writes
(`ios/.build/pump-reader-out/live-ledger.json`, or `PUMP_LIVE_LEDGER`): per
still, per field, the outcome (`right`, `wrong`, `abstained`, `unscored`), the
value, and the law's reason when it abstained. The live gate is one number, so a
change that trades five gains for five losses reads as "no change"; this names
the ten stills and the stage each one moved at (ml/pump-reader/REPORT.md ->
round protocol).

Every changed field is one of:
  gain        abstained -> right
  WRONG       now wrong (a new wrong value, or a right one turned wrong)
  law flip    right -> abstained on a law reason (nothing closed, ambiguous, price)
  read flip   right -> abstained on a read reason (no candidate, impossible cells)
  assign flip right -> abstained because no window got the role
  locate flip right -> abstained because the photo was not taken for a display
  loss        right -> abstained with no reason recorded
  reason      abstained in both, the reason moved
Exit status is 0; the report is the output.
"""

from __future__ import annotations

import json
import sys
from collections import Counter

LAW = {"nothingClosed", "ambiguous", "boardFoundNoPrice", "priceUnvalidated", "priceDisagrees",
       "priceOutOfBand", "currencyUnmeasured"}
READ = {"cellUnknown", "cellCountImpossible"}
ASSIGN = {"noLitersWindow", "noTotalWindow", "litersAllZero"}
# Recorded by the ledger, not the law: the app's display decision refused the
# photo before anything was read.
LOCATE = {"notADisplay"}


def load(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def classify(before: dict | None, after: dict | None) -> str | None:
    """The kind of change one field made, or None when it did not change."""
    b = before or {"outcome": "unscored"}
    a = after or {"outcome": "unscored"}
    if "unscored" in (b["outcome"], a["outcome"]):
        return None
    if a["outcome"] == "wrong" and (b["outcome"] != "wrong" or b.get("got") != a.get("got")):
        return "WRONG"
    if b["outcome"] == a["outcome"]:
        if a["outcome"] == "abstained" and b.get("reason") != a.get("reason"):
            return "reason"
        return None
    if a["outcome"] == "right":
        return "gain"
    if b["outcome"] == "right" and a["outcome"] == "abstained":
        reason = a.get("reason")
        if reason in LAW:
            return "law flip"
        if reason in READ:
            return "read flip"
        if reason in ASSIGN:
            return "assign flip"
        if reason in LOCATE:
            return "locate flip"
        return "loss"
    if b["outcome"] == "wrong" and a["outcome"] == "abstained":
        return "wrong -> abstained"
    return None


def with_reason(still: dict, field: str) -> dict | None:
    """The field, carrying the still's own refusal reason when the field has
    none - a photo that commits nothing records why once, on the photo."""
    entry = still.get("fields", {}).get(field)
    if entry is None or entry.get("reason") or entry.get("outcome") != "abstained":
        return entry
    return {**entry, "reason": still.get("reason")}


def shown(entry: dict | None) -> object:
    """A committed field's value, rounded as a display prints it; otherwise its reason."""
    if not entry:
        return None
    if entry.get("outcome") in ("right", "wrong") and entry.get("got") is not None:
        return round(entry["got"], 3)
    return entry.get("reason")


def diff(before: dict, after: dict) -> list[dict]:
    """One row per changed field, ordered by still then field."""
    b_stills = {s["name"]: s for s in before.get("stills", [])}
    a_stills = {s["name"]: s for s in after.get("stills", [])}
    rows = []
    for name in sorted(set(b_stills) | set(a_stills)):
        bs, as_ = b_stills.get(name, {}), a_stills.get(name, {})
        fields = set(bs.get("fields", {})) | set(as_.get("fields", {}))
        for field in sorted(fields):
            bf, af = with_reason(bs, field), with_reason(as_, field)
            kind = classify(bf, af)
            if kind is None:
                continue
            rows.append({"still": name, "field": field, "kind": kind,
                         "before": shown(bf), "after": shown(af),
                         "want": (af or bf or {}).get("want"),
                         "head": as_.get("head") or bs.get("head")})
    return rows


def report(before: dict, after: dict) -> str:
    rows = diff(before, after)
    bt, at = before.get("totals", {}), after.get("totals", {})
    lines = [f"before {before.get('detector') or 'shipped'}: committed {bt.get('committed')}, "
             f"correct {bt.get('committedCorrect')} of {bt.get('numericTotal')}",
             f"after  {after.get('detector') or 'shipped'}: committed {at.get('committed')}, "
             f"correct {at.get('committedCorrect')} of {at.get('numericTotal')}"]
    counts = Counter(r["kind"] for r in rows)
    lines.append("changed fields: " + (", ".join(f"{k} {v}" for k, v in sorted(counts.items())) or "none"))
    stills = sorted({r["still"] for r in rows})
    lines.append(f"stills that changed: {len(stills)}")
    for r in rows:
        lines.append(f"  {r['kind']:<12} {r['still'][:60]:<60} {r['field']:<9} "
                     f"{r['before']} -> {r['after']} (want {r['want']})")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    print(report(load(argv[1]), load(argv[2])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

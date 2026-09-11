#!/usr/bin/env python3
"""Every task belongs to a scenario, and a scenario is reviewed when its tasks are done.

The rule (2026-09-10, product owner): a task without a parent scenario has no
context - you cannot tell what it is FOR, and you cannot tell when the story it
belongs to is finished. So every row in docs/TASKS.md carries the journey it
serves, and this script is what makes that checkable rather than remembered.

The tag is the convention the PJ rows already used: the journey id in
parentheses somewhere in the row's first cell - `(J7 "app proposes the next
reminder")`. A row that genuinely serves no user journey says so explicitly with
`no-scenario:` and a reason; infrastructure is allowed, silence is not.

Usage: python3 scripts/scenario-index.py [--check]
  (no flag) prints the scenario map: rows per scenario, and which scenarios are
            READY FOR REVIEW because every row naming them is closed.
  --check   exits 1 when an OPEN row names no scenario, for a pre-commit gate.
            Closed rows are not policed - the backlog is decades of history and
            the rule earns its keep going forward, not retroactively.
"""
import re
import sys
from pathlib import Path

DOCS = Path(__file__).resolve().parent.parent / "docs"
OPEN_FILE = DOCS / "TASKS.md"
DONE_FILE = DOCS / "TASKS-DONE.md"
JOURNEYS = DOCS / "JOURNEYS.md"

# The id cell may carry a version marker after the id: `RV.118 **[v1.1]**`.
ROW = re.compile(r"^\|\s*\*\*\[(x|~|!|cut| )\]\*\*\s*([A-Z]+\.[0-9]+[a-z]?)\b([^|]*)\|\s*(.*)$")
# A row deferred past v1 does not hold a v1 story open; the review treats it as N/A.
DEFERRED = re.compile(r"\[(v1\.[0-9x]+|v2)\]")
SCENARIO = re.compile(r"\b(J[0-9]+[a-d]?|F[0-9]+[ab]?)\b")
NO_SCENARIO = re.compile(r"no-scenario:\s*(\S.*?)(?:\||$)")
HEADING = re.compile(r"^###\s+(J[0-9]+[a-d]?|F[0-9]+[ab]?)\s*[·.]?\s*(.*)$")


def journeys() -> dict[str, str]:
    """The scenarios JOURNEYS.md defines, id -> title."""
    found = {}
    for line in JOURNEYS.read_text(encoding="utf-8").split("\n"):
        match = HEADING.match(line)
        if match:
            found[match.group(1)] = re.sub(r"\*\*|\*", "", match.group(2)).strip()
    return found


def rows():
    """(id, status, scenarios, reason, where) for every task row in both files."""
    for path in (OPEN_FILE, DONE_FILE):
        for line in path.read_text(encoding="utf-8").split("\n"):
            match = ROW.match(line)
            if not match:
                continue
            status, rid, idtail, body = match.groups()
            cell = body.split(" | ")[0]
            reason = NO_SCENARIO.search(cell)
            # Deferred only when the marker is on the id or leads the row's own
            # text - a row that merely MENTIONS a v1.1 row is still v1 work.
            # The marker may follow the scenario link: `(J3 ...) **[v1.x]** **gap** ...`
            lead = cell.lstrip()[:120]
            deferred = (bool(DEFERRED.search(idtail))
                        or bool(re.match(r"^(\([^)]*\)\s*)?\*\*\[v", lead))
                        or rid.startswith("AG."))
            yield (rid, status, sorted(set(SCENARIO.findall(cell))),
                   reason.group(1).strip() if reason else None, path.name, deferred)


def main() -> int:
    check = "--check" in sys.argv
    defined = journeys()
    all_rows = list(rows())
    unattached = [r for r in all_rows if r[1] in " !" and not r[2] and not r[3]]
    unknown = sorted({s for r in all_rows for s in r[2] if s not in defined})

    if check:
        problems = 0
        for rid, _, _, _, where, _ in unattached:
            print(f"{where}: {rid} names no scenario. Add the journey id it serves "
                  f"(see docs/JOURNEYS.md), or `no-scenario: <reason>`.")
            problems += 1
        if unknown:
            print(f"rows name scenarios JOURNEYS.md does not define: {', '.join(unknown)}")
            problems += 1
        if problems:
            print(f"\nFAIL: {problems} problem(s). Every task belongs to a scenario.")
            return 1
        print(f"PASS: {len(all_rows)} rows, every open one attached to a scenario.")
        return 0

    by_scenario: dict[str, list[tuple[str, str, bool]]] = {}
    for rid, status, scenarios, _, _, deferred in all_rows:
        for scenario in scenarios:
            by_scenario.setdefault(scenario, []).append((rid, status, deferred))

    # A scenario is READY for its v1 review when every v1 row naming it is
    # closed; rows deferred to v1.1/v1.x/v2 are listed but do not hold it open.
    ready, active = [], []
    for scenario, items in sorted(by_scenario.items()):
        open_rows = [r for r, s, d in items if s in " !" and not d]
        deferred = [r for r, s, d in items if s in " !" and d]
        (active if open_rows else ready).append((scenario, items, open_rows, deferred))

    print("READY FOR THE SCENARIO REVIEW - every row naming these is closed.")
    print("Dispatch agents/briefs/REVIEW-SCENARIO.md before marking the story implemented.\n")
    for scenario, items, _, deferred in ready:
        note = f"  (deferred, not blocking: {', '.join(deferred)})" if deferred else ""
        print(f"  {scenario:5s} {defined.get(scenario, '(not in JOURNEYS.md)')[:56]:58s} "
              f"{len(items)} row(s){note}")

    print("\nSTILL OPEN\n")
    for scenario, items, open_rows, deferred in active:
        note = f"  +{len(deferred)} deferred" if deferred else ""
        print(f"  {scenario:5s} {defined.get(scenario, '(not in JOURNEYS.md)')[:56]:58s} "
              f"{len(open_rows)} of {len(items)} open: {', '.join(open_rows[:6])}"
              f"{' …' if len(open_rows) > 6 else ''}{note}")

    if unattached:
        print(f"\nUNATTACHED - {len(unattached)} open row(s) name no scenario:")
        for rid, _, _, _, _, _ in unattached:
            print(f"  {rid}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

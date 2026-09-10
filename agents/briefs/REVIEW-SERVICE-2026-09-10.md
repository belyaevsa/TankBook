# Service-loop walk-through: J7 / J7b / J7d / J7c - regroup or rebuild the rows

**Read `agents/briefs/REVIEW-JOURNEYS.md` first and follow it in full.** Everything below narrows
that brief to this run; where the two differ, the recurring brief wins on method and this file wins
on scope.

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY: no edits, no builds, no
tests, no commits.** A build agent (`RV.198`) is working in this checkout right now - if you write
anything you corrupt its work. Your entire output is your report, plus the ONE file named at the end.

## Why this run

The service loop is **fragmented across six rows and no one of them owns it**, and the product owner
asked whether they form a meaningful branch of work or should be rebuilt:

| Row | Covers | State |
|---|---|---|
| `PJ.23` | edit an item's title / category / cost | shipped `fd57e7b` (2026-09-10) |
| `RV.198` `[!]` | add and delete a line | **in flight right now** |
| `RV.199` | does the header total follow the item costs? | filed, needs a DECISION |
| `PJ.22` | lifetime on an item -> the proposed reminder; writes `proposedReminderId` | PRIORITY since 2026-08-31, unbriefed |
| `PJ.26` | a `.parts` Expense becomes a TireSet; writes `purchaseExpenseId` | PRIORITY since 2026-08-31, briefed |
| `PJ.27` | the seasonal swap reminder from a mount | PRIORITY since 2026-08-31, briefed |

**The finding that prompted this run**: J7's own Fallbacks sentence has promised *"the user
renames/splits by hand"* since the journey was written. `PJ.23` delivered **rename** and its brief
made **split** optional, so the screen could correct a line but not add one - and nothing noticed
until the owner opened it. **A promise in a journey with no row behind it is the shape this walk
exists to find.**

## Your scope

**J7 (service visit), J7b (parts, tires, consumables), J7d (a reminder is born) and J7c (reminder
lifecycle)** - the whole loop from invoice to the next reminder firing, plus the parts shelf and
tire sets that hang off it. Both passes apply: **reachability** and **sequence**.

## The four things to settle

1. **Walk the loop as a SEQUENCE, not as screens.** Follow one workshop invoice end to end: scan or
   type -> line items -> categories -> costs -> the header total -> the proposed reminder -> the
   parts shelf -> a tire set -> the seasonal swap -> the reminder firing -> completing it. **Say at
   which step each fact stops being carried**, exactly as the 2026-09-10 import walk did for
   currency and station. That walk found `PJ.58` and `PJ.59` this way.
2. **Every promise J7/J7b/J7d/J7c makes, against a row.** One line per promise: **MET** (`file:line`),
   **PARTIAL** (what exists, what is missing, both cited), **MISSING** (what you searched for), or
   **N/A** (why - a later phase, a v2 journey). **The output that matters most is a promise with no
   row**, like *"renames/splits by hand"* was.
3. **Then answer the owner's actual question: group or rebuild?** For the six rows above, say
   whether they are the right decomposition. The project's rule is that **a group is justified by a
   shared SEAM, never a shared theme** - if two rows edit the same file, or one is how you diagnose
   the other, they are one dispatch. *"All about services"* is a theme and is not enough.
   **Propose the dispatch list you would actually run**, in order, with the seam named for each and
   the blocking relationships stated. Recommending "leave them as they are" is a legitimate answer
   if that is what you find.
4. **Two dead fields sit in this loop** - `ServiceRecord.proposedReminderId` and
   `TireSet.purchaseExpenseId`, both `nil` at every production write, both reported by `RV.196`'s
   field guard. **`PJ.22` and `PJ.26` are their writers.** Check whether the loop has MORE of them:
   a field, a link or an entity this journey describes that nothing can create. `TireSet` has no
   `###` section in `docs/SCHEMA.md` at all, so neither `RV.163` nor `RV.196` can see any of its
   fields - **that blind spot is yours to cover.**

## Two standing cautions that have each cost a row

- **A `[x]` row whose behaviour the code does not have is the most valuable finding you can make**,
  and only a re-run produces it. Say it explicitly: *"PJ.n is ticked but …"*. `PJ.23` shipped hours
  ago - check it honestly rather than trusting its row.
- **A doc or comment naming behaviour with no call site is a defect shape**, not documentation debt.
  It has appeared repeatedly this week, including `TireSetDraft`'s comment promising that a rename
  *"must never overwrite"* `purchaseExpenseId` - a promise about a value nothing can set.

## Already tracked - cite, never re-file

The six rows above, plus `PJ.52` (parts shelf, `[v2]`), `RV.169`/`RV.171` (guards awaiting seams),
`RV.187` (the Log row's title), `RV.195` (the expense category). **Read `docs/TASKS.md` end to end
before proposing anything** - twice on 2026-09-10 a finding was filed that an existing row already
carried (`RV.195`'s "leftover" was `PJ.23`; `RV.165` duplicated `RV.110`).

## Number your rows in a fresh range

Use **`PJ.60`+** for new findings, and say which run produced them.

## Output

Write your report to **`diagnostics/REVIEW-SERVICE-2026-09-10.md`** - that is the **one file you may
create**, and the only write you are permitted.

Tables, `file:line`, no narrative. **Never MET without a citation.** **Never quote a domain value**
from a fixture or a log. Finish with, in this order:

- **the ticked rows you found to be untrue, FIRST** - they are the point of a re-run;
- **the sequence trace** from item 1, as its own table;
- **the promise-to-row map** from item 2, with the promises that have no row called out;
- **the recommended dispatch list** from item 3 - grouped, ordered, each with its seam and its
  blockers, or a reasoned "leave them as they are";
- proposed `PJ.60`+ rows, each with its one-line deliverable, the journey stage it closes, the
  user-facing consequence **today**, severity (**bug** / **gap** / **polish**), and the check that
  makes it done (L1/L4, naming the suite);
- anything you looked for and could not settle, and what would settle it.

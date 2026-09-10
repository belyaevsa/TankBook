# REVIEW-JOURNEYS run, 2026-09-10 - Group C + Group D

**Read `agents/briefs/REVIEW-JOURNEYS.md` first and follow it in full.** Everything below narrows
that brief to this run; where the two differ, the recurring brief wins on method and this file wins
on scope.

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY: no edits, no builds, no
tests, no commits.** A build agent (`RV.181`) is working in this checkout right now - if you write
anything you corrupt its work. Your entire output is your report, plus the ONE file named at the end.

## Why this run, and why these groups

Two runs happened on 2026-09-09: the first went deep on J4 / J7b / money+rates / feedback, the
second took **Group A and Group B**. **Groups C and D have never been walked.**

That matters more than usual right now. Since the last walk the product owner has reported **ten
defects by using the app**, and **six of them are in Group C's territory** - import, currency, and
the F6/F9 states:

| Row | What it was |
|---|---|
| `RV.185` | An imported car ignores the declared currency (KZT became EUR) and cannot be named |
| `RV.186` | A service at the same odometer as its fill-up is flagged and excluded from the stats |
| `RV.187` | Imported expenses/services arrive with no title - the column that names them is read only as a category |
| `RV.188` | The conflict panel lists two consistent entries and declares them impossible; the culprit is an unlabelled dot |
| `RV.189` | Imported fills show `92`, not the station the file names - cause **not established** |
| `RV.182` | A catalogue row shows a tank volume that picking it does not fill |

**Not one was caught by a test, a code review or the type checker.** Group C is where the app is
weakest and least walked, which is the whole argument for this run.

## Your scope

**Group C (`PJ.3xx`) and Group D (`PJ.4xx`)** exactly as the recurring brief defines them - see its
"Group C" and "Group D" sections for the journey lists and focus points. Both passes apply:
**reachability** and **sequence**.

Group C is J8, J9, J10, J2's parse/preview/commit, F6, F6a, F6b, F9, F9a.
Group D is J11a, J11, J12, J13, F7, F10.

## Four things to settle, on top of the group walks

1. **Walk an import END TO END as a sequence, not as screens.** `RV.185`-`RV.189` are all
   *sequence* defects: every individual screen was correct and the data lost its meaning between
   them. Follow one Drivvo file through source → cars → preview → review → commit → Log → Trends and
   say at which step each fact (currency, car name, station, title, odometer) stops being carried.
   `Spike/ImportFixtures/drivvo/drivvo-ru-3sections.csv` is the owner's own file.
2. **F9 / F9a after an import.** `RV.186` showed entries excluded from the stats for a reason that
   was not a defect in the data. Ask what the user can actually DO from each F9/F9a surface, and
   whether the next step it names exists (hard rule 7). `RV.188` is the known instance; report any
   sibling.
3. **J13 and F10 (Group D), which no walk has ever covered.** Archive, delete, and the export/exit
   path. Note that `RV.181` - *no share in the app dispatches anything* - is in flight and touches
   the export lane; **cite it, do not re-file it**, but say whether J13's promise depends on
   anything else that is unbuilt.
4. **`docs/DEFECT-PATTERNS.md` Part 2's five shapes**, applied to C and D specifically. The guards
   shipped this week (`RV.162` screen routes, `RV.163` entity writers, `RV.167` money aggregation)
   each state a blind spot in their own rows - **you are the check on what they cannot see.**

## Two standing cautions that have each cost a row

- **A `[x]` row whose behaviour the code does not have is the most valuable finding you can make**,
  and only a re-run produces it. Say it explicitly: *"PJ.n is ticked but …"*.
- **A doc or comment naming behaviour with no call site is a defect shape**, not documentation debt.
  It has appeared **five times** in the last two days: `recordsEqual`'s "non-Vehicle", the station
  row's PJ.19 citation, `LogStream.group`'s "never summed as zero", RV.161's "the oracle is the
  filename", and RV.142's *"the commit materialises the rows"*. Read comments as claims to check.

## Already tracked - cite, never re-file

`RV.173`-`RV.189` (the current backlog, all filed 2026-09-09/10), `RV.165` (the full journey suite),
`RV.170`/`RV.171` (guards awaiting their seams), `RV.179`/`RV.180` (station corpus and brand/site),
`PJ.55` and `RV.161` (shipped today). Read `docs/TASKS.md` end to end before proposing anything.

## Number your rows in a fresh range

Use **`PJ.58`+**, and say which run produced them. Group C and D findings both draw from that single
range.

## Output

Write your report to **`diagnostics/REVIEW-JOURNEYS-2026-09-10.md`** - that is the **one file you may
create**, and the only write you are permitted.

Per the recurring brief: one line per journey stage/fallback with **MET** (`file:line`) / **PARTIAL**
(what exists, what is missing, `file:line` for both) / **MISSING** (what you searched for) / **N/A**
(why - a later phase per `VISION.md`, or a v2 journey). **Never MET without a citation.** Tables,
`file:line`, no narrative. **Never quote a domain value** from a fixture or a log.

Add your run to the run-history table in your report (tree `ea20655`), and finish with:

- **the ticked rows you found to be untrue, listed FIRST** - they are the point of a re-run;
- the proposed `PJ.58`+ rows, each with its one-line deliverable, the journey stage it closes, the
  user-facing consequence **today**, severity (**bug** / **gap** / **polish**), and the check that
  makes it done (L1/L4, naming the suite);
- **the import sequence trace** from item 1, as its own table;
- anything you looked for and could not settle, and what would settle it.

# REVIEW-JOURNEYS run, 2026-09-09 (second run of the day) - Group A + Group B

**Read `agents/briefs/REVIEW-JOURNEYS.md` first and follow it in full.** Everything below narrows
that brief to this run; where the two differ, the recurring brief wins on method and this file wins
on scope.

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY: no edits, no builds, no
tests, no commits.** Another agent is building in this checkout right now - if you write anything
you will corrupt its work. Your entire output is your report.

## Why this run exists, and what makes it different from this morning's

The first run today (tree `4cc801a`, `diagnostics/REVIEW-JOURNEYS-2026-09-09.md`) went **deep on
J4 / J7b / money+rates / feedback** and left the rest of the map untouched. It yielded one row
(`PJ.55`). **This run takes the half that run did not: Group A and Group B.** Do not re-walk J4 or
J7b except where a Group A/B journey passes through them, and cite that run's findings rather than
re-deriving them.

Four rows have shipped since `4cc801a`, and three of them fire the recurring brief's event
triggers:

| Shipped | Commit | Which trigger it fires |
|---|---|---|
| `RV.141` | `85ba6d5` | **Trigger 3** - copy naming a destination shipped: the Home excluded-entries footnote now claims to reach its entries and say why they are out. Walk that claim |
| `RV.166` | `378ee65` | **Trigger 2** - a reader of money shipped: a purchase group's header now classifies `.complete`/`.partial`/`.mixed`/`.pending`. Walk what a user sees for each of the four, not just the one the row fixed |
| `RV.167` | `62b61d2` | Test-only. No journey consequence; listed so you do not go looking |
| screenshots | `4bbb302` | Not a product change, but it proved `P1.5-log-stream` had **never** shown a log row. **Treat committed screenshots as evidence with suspicion** - one was a picture of a different screen for months |

## Your scope this run

**Group A (`PJ.1xx`) and Group B (`PJ.2xx`)** exactly as the recurring brief defines them - see its
"Group A" and "Group B" sections for the journey lists and focus points. Both passes apply:
reachability **and** sequence.

**Three specific things to settle, on top of the group walks:**

1. **`RV.141`'s footnote (trigger 3).** The Home footnote reads "N entries excluded". Does tapping
   it reach those entries, and does the destination explain *why* each is out? The row shipped
   claiming it does. Screenshot evidence exists at `design/screenshots/RV.141-home-excluded.png` -
   and note the footnote renders amber with **no chevron**, unlike the blue affordance directly
   above it. **Say whether that is a comprehension defect** (a button that reads as a label) or
   correct (hard rule 5 makes amber a warning, not an action). `RV.159` is the same class and is
   already filed - **cite it, do not re-file it**.
2. **`RV.166`'s four states (trigger 2).** A purchase-group header can now be `.complete`,
   `.partial`, `.mixed` or `.pending`. Only `.partial` was walked when the row shipped. **What does
   a user actually see for `.mixed` and `.pending`?** Both print no figure. Is that reachable, and
   is the receipt still comprehensible when its header states nothing - or is there a state where
   the user sees a group card with no total and no explanation? That would be a hard rule 7 gap.
3. **Trigger 1, the screens that shipped recently and their routes**: `RV.156`'s station creation
   (from the entry row AND the Garage) and `PJ.25`'s parts shelf door. **From a cold launch with no
   debug flag** - `PJ.4` shipped a screen whose only route was `-presentScreen`, unreachable in
   Release, with a green suite. The UI tests navigate via `-presentScreen`, so **a green suite is
   not evidence of reachability**; find the production route or report there is none.

## Two standing cautions that have each cost this project a row

- **A `[x]` row whose behaviour the code does not have is the most valuable finding you can make**,
  and only a re-run produces it. Say it explicitly: *"PJ.n is ticked but …"*.
- **A doc naming behaviour with no call site is a defect shape**, not documentation debt
  (`docs/DEFECT-PATTERNS.md`). `docs/ERRORS.md:209`'s "Storage full" warn sheet is a live example -
  it is already being checked by the `RV.149` agent, so **cite it, do not investigate it**.

## Already tracked - cite, never re-file

`PJ.55` (station ranking's `favorite` rung), `RV.149` (fill-up receipt fails silently - **in flight
right now**), `RV.159` (two identical-looking consents), `RV.160` (feedback send looks like
nothing), `RV.162`/`RV.163` (the enumeration guards), `RV.165` (the journey suite), `RV.148`
(deferred by the product owner - **not a finding**), `RV.169`-`RV.172` (source-scan guards, filed
today). Read `docs/TASKS.md` end to end before proposing anything.

## Number your rows in a fresh range

Use **`PJ.56`+** for new rows, and say which run produced them. Group A and Group B findings both
draw from that single range this run - the `PJ.1xx`/`PJ.2xx` split in the recurring brief applies
when four agents run in parallel; you are one agent covering two groups.

## Output

Write your report to **`diagnostics/REVIEW-JOURNEYS-2026-09-09b.md`** - that is the **one file you
may create**, and the only write you are permitted. Nothing else in the tree.

Per the recurring brief: one line per journey stage/fallback with **MET** (`file:line`) /
**PARTIAL** (what exists, what is missing, `file:line` for both) / **MISSING** (what you searched
for) / **N/A** (why - a later phase per `VISION.md`, or a v2 journey). **Never MET without a
citation.** Tables, `file:line`, no narrative. Never quote a domain value from a fixture or a log.

Then add your run to the run-history table in your report (tree `1ec2b1d`), and finish with:

- the proposed `PJ.56`+ rows, each with its one-line deliverable, the journey stage it closes, the
  user-facing consequence **today**, severity (**bug** / **gap** / **polish**), and the check that
  makes it done (L1/L4, naming the UI suite);
- **the ticked rows you found to be untrue**, listed separately and first - they are the point of a
  re-run;
- anything you looked for and could not settle, and what would settle it.

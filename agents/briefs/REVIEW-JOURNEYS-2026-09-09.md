# REVIEW-JOURNEYS, re-run 2026-09-09

**Read `agents/briefs/REVIEW-JOURNEYS.md` first and follow its shared instructions in full.** This
file only sets *this* run's scope and priorities. You are **one** agent, not the original four - the
machine is memory-constrained and another agent is building in this checkout right now.

## Read-only. Absolutely no edits, builds or tests.

You write **exactly one file**: `diagnostics/REVIEW-JOURNEYS-2026-09-09.md`. Nothing under `ios/`,
`backend/`, `docs/` or `agents/`. Do not run `swift build`, `swift test`, `xcodebuild` or `dotnet` -
**another agent owns that toolchain right now**. Never move, rename or revert a file you did not
create; if something changes under you, report it and carry on.

## Why this run exists

The journeys review ran **once**, on 2026-08-29 at `93d2619`, produced 66 `PJ` rows, and was never
repeated. **643 commits have landed since.** Every product-reachability gap in
`docs/DEFECT-PATTERNS.md` Part 2 was found either by that review or by the product owner using the
app - never by a test or a code review. Read Part 2 before you start; it is the taxonomy you are
hunting.

## What this run must prioritise, in order

1. **`[x]` rows whose behaviour the code does not have.** This is the finding only a re-run can
   produce and it is worth more than a new gap. Say it explicitly: *"PJ.n / RV.n is ticked but …"*.
   Recent evidence that this happens: `PJ.28` was ticked-adjacent for months while the photo was
   dropped; `RV.136` was ticked twice and the loop survived both.
2. **The four event shapes from `DEFECT-PATTERNS.md` Part 2**, applied to everything that shipped
   since `93d2619`:
   - a **screen or route** that has no non-DEBUG path from a tab root;
   - a **reader of an entity** with no production writer (not a seed, not the import path);
   - **copy naming a destination or outcome** that does not exist;
   - a row that shipped **partially**, with the remainder never filed.
3. **The journeys this session's work touched most**, because they moved most: J4 (station), J7b
   (purchase and the parts shelf), the money and rate journeys, and the feedback/About flow.
4. Everything else in `JOURNEYS.md`, as budget allows. **Depth beats coverage** - a thorough verdict
   on half the journeys is worth more than a shallow pass over all of them. Say where you stopped.

## The rules that keep this useful

- **Never MET without a `file:line` citation.** A verdict with no citation is an opinion.
- **A gap already tracked is CITED, never re-filed.** `docs/TASKS.md` carries 95 open rows and
  `docs/TASKS-DONE.md` 293 closed ones - check both. Re-filing a known gap makes the backlog worse.
- **Check the version marker before filing.** A journey marked `[v1.1]`, `[v1.x]` or `[v2]` in
  `VISION.md`/`JOURNEYS.md` is not a v1 gap - say N/A and why.
- **Propose rows in the row format `docs/TASKS.md` uses** - the defect with its evidence, the
  deliverable, the checks, and named vacuous traps - so a proposal can be filed without a rewrite.
- Number new rows `PJ.<n>` in a fresh range and say this run produced them.

## Report back

The findings file's path, then in three sentences: how many `[x]`-but-not-true rows you found, how
many new gaps, and where you stopped. Do not summarise the file's contents in prose - the file is
the deliverable.

# VERIFY-SHIPPED - do the last 30 ticked rows still hold?

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`.

## READ-ONLY. One output file, nothing else.

You write **exactly one file**: `diagnostics/VERIFY-SHIPPED-2026-09-09.md`. No edits anywhere else,
no commits. **Do not run `swift build`, `swift test`, `xcodebuild` or `dotnet`** - another agent owns
that toolchain right now and the machine is memory-constrained. You are reading code, not proving a
fix. Never move, rename or revert a file you did not create.

## Why this run exists, and the specific risk it hunts

A row is ticked when its own gates pass. **Nothing re-checks it afterwards**, and several rows
shipped since have rewritten the ground under earlier ones:

- **`RV.145`** reshaped `LogStream.MonthTotal` and rewrote **every money surface** - the divider, the
  vitals tile, the guest strip, `VehicleVitals`, the Trends tile and series.
- **`RV.153`** changed the receipt total finder's precedence.
- **`RV.156`** moved the station row out of `ManualFillUpSections` into its own file and changed both
  its states.
- **`RV.157`** changed *when* a sync fires, and brackets the engine's own writes.
- **`RV.150`/`PJ.19`** added station stamping and ranking on top of screens that predate them.

**The finding worth most is a `[x]` row whose behaviour the code no longer has.** The 2026-09-09
journeys re-run checked this session's rows and found none; **it did not check the older ones**, and
those are the ones the refactors above passed through.

`RV.136` is the cautionary tale: ticked twice, and the loop survived both.

## The rows to verify, oldest first - spend your budget in this order

**Group A - shipped BEFORE the refactors, highest risk (start here):**
`RV.126`, `RV.128`, `RV.131`, `RV.132`, `RV.133`, `RV.135`, `RV.137`, `RV.140`, `RV.141`, `RV.142`,
`RV.82`, `RV.112`.

**Group B - shipped during the refactors:**
`RV.144`, `RV.145`, `RV.146`, `RV.147`, `RV.117a`, `RV.117b`, `PJ.19`, `PJ.25`, `PJ.28`.

**Group C - shipped last, already spot-checked by the journeys re-run (skip unless budget remains):**
`RV.136`, `RV.150`, `RV.151`, `RV.153`, `RV.154`, `RV.156`, `RV.157`.

Each row's text is in `docs/TASKS-DONE.md`. **The row's own "Checks" column is the specification** -
that is what was promised, and what you are testing the code against.

## What a verdict looks like

For each row, one of:

- **HOLDS** - with a `file:line` citation for the seam that makes it true. **Never HOLDS without a
  citation.**
- **BROKEN** - the behaviour the row claims is not in the code. Say what the row promised, what the
  code does now, both with citations, and **name the change that most likely undid it**.
- **UNVERIFIABLE FROM SOURCE** - say what you would need (a device, a run, a fixture) and stop. This
  is an honest verdict; guessing is not.

**Weight the row's headline claim, not its incidentals.** A row that promised "the divider cannot
express a wrong total" is broken if a wrong total is expressible, not if a comment moved.

## Things that make a row look fine and are not evidence

- **A green test suite.** `PJ.4` shipped a screen unreachable in Release with a green suite;
  `RV.156` shipped a correctly-rendered permanently dead label. Read the code, not the results.
- **A test that asserts the old behaviour.** `MoneyBackfillServiceTests` froze `costPerKm = 0.1`
  with a pending row skipped - the exact defect `RV.147` later removed. **A passing test can be
  asserting the bug.** If you find one, that is a finding in its own right.
- **A doc or comment.** `recordsEqual`'s comment described its own bug as deliberate for months.

## Also report, if you see them

- A row whose **remainder was fenced out and never filed** - `PJ.28` sat half-delivered for months
  because `RV.62` closed its own scope correctly.
- The four shapes in `docs/DEFECT-PATTERNS.md` Part 2, on anything you touch: an unreachable screen,
  a reader with no writer, copy naming something that does not exist, a dead end.

## Do not re-file what is tracked

`docs/TASKS.md` has 105 open rows and `docs/TASKS-DONE.md` 293 closed. **Cite an existing id rather
than proposing a new row.** Only propose new rows for something no row covers, in the row format
`TASKS.md` uses, numbered from `RV.166` upward.

## Report back

The findings file's path, then in three sentences: how many rows verified, how many **BROKEN**, and
where you stopped. The file is the deliverable - do not summarise it in prose.

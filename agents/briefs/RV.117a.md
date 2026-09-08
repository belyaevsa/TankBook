# RV.117a - the timeline conflict's valid RANGE, computed in core

**[v1.1]** - this is a point-release row, not a launch blocker. It is the **substance half** of
[RV.117]; the neighbourhood chart is RV.117b and is briefed after this lands, because its shape
depends on what this returns. RV.117's own trap list is the reason for the order: *"shipping the
chart without the intervals, which is decoration"*.

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** If a file is in your way or a test is
red that is not yours, report it and carry on.

## What this task is, in one sentence

Given the entries either side of a flagged one, return **the odometer interval valid for its date**
and **the date interval valid for its odometer** - so the user can see which of the two fields is
wrong, instead of only that something is.

## Why it matters, from the product owner (2026-09-07)

Drivvo, on an odometer that contradicts its date, tells the user:
*"on 13/07/2025 the odometer must be between 490 500 and 490 983 km; if 490 200 is correct, the date
must be..."* - across neighbours 489 590 / 490 500 / **490 200** / 491 206 / 491 791.

Tankbook today quotes **one** neighbour and offers ranked fixes (`docs/ERRORS.md` -> Confirm -> F9a):
*"Aug 17 already recorded 119 486 km."* Honest, and thin. The owner hit this after importing years of
history, where an entry flagged in the past is one they cannot reason about from memory.

## Read the numbers before you design: the upper bound is NOT the next entry

In the Drivvo example the next entry is **491 206**, but the stated upper bound is **490 983**. So the
interval is **not** simply `(previous, next)` - it is the **intersection of the order constraint and
the pace constraint**. Both checks already exist in `TimelineValidator` and both must bound the
interval, or your range will claim values the validator would flag - which is this row's third
vacuous trap ("computing the range separately from `TimelineValidator` so the two can disagree").

## What already exists - build on it, do not fork it

`ios/Sources/TankbookCore/Validation/TimelineValidator.swift` (248 lines):

- `validate(_:at:in:limit:attachmentsByID:)` (`:100-160`) already walks **back** to the nearest
  earlier entry with an odometer and **forward** to the nearest later one (`:107-124`), skipping
  entries that carry none. That neighbour pair is exactly this row's input - do not re-derive it.
- **CHECK 1, order** (`:127-137`): the odometer must fit **strictly** between the neighbours
  (`odo <= previous.odometer` flags; `odo >= next.odometer` flags).
- **CHECK 2, pace** (`:139-158`): `abs(Δodometer) / days > limit` flags, where `limit` is
  `vehicle.paceLimitKmPerDay` (`:70`, `:80`; DB default 1500, `Migrations.swift:213`) and `days`
  comes from `dayDiff`. Note the guard `days > 0`: **same-day neighbours are not pace-checked**, so
  the pace bound does not exist in that case and the interval must not invent one.
- `Flag.Detail.order(previousOdometer:previousDate:nextOdometer:nextDate:)` (`:20-21`) already
  carries all four values a caller needs.
- `ResolutionSuggestion` (`:31-34`) is `fixOdometer(from:to:)` / `fixDate(from:to:requiresExplicitConfirmation:)`
  - a **single** suggested value. This row's interval is the honest generalisation of that single
  value, but **`suggestions` must keep working exactly as it does now**: `docs/SCHEMA.md`'s PRIORITY
  rule (a receipt's `extractedTimestamp` makes the printed date ground truth, so "fix odometer" ranks
  first and a date change needs explicit confirmation) is not yours to change here.

## What to build

**A derived interval type in core, returned alongside the flags.** Shape it yourself, but it must
express all of these and make the wrong one inexpressible:

1. **The odometer interval valid for this entry's date**: the intersection of
   - order: strictly above `previousOdometer`, strictly below `nextOdometer`;
   - pace: at most `previousOdometer + limit * days(previous -> entry)`, at least
     `nextOdometer - limit * days(entry -> next)`.
2. **The date interval valid for this entry's odometer**: the dates on which this odometer is
   consistent with both neighbours, bounded the same two ways.
3. **Open ends are first-class.** The newest entry has no `next`, the oldest has no `previous`, and a
   same-day neighbour contributes no pace bound. An absent bound is **open**, not a large number and
   not a silently dropped constraint - the row requires it to "say so rather than inventing one".
4. **An empty interval is possible and must be representable.** When the two constraints cross - the
   neighbourhood itself is inconsistent, which a multi-year import can produce - there is no valid
   value, and saying "must be between 490 983 and 490 500" would be nonsense. Decide what the type
   returns and say why in your report.

**Derived, never stored** (hard rule 2). Nothing goes in the database, nothing is written onto the
entry, no migration.

**One source of truth.** The interval must be computed from the same neighbour walk and the same
`limit` the flags use, in the same pass - so a value inside the interval is never flagged and a value
outside always is. That equivalence is a required test, not a hope.

**Do not auto-correct** (hard rule 13). This returns information; it never changes a value, never
pre-fills a "corrected" number as fact, and never reorders `suggestions`.

## Explicitly out of scope

- **The chart and every UI change** - that is RV.117b. This task changes `TankbookCore` and its
  tests only. Do not touch `ios/App/Sources`, do not take screenshots, do not run UI suites.
- Changing when an entry flags, the pace limit, or the PRIORITY ranking of `suggestions`.
- [RV.104]'s acceptance behaviour. An accepted entry's interval is still computable; suppression is
  a separate concern and stays as it is.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> Validation (CHECK 1, CHECK 2, PRIORITY) - **the authority for this task**.
2. `docs/ERRORS.md` -> Confirm -> F9a (what is shown today, line ~146).
3. `CLAUDE.md` hard rules 2 and 13.

**Extend `docs/SCHEMA.md` -> Validation in the same change** with the interval's definition,
including the open-ended and empty cases. A doc left stale is an unfinished task.

## Checks

Baseline on `main` as left: **1675 tests / 187 suites**, **777** localization keys at 100% RU,
`swift build` 0, `swiftlint lint` 0 errors **from the repo ROOT**. **Re-measure yourself and report
what you observe** - do not copy these numbers into your report.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. **No UI suites and no `xcodegen`** - this task touches no app code. If you find yourself needing
   them, you have left the fence; stop and report instead.
5. Localization gate - exit 0; report the key count. (No new user-facing strings are expected here -
   the copy is RV.117b's. If you think one belongs in core, say so rather than inventing it.)
6. Release build - not required; nothing here is behind a `#if DEBUG` seam. Confirm that is true.

Verify by **exit code** (`echo $?`), not by skimming output, and report the codes you observed.

### Tests you must add

- **L1, the row's whole point - assert the ENDPOINTS, not that a range exists.** Use the owner's own
  numbers as a fixture: neighbours 489 590 / 490 500 / [entry] / 491 206 / 491 791. With a pace limit
  that reproduces it, the odometer interval's upper bound is the **pace** bound, not `next - 1`.
- **L1**: the newest entry (no `next`) has an **open** upper bound and the oldest (no `previous`) an
  open lower bound - assert openness, not a sentinel value.
- **L1**: a same-day neighbour contributes **no** pace bound (the `days > 0` guard), so the interval
  is bounded by order alone.
- **L1, the equivalence that keeps the two from disagreeing**: for a generated neighbourhood, every
  odometer inside the computed interval validates clean and every odometer outside it flags. Drive it
  over the boundary values themselves (bound, bound±1), not over a random sample.
- **L1**: the date interval for a fixed odometer, at its endpoints, both directions.
- **L1**: an inconsistent neighbourhood yields the empty/no-valid-value case rather than an inverted
  range.

### Vacuous traps, named

- **Computing the range separately from `TimelineValidator`**, so the two can disagree. Same walk,
  same limit, same pass.
- **Testing only a middle entry**, where both neighbours exist - the open-ended cases are exactly
  what this row calls out, and they never arise there.
- Asserting a range is non-nil, or that its width is positive, instead of asserting its endpoints.
- Dropping the pace constraint because order alone is easier - it would claim 491 205 is valid in the
  owner's example, which the validator flags.
- Representing an open bound as `Int.max`, a far-future date, or `0`.
- Auto-applying or pre-filling the suggested value (hard rule 13).
- Changing `ResolutionSuggestion`'s ordering or the PRIORITY rule.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## This brief's reading of the code is a hypothesis - confirm it before you change anything

The line numbers were read on the tree as left; verify them. In particular **verify the claim that
the Drivvo upper bound is pace-derived** - it is the reasoning this whole design rests on, and if the
numbers do not support it, say so and report what they do support. Recent sessions have had four
orchestrator diagnoses proved wrong by the agent that checked; that is a good outcome, not a failure.

## Report back

Every check with the **exit code you observed** and the observed test count; whether each new test was
**run or only written**; the shape you chose for the interval type and why the wrong state is
inexpressible in it; what you decided for the empty-interval case; whether the pace bound really is
what produces Drivvo's 490 983; and anything you found that belongs in RV.117b rather than here.

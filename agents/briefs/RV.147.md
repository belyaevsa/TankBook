# RV.147 - costPerKm still sums a rate-pending row as zero

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** If a file is in your way or a test is
red that is not yours, report it and carry on.

**Order matters: this row goes AFTER [RV.145].** RV.145 reshapes the very accumulator you must reuse
(it adds the home-currency axis to `LogStream.MonthTotal`). Confirm RV.145 has landed before you
start - `git log --oneline -20 | grep RV.145`. If it has not, **stop and report that** rather than
building against the old shape.

## The defect

Reported by the [RV.112] agent and correctly left outside its fence.
`ConsumptionEngine.costPerKm` (`ios/Sources/TankbookCore/Consumption/ConsumptionEngine.swift:194-206`):

```swift
let homeTotal = inWindow.reduce(Decimal.zero) { partial, entry in
    guard let homeAmount = entry.money?.homeAmount else { return partial }
    return partial + homeAmount
}
```

A rate-pending row contributes **zero** and is not counted - the same mechanism [RV.106] fixed on the
Log divider and [RV.112] fixed on the vitals tile and both Trends series. This is the **fourth**
instance of the shape, one surface further out.

Visible in `design/screenshots/RV.112-trends.png`: the `COST / KM` tile reads **`0.07 €`** on a car
with four pending entries. `HomeStats.costPerKm` (`HomeStats.swift:47`, `:124`) is a plain `Double?`,
so nothing downstream can tell an exact figure from an understated one.

## What makes this one different from RV.106 and RV.112: it is a RATIO

The others were sums. This is `Σ money / Δ odometer` over a 90-day window, so a partial numerator
sits over a **complete** denominator. A cost-per-km computed from an understated total is not
"approximately right" - it is **low by an unknown amount**, and it looks perfectly plausible, which
is worse than a visibly missing number.

**Decide and record the honest treatment**, do not assume one. Write the decision and its reason into
`docs/SCHEMA.md` -> Derived: consumption -> COST/KM. The obvious candidates, and the row does not
pick for you: report the figure as partial the way the divider does; or decline to report a figure at
all while the window contains a pending row; or report over the sub-window that is fully known, if
that can be defined without lying about the span.

**Whatever you decide, `costPerKmSpanMonths` must follow it.** `TrendsStats.swift:206-215` derives
the tile's "last 3 months" label from the same window; a label describing a span the figure no longer
covers is the same class of lie this row exists to remove.

## What to build

**Reuse [RV.112]'s accumulator - do not write a fourth summation.**
`LogStream.MonthTotal.Accumulator` (`LogStream.swift:498-524`) is the one place that decides what a
pending row contributes, and after [RV.145] it also carries the home-currency axis. The windowed
total goes through it, so this figure and the tile above it can never disagree about what is known.

If the accumulator genuinely cannot serve a windowed (rather than monthly) total, **say so with the
reason** and extract the shared piece rather than duplicating the rule - but try the reuse first.

**Every caller of the figure must handle the new shape**, not just the Trends tile: `HomeStats`
(`:47`, `:124`) and anything reading it. A caller left printing a bare `Double` is the defect
re-introduced one layer up.

## Explicitly out of scope

- [RV.145]'s divider/tile/symbol work - it is the row before this one; build on it, do not redo it.
- The EV figures (`evSegments`) and the consumption headline, unless they carry the identical
  `reduce` - if they do, **say so and fix them here**, since leaving one is how this shape has now
  survived three rows.
- The rate feed ([RV.135], [RV.139]). Assume rates may never arrive.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> Derived: consumption -> COST/KM - **the authority, and extend it here**.
2. `docs/ERRORS.md` -> Home and Trends, F9.
3. `CLAUDE.md` hard rules 2, 3, 7.

## Checks

Re-measure the baseline yourself and report what you observe; RV.145 will have moved it.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. (From the root, not `ios/`: the `excluded:`
   paths are root-relative and it reports thousands of phantom errors otherwise.)
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then `TankbookUITests/TrendsUITests` and `TankbookUITests/HomeUITests` **by
   name**, each with its **observed, non-zero** count. A filter matching nothing prints "0 tests ...
   passed" and still exits 0.
5. Localization gate - exit 0; report the key count. Any new string is EN **and** RU (hard rule 10).
6. Release build only if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), not by skimming output, and report the codes you observed.

### Tests you must add

- **L1**: a window containing a pending row does **not** report a bare cost-per-km number.
- **L1**: a fully converted window is unchanged, **to the cent** - the regression guard.
- **L1**: the figure agrees with the accumulator's classification for the same entries. Assert
  through the shared seam, not against a parallel calculation written in the test.
- **L1**: `costPerKmSpanMonths` and the figure never disagree about what the window covers.
- **L4**: the Trends `COST / KM` tile in the pending state - the `0.07 €` scene from
  `design/screenshots/RV.112-trends.png` is the fixture to reproduce.

### Vacuous traps, named

- A fixture with **no** pending rows - it passes today.
- Marking the tile partial while the underlying figure is still computed from an understated total:
  the label would be honest about a number that is not.
- Fixing the Trends tile and leaving `HomeStats.costPerKm`'s other callers printing a bare Double.
- Writing a fourth summation instead of reusing the accumulator - that is how the three surfaces
  disagreed in the first place.
- Dividing a partial numerator by a partial denominator to "balance" it: the odometer span is known
  and must not be degraded to match the money.

## Screenshots

The Trends `COST / KM` tile in the pending state, **EN and RU**, **dark** theme, captured **outside**
any running test. Commit as `design/screenshots/RV.147-trends.png` and `RV.147-trends-ru.png`.
RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
Pass `-homeResetDatabase` alongside any seed. **You cannot see your own screenshots**; state what you
captured and how, and do not assert they look right.

## This brief's reading of the code is a hypothesis - confirm it before you change anything

Line numbers were read before RV.145 landed and that row edits some of these files. Verify every one.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; the fail-then-pass (or mutation) evidence; what you decided the honest treatment
of the ratio is and why; whether the accumulator served a windowed total or needed extracting; whether
the EV/headline figures carry the same `reduce`; and anything you found and did not fix.

## Never stash, move or `git checkout` to get a "clean baseline"

To show a test fails before the fix: **write the test, run it against the unmodified code, then make
the change.** If the change is already written, prove the test's teeth with a **mutation** - revert
the one line the test is about, run it, restore the line.

**Do not** `git stash`, `git checkout`, or move files out of the tree to get a clean baseline. On
2026-09-08 an agent did exactly that and a bad `mv` loop destroyed three of its own new files; the
same loop would have taken a concurrent session's uncommitted work. Assume you are not alone in this
checkout.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

# RV.112 - the vitals tile and the Trends series still treat a rate-pending row as zero

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - another session may be writing in this
checkout. If a file is in your way or a test is red that is not yours, report it and carry on.

## The defect, pinned

[RV.106] gave the Log's month divider a type that cannot express a wrong total -
`LogStream.MonthTotal` (`ios/Sources/TankbookCore/Consumption/LogStream.swift:50-63`) with
`.complete(Decimal)` / `.partial(amount:pendingCount:)` / `.pending(pendingCount:)`. It correctly
stopped at the divider. **Two other surfaces derive the same figure and still understate it:**

- `HomeStats.monthSpend` (`ios/Sources/TankbookCore/Consumption/HomeStats.swift:149-158`) -
  `guard let homeAmount = entry.money?.homeAmount else { return partial }` inside a `reduce`, i.e. a
  rate-pending row contributes **zero** and is not counted. It is typed `Decimal?` (`:49`) where nil
  means only "the month has no entries".
- `TrendsStats.monthlySpendSeries` (`TrendsStats.swift:108-121`) - the identical `reduce`, per month,
  producing a `TrendPoint` at a value no month actually had.

**And one the row does not name: `TrendsStats.monthlyCostSeries` (`:123-146`) has the same `reduce`
and the same defect** (cost-per-km built on an understated total). Fix it in the same change and say
so; leaving it is exactly how this shape survived RV.106.

The owner's own screenshot from [RV.140] is the visible form: `РАСХОДЫ ЗА СЕНТЯБРЬ 0 €` sitting
directly above two `110.00 USD` rows. Hard rule 2 - a derived figure that asserts a falsehood is the
defect.

**`monthSpend` has FOUR call sites**, all of which print a bare number today. All four must change:

- `ios/App/Sources/Home/HomeSections.swift:242-244`
- `ios/App/Sources/Home/HomeGuestLayout.swift:102-105`
- `ios/App/Sources/Shared/VehicleVitals.swift:20-23` (the Garage / car-switcher vitals)
- `ios/App/Sources/Trends/TrendsView.swift:146-148`

## The design questions are CLOSED. Do not re-open them.

**1. One vocabulary, in core.** Retype `HomeStats.monthSpend` as `LogStream.MonthTotal?` - nil still
means "no entries this month", the three cases carry the honesty. Do **not** invent a second
vocabulary and do **not** duplicate the divider's classification. The shared piece is the
classifier at `LogStream.swift:463-478` (`pendingCount == 0` -> `.complete`; `total > 0` ->
`.partial`; else `.pending`) together with the money-contribution rule at `:495+`. **Extract that
into one core API and have LogStream, HomeStats and TrendsStats all call it**, so the three surfaces
are structurally incapable of disagreeing. Note the callers differ in what they iterate - LogStream
sums per ROW (a purchase group counted once by its grand total, hard rule 4; an S2 duplicate card
only its counted member, docs/SYNC.md) while HomeStats and TrendsStats sum per entry over already-
filtered entry lists - so the shared piece is the **accumulator + classifier**, not the iteration.

**2. A Trends chart omits a month it cannot state, and the line BREAKS there.** A partial month is
not plotted at its known-so-far sum, and a pending month is not plotted at zero: both read as "spend
fell", which is the lie hard rule 2 forbids. A gap reads as "unknown", which is the truth. So
`monthlySpendSeries` and `monthlyCostSeries` yield a point **only for `.complete` months**.
**The gap must be a real gap**: check how the chart renders the array - a series that simply omits
the point will draw a straight line across the hole, which is a worse lie than the dip. If the
renderer interpolates, make the discontinuity explicit. Say in your report which it did.

**3. The chart says why.** When any month inside the plotted window is `.partial` or `.pending`, the
Trends surface carries the pending phrase - reuse `L10n.pendingRates(_:)` and the existing F9
footnote treatment ([RV.111]/[RV.132]), do not write new copy. Any genuinely new string goes through
the String Catalogs in **EN and RU** (hard rule 10).

**4. Rendering.** The divider's shapes are `dividerFigure`/`dividerText` in
`ios/App/Sources/Home/HomeSections+LogStream.swift:118-160`: `.complete` is the number alone,
`.partial` is the DIN figure with the pending phrase beneath, `.pending` is the phrase alone and no
number is ever built. The vitals tile is a different, smaller slot - **you decide the tile's
treatment, but the rule is fixed: a `.partial` figure is visibly marked as partial, and a `.pending`
month prints no number at all.** Colours from `docs/DESIGN.md` tokens only, numbers in DIN, units
subordinate (hard rules 5 and 6). Amber is attention only; a pending rate is a footnote, not an
alarm.

## Explicitly out of scope

- [RV.139] (the client never asking for rates) and [RV.135]'s feed. Assume rates may never arrive.
- Converting anything at today's rate to fill a gap - hard rule 3, and [RV.88]'s defect.
- The Log divider itself, which [RV.106] already fixed. Reuse it, do not re-fix it.
- `unitPriceHistory` / the price sparkline, which already returns nil for a pending entry.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> Money, and Recalculation on edit (hard rule 2).
2. `docs/ERRORS.md` -> Home, F9 (the rate-pending footnote and its next step).
3. `docs/DESIGN.md` -> the vitals tile and Trends.
4. `CLAUDE.md` hard rules 2, 3, 5, 6, 7, 10.

**Extend the docs in the same change** where this adds behaviour the docs do not describe - the
Trends chart's gap rule belongs in `docs/DESIGN.md` (or `docs/ERRORS.md` -> Trends, whichever owns
it); a doc left stale is an unfinished task.

## Checks

Baseline on `main` as left: **1671 tests / 186 suites**, **777** localization keys at 100% RU,
`swift build` 0, `swiftlint lint` 0 errors **from the repo ROOT**. **Re-measure yourself and report
what you observe** - do not copy these numbers into your report.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then **exactly these UI suites by name**:
   `-only-testing:TankbookUITests/HomeRV106UITests`,
   `-only-testing:TankbookUITests/HomeRV111UITests`,
   `-only-testing:TankbookUITests/TrendsUITests`, and
   `-only-testing:TankbookUITests/GarageUITests` (it renders `VehicleVitals`).
   **Report the observed test count for each and check it is non-zero** - a filter matching nothing
   prints "0 tests ... passed" and still exits 0. This has happened twice in the last week.
5. The localization gate - exit 0; report the key count and the RU percentage.
6. Release build (`xcodebuild -configuration Release ... build`) only if you touch a `#if DEBUG`
   seam. `HomeTestSeed` is one. Say which applies and run it if it does.

Verify by **exit code** (`echo $?`), not by skimming output, and report the codes you observed.

### Tests you must add

- **L1**: a month whose money-bearing rows are **all** pending is reported as `.pending` by
  `HomeStats` and yields **no point** from either Trends series.
- **L1**: a mixed month is `.partial` from `HomeStats` with `amount` equal to the exact sum of the
  known figures and the correct `pendingCount`, and yields **no point** from either Trends series.
- **L1**: a fully converted month is `.complete` and its figure is unchanged **to the cent** on all
  three surfaces - this is the regression guard.
- **L1**: `HomeStats`, `TrendsStats` and `LogStream` classify the **same** month identically. Write
  this one against a fixture containing a purchase group and an S2 duplicate pair, so the shared
  accumulator's single-count invariants (hard rule 4, docs/SYNC.md S2) are asserted through the new
  seam rather than assumed.
- **L4**: the Home vitals tile and the Trends chart with a pending month.
  `-seedHomeRV106Pending` (`RV106HomeTestSeed.seedPending`) already produces exactly this state -
  reuse it rather than writing a new seed, and pass `-homeResetDatabase` with it (seeds are
  idempotent and silently do nothing on a populated database).

### Vacuous traps, named

- **Fixing Home and leaving Trends** - that is precisely how this shape survived [RV.106]. Both
  Trends series, not just `monthlySpendSeries`.
- Asserting the number **changed** without asserting it is **MARKED** as partial or absent.
- A fixture with **no** pending rows, which passes against today's code. Before you change
  anything, run your new tests against the CURRENT code and show they fail; report both outcomes.
- Omitting the Trends point but letting the renderer draw a straight line across the gap.
- Summing a pending row as zero anywhere new, including in the accessibility label.
- Changing `monthSpend` to nil for a partial month - that hides a figure the app legitimately knows,
  and the divider already proved partial is printable.

## Screenshots

Two screens, **EN and RU**, **dark** theme, captured **outside** any running test (`simctl` and
`xcodebuild test` fight over the device): the Home vitals tile and the Trends chart, both in the
pending state. Commit to `design/screenshots/` as `RV.112-home.png`, `RV.112-home-ru.png`,
`RV.112-trends.png`, `RV.112-trends-ru.png`.
RU:
`xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
RU strings run 20-30% longer and short ones expand worst - if the partial marker or the pending
phrase truncates in the tile, that is a defect to fix, not a screenshot to ship.
**You cannot see your own screenshots** - the orchestrator opens every one. Do not assert they are
correct; state what you captured and how.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent** and
any sibling whose brief mentions xcodebuild. Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## This brief's diagnosis is a hypothesis - confirm it before you change anything

The line numbers above were read on the tree as left; verify them. If the shared-classifier shape
turns out to be wrong - if the three call sites genuinely cannot share one accumulator - **report
that with the reason** rather than forcing the extraction. A negative reported honestly is worth
more than a green run on a wrong shape.

## Report back

Every check with the **exit code you observed** and the **observed** test counts per suite; whether
each new test was **run or only written**; the before-and-after of the tests you wrote against the
current code; what the Trends renderer did with the gap; and any defect you found and did not fix.

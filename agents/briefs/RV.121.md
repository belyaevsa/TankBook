# RV.121 - the anomaly card guesses causes it cannot know

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.

## The objection, in the product owner's own words (2026-09-07)

> "don't think that calculating and showing anomalies on average consumption means something
> (besides budget) ... I can drive 1000 km a day, I can stay at a point with the engine running
> for 40 minutes in the winter - this all affects my consumption. And we can't say anything about
> it as we don't know what has happened."

## The cause is pinned. Do not spend the run rediscovering it.

`ios/App/Sources/Home/AnomalyInsightCard.swift:123` renders `L10n.anomalyCauses`, defined at
`ios/App/Sources/Localization/L10n.swift:584-588`:

```swift
static var anomalyCauses: String {
    localize("Likely causes: tire pressure, air filter, winter")
}
```

RU value at `ios/App/Sources/Localizable.xcstrings:6412-6425`:
`"Вероятные причины: давление в шинах, воздушный фильтр, зима"`.

**That line is a causal claim the app has no evidence for.** The app cannot see a motorway week,
an idling hour, a tow, a roof box or a different driver. Naming three plausible causes makes a
guess look like a diagnosis. The *engine* is sound; the **presentation** overclaims.

## Design questions ALREADY CLOSED - do not reopen, do not redesign

1. **The card stays a card on Home.** It is not moved to the Log's month divider - that is
   [RV.119], a separate row.
2. **The engine is not removed and its windows do not change.** The rolling-90-day vs
   seasonally-aligned-baseline model is a decided architecture (`docs/SCHEMA.md` -> ANOMALY,
   `CLAUDE.md` -> decisions already made). `AnomalyEngine.detect` keeps its shape.
3. **"Monthly granularity" is ALREADY IMPLEMENTED and you must not rebuild it.**
   `AnomalyCause` (`ios/Sources/TankbookCore/Consumption/AnomalyEngine.swift:22-43`) is keyed on
   `evaluatedYear` + `evaluatedMonth`, precisely so the verdict survives a recompute a few days
   later inside the same window. Read those lines and confirm it, then leave it alone.
4. **The percent headline stays.** `anomalyTitle(percent:)` and `anomalyCaption(rolling:baseline:)`
   are *measurements*, falsifiable to the reader, and they are not the defect. Keep both.

## What to build

### A. Delete the causes line, completely

- Remove `L10n.anomalyCauses` and its doc comment.
- Remove the `Text(L10n.anomalyCauses)` block and the `homeAnomalyCauses` accessibility identifier
  from `AnomalyInsightCard.swift:122-127`.
- Remove the string entry (EN **and** RU) from `ios/App/Sources/Localizable.xcstrings`.
- Remove or rewrite every test that asserts `homeAnomalyCauses` exists. Search
  `ios/App/UITests/AnomalyInsightUITests.swift` and the whole repo for `anomalyCauses` and
  `homeAnomalyCauses` and leave **zero** references.

### B. Replace it with the reading a private owner actually has: the money

The card's expanded evidence gains one line where the causes line was: **what the drift costs per
month at the user's own recent prices.**

**The arithmetic lives in `TankbookCore`, never in the view** (hard rule 2, and
`AnomalyInsight.swift`'s own comment says the view does no arithmetic). Add to `AnomalyEngine`:

```swift
/// The extra fuel spend per month the drift represents, at the user's own most
/// recent unit price. `nil` when no price is known - the card then shows no
/// money line rather than a zero.
public static func monthlyCostDelta(anomaly: ConsumptionAnomaly,
                                    segments: [Segment],
                                    unitPrice: Decimal?) -> Decimal?
```

- Extra litres per month = `(rollingValue - baselineValue) / 100 * monthlyDistanceKm`.
- `monthlyDistanceKm` = total distance of the segments inside `anomaly.rollingWindow`, divided by
  `Double(rollingWindowDays) / 30.44`. Use the window the anomaly reports, not a re-derived one.
- `unitPrice` is the **most recent** `FillUp.unitPrice` inside the rolling window, in the vehicle's
  `homeCurrency`. Hard rule 3: money is a pair - the amount you render is the **home-currency**
  one, and you must not mix a foreign original into it.
- **Return `nil`, never `0`, when there is no price, no distance, or a non-positive delta.** A
  missing price is a missing line, not a free month. This is the hard rule 13 shape: a value the
  app cannot know is not invented.
- The app-side wiring belongs in `ios/App/Sources/Home/AnomalyInsight.swift`, which already builds
  the segments; do not duplicate the segment construction anywhere else.

**The string is one full localised phrase per language, never concatenation.** This is a standing
scar: `"%@ spend"` composed in RU as `"%@ расходы"` rendered "АВГУСТ РАСХОДЫ", word-order nonsense
(`CLAUDE.md` -> Conventions). Add to `L10n.swift`, with EN and RU in `Localizable.xcstrings`:

- EN: `"About %1$@ more per month at today's prices"`
- RU: `"Примерно на %1$@ в месяц больше по текущим ценам"`

Give it accessibility identifier `homeAnomalyCost`. Render it with the same
`.font(.caption)` / `Theme.Palette.inkSoft` treatment the deleted line had - **no new colour**, and
no ad-hoc hex (hard rule 5). It must not scream: the product owner's word.

### C. Derive the threshold, and WRITE DOWN the derivation

`AnomalyEngine.minimumRelativeDrift = 0.12` (`AnomalyEngine.swift:194`) has a comment claiming it
is "the upper end of docs/SCHEMA.md's +10-12% and exactly J9's +12%" - that is a **citation, not a
derivation**. Nothing records why 12% is the right band for a real car's 90-day rolling value.

There is real data on this machine: **`Spike/ImportFixtures/drivvo/drivvo-ru-3sections.csv`**, the
product owner's own history, 250 refuelling rows. It is **gitignored pending the owner's validation
of its anonymisation - READ IT, DO NOT COMMIT IT, and do not remove its `.gitignore` line.**

Do this:

1. Write a throwaway script (put it in `/private/tmp/claude-501/-Users-sbelyaev-repos-fuel-counter-ios/a5918dd1-31c0-421f-be44-490e7cdbfea7/scratchpad/`, not in the repo) that reads the
   `##Refuelling` section and computes the **90-day rolling distance-weighted L/100km series** the
   engine would see - not the per-fill values. Per-fill spread is much wider than a 90-day mean and
   using it would justify a far too high threshold; that mistake is the trap here.
2. Report the series' mean and standard deviation, and how many times a 12% band would have fired
   over that history.
3. **Keep 0.12 if the data supports it, change it if it does not** - and either way replace the
   comment at `AnomalyEngine.swift:188-194` with the derivation: the measured spread, the rule
   ("the threshold is N sigma of the 90-day rolling series"), and a pointer to the doc.
4. Record the same derivation in `docs/SCHEMA.md` under ANOMALY (line ~494). The doc is the
   authority; the code comment names the rule and links it. Do **not** copy the measured numbers
   into the code comment - `CLAUDE.md` -> "Code comments: current truth only" forbids mutable
   measurements in comments.

For context: the owner's per-fill spread is 4.973-10.989 L/100km around a 6.827 mean. That is
per-fill. **Compute the rolling series yourself; do not reason from those three numbers.**

## Explicitly out of scope

- [RV.119] (the Log's month divider), [RV.118] (the coverage line), [RV.122], [RV.124].
- Changing `rollingWindowDays`, `baselineLagDays`, `minimumSegmentsPerWindow` or the dismissal flow.
- Any new colour, icon or layout beyond swapping one line for another.
- Committing the Drivvo fixture, or touching `.gitignore`.

## Docs to read before writing (in order)

1. `CLAUDE.md` - hard rules 2, 3, 5, 7, 10, 13; and "Code comments: current truth only".
2. `docs/SCHEMA.md` -> Derived: consumption -> ANOMALY (**the authority for this task**).
3. `docs/JOURNEYS.md` -> J9.
4. `docs/DESIGN.md` -> the palette tokens, only if you touch styling.
5. `docs/VISION.md` -> "What we will not tell a driver" (added 2026-09-07 for this row).

## Checks - name the numbers, and run them

Baseline on the tree you were handed: **iOS 1618 tests / 181 suites**, lint **0**, localization
gate **0** (770 keys, 100% RU).

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` **from the repo ROOT** - exit **0**. The `excluded:` paths are root-relative;
   running it from `ios/` gives a wrong answer.
3. `cd ios && swift test` - the full unit suite, **never subsetted**. It must be **>= 1618** and
   must not fall. Report the observed number.
4. `xcodegen generate` then the UI suite **you touched, by name**:
   `-only-testing:TankbookUITests/AnomalyInsightUITests`. Report the observed test count and
   **check it is non-zero** - a filter matching nothing prints "0 tests ... passed".
5. The localization gate - exit 0, and the key count drops by exactly 1 net (one removed, one
   added, so **770 stays 770**; say what you observe).
6. Release build: **not required** - this row touches no `#if DEBUG` seam. Say so in your report
   rather than skipping silently.

### Tests you must add

- **L1 (TankbookCore)**: a rise inside the band produces **no** anomaly; a rise above it does.
  Assert `minimumRelativeDrift` **against the stated rule** (the N-sigma derivation), not against
  itself - `#expect(minimumRelativeDrift == 0.12)` is a vacuous test and is the exact trap this row
  exists to avoid.
- **L1**: `monthlyCostDelta` returns `nil` with no unit price, `nil` for a non-positive delta, and
  a correct value for a hand-computed fixture. Compute the expected number by hand in the test, do
  not call the function to produce its own expectation.
- **L1**: a repo-wide grep asserts **no user-facing string asserts a CAUSE** - assert the causes
  phrasing is absent from `Localizable.xcstrings` in **both** EN and RU.
- **L4 (UI)**: the expanded card shows no causes line, shows the cost line when a price exists, and
  is dismissible and non-blocking.

### Vacuous traps, named

- **Retuning 0.12 without recording why** - that is how 0.12 got there in the first place.
- **Keeping the causes line and softening its wording** - "possible factors", "this can be caused
  by" - the same claim in a quieter voice. The line goes.
- **Asserting the card renders** rather than that it no longer diagnoses.
- **Asserting a string key exists** rather than what it says.
- Deriving the threshold from per-fill spread instead of the 90-day rolling series.

## Screenshots

Capture the Home screen with the anomaly card **expanded**, dark theme, EN and RU:
`design/screenshots/RV.121-home-anomaly.png` and `RV.121-home-anomaly-ru.png`.

- Pass `-homeResetDatabase` alongside the seed - seeds are idempotent and silently do nothing on a
  populated database.
- RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
- Take them **outside** a test run - `simctl` and `xcodebuild test` fight over the device.
- **OCR your own capture and read the text back** before reporting it. A previous row committed a
  screenshot showing the exact opposite of its claim because it was taken before the form settled.
- RU is where this breaks: the cost phrase is long and Russian runs 20-30% longer. If it truncates,
  fix the layout, do not shorten the Russian.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **you** and any
other running agent. Use `pgrep -x xcodebuild`. Never `pkill -f`.

## Report back

Exact numbers for every check above, each with the **exit code you observed**, and state plainly
**whether each test was run or only written**. If you conclude any part of this brief is wrong,
say so and stop at that point rather than absorbing it - four of the orchestrator's diagnoses have
been wrong and every one was caught by an agent pushing back.

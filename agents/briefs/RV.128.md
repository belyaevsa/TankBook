# RV.128 - a multi-car import shows every row in one car's distance unit

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.

## The defect, pinned

`ios/App/Sources/Import/ImportFlowModel.swift:120` defines `distanceUnit(for:)` **specifically so
each row of a multi-car import renders in its own destination car's unit**. It has **zero
references anywhere in the repository** - measured 2026-09-07.

`ios/App/Sources/Import/ImportReviewView.swift:266-270` passes the single global instead:

```swift
ImportOdometerCell(fill: fill, sourceRow: row.sourceRow,
                   distanceUnit: model.distanceUnit,      // :268 - the GLOBAL, not the row's car
```

The helper's own comment credits **[RV.86]** ("a multi-car file's rows can land in cars with
different units") and it already falls back to the global when the row's vehicle cannot be resolved -
so the fallback question below is answered in the code; confirm it rather than re-deriving it.
Multi-car import is the part that did not follow through to the view: a review mixing a
km car and a miles car labels **every** odometer with whichever unit the model happens to hold, so
the user confirms a number under the wrong unit - and hard rule 13 says they are confirming a
default input they are expected to check.

The helper exists, is correct, and is bypassed. That is the shape this project keeps finding: a
right answer sitting beside the code that does not call it.

## Design questions ALREADY CLOSED

1. **Pass the per-row unit at the call site.** `model.distanceUnit(for: row)`. The fix is one
   argument; do not redesign the cell, the model, or the row type.
2. **The value of this row is the TEST, not the fix.** A unit test of `distanceUnit(for:)` passes
   **today**, against the broken screen, and proves nothing. The check that matters is an
   integration test over a **two-car import with different units**.
3. **Do not delete the helper and inline its logic.** It is the tested seam; use it.

## What to build

- The one-argument change at `ImportReviewView.swift:268`, plus any sibling cell in the review or
  preview surfaces that takes a distance unit. **Audit them**: the compiler flagged one unused
  declaration, not every wrong call site. Report what you found, including "nothing else".
- Check whether the **row's destination car can be unset** at review time and what
  `distanceUnit(for:)` returns then. Say what you found and make the fallback deliberate rather
  than incidental.

## Explicitly out of scope

- [RV.126] (the Confirm screen's odometer conflict unit) - different file, different mechanism.
- [RV.116] (the unsupported-column notice) and [RV.113] (the Drivvo importer). **[RV.113] may have
  just changed this area - `git log` before you start and build on what is there.**
- Volume or currency units. This row is distance only.

## Docs to read before writing

1. `CLAUDE.md` - hard rules 10 and 13.
2. `docs/SCHEMA.md` -> units on the vehicle.
3. `docs/JOURNEYS.md` -> J2/F6, the import review.

## Checks

Baseline: **iOS 1631 tests / 181 suites** (one pre-existing failure, `RV.125`'s confident-wrong
total in the Vision-gated `RV.56` suite - **not yours, do not fix it**), `swift build` 0,
`swiftlint` 0 errors **from the repo ROOT**, localization gate 0 (771 keys, 100% RU). **Re-measure
the baseline yourself** - [RV.113] landed shortly before you and may have moved these numbers.

1. `cd ios && swift build` - 0.
2. `swiftlint lint` from the **repo ROOT** - 0. Root-relative `excluded:` paths.
3. `cd ios && swift test` - full, never subsetted; report the number and the only-permitted failure.
4. `xcodegen generate` + the import UI suites **by name** (`ImportCarsUITests` and any other you
   touch); report a non-zero observed count.
5. Localization gate - 0; the key count should be unchanged unless you add copy.
6. Release build - required only for a `#if DEBUG` seam. Say which applies.

### Tests you must add

- **L4, the row's whole point**: a **two-car import, one km and one miles**, labels each row with
  its own car's unit. Assert both rows in one test, so a fix that swaps the global for a different
  global cannot pass.
- **L1**: `distanceUnit(for:)`'s behaviour for a row whose destination car is unset.

### Vacuous traps, named

- **Unit-testing `distanceUnit(for:)` alone** - it passes today and says nothing about the screen.
- **Testing a single-car import**, where the global and the per-row unit agree and any code passes.
- Asserting the argument is passed rather than what the row renders.
- Asserting the cell exists rather than reading its unit label.

## Screenshots

The import review of a two-car, mixed-unit import, dark, EN and RU:
`design/screenshots/RV.128-import-review.png` and `-ru.png`. Pass the reset flag with the seed.
RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
Take them **outside** a test run, and **OCR your own capture** - both units must be visible in one
shot, or the screenshot does not show the fix.

## Never `pgrep -f` for a build process

Your brief is part of your command line. Use `pgrep -x xcodebuild`. Never `pkill -f`.

## Report back

Every check with the **exit code you observed**, whether each test was **run or only written**, the
sibling call-site audit, and what an unset destination car yields. Name any closed decision you
think is wrong and stop there.

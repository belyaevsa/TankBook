# RV.126 - an odometer conflict tells a miles driver about kilometres

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.

## The defect, pinned - and it is shipping on TestFlight

`ios/App/Sources/ConfirmManual/ManualFillUpFormState.swift:252-258`:

```swift
let unit = L10n.distanceUnit(distanceUnit)          // :252 - computed, NEVER used
switch flag.detail {
case .order(let previousOdometer, let previousDate, _, _):
    if let previousOdometer, let previousDate, odo <= previousOdometer {
        let day = previousDate.formatted(.dateTime.month(.abbreviated).day())
        let quote = String(format: L10n.localize("%@ already recorded %@ km."),   // :257 - "km" HARDCODED
                           day, OdometerFormat.grouped(previousOdometer))
```

The function already receives the vehicle's `distanceUnit` and computes the right label into `unit`,
then throws it away and hardcodes `km`. **A miles-configured car is told about kilometres**, in the
one message whose entire job is to make the user trust a number they are about to correct.

**Both languages are wrong, not just English.** `Localizable.xcstrings:174-190`:

- en: `"%@ already recorded %@ km."`
- ru: `"«%@» уже зафиксирован пробег %@ км."`

The unused local is only what the compiler could see. The wrong unit is the defect.

## Design questions ALREADY CLOSED - do not reopen

1. **One full localised sentence PER UNIT, not a `%@` unit placeholder.** Add a second key for
   miles and pick between them, e.g. `"%@ already recorded %@ km."` and
   `"%@ already recorded %@ mi."`, each with its own RU value.
   **Why, and do not substitute the "obvious" fix**: `L10n.distanceUnit(.mi)` returns `"миль"` in
   RU (`Localizable.xcstrings:13414-13428`) - a **genitive plural**, correct after a number but not
   in every frame - while `"км"` is indeclinable. Interpolating a unit token into a translated stem
   is exactly the concatenation hard rule 10 forbids, and it is the scar this project already
   carries: `"%@ spend"` composed in RU as `"%@ расходы"` rendered "АВГУСТ РАСХОДЫ".
   Two full sentences cost one extra key and cannot be got wrong.
2. **`L10n.distanceUnit` stays as it is.** It is correct and used elsewhere. Do not change it, and
   do not "fix" this by finding a way to consume `unit` - if the chosen design leaves `unit` unused,
   **delete the local**; silencing the warning by using it is the trap.
3. **Scope is this message and its siblings in this file only.** Do not sweep the whole catalogue.

## What to build

- Give the conflict sentence a per-unit form, chosen from `distanceUnit`, with EN and RU values for
  each. `OdometerFormat.grouped` stays the number formatter.
- **Audit the sibling messages in this file for the same shape** before you finish. The compiler
  flagged one line; check whether any other user-facing string in
  `ManualFillUpFormState.swift` (and the `.pace` branch's messages wherever they are rendered)
  bakes in a unit. Report what you found, including "nothing else".

## Explicitly out of scope

- [RV.128] (the multi-car import unit) - a different file, a different mechanism, its own row.
- Any other unused-declaration finding ([RV.130] owns the mechanical sweep).
- Changing `DistanceUnit`, `OdometerFormat`, or the timeline-flag engine.

## Docs to read before writing

1. `CLAUDE.md` - hard rules 7, 10, 13, and the code-comment rule.
2. `docs/ERRORS.md` -> the Confirm screen's odometer conflict row (**the authority for the copy**).
3. `docs/DESIGN.md` -> units are typographically subordinate, if you touch rendering.

## Checks

Baseline: **iOS 1631 tests / 181 suites** (one pre-existing failure, `RV.125`'s confident-wrong
total in the Vision-gated `RV.56` suite - **not yours, do not try to fix it**), `swift build` 0,
`swiftlint` 0 errors **from the repo ROOT**, localization gate 0 (771 keys, 100% RU).

1. `cd ios && swift build` - 0.
2. `swiftlint lint` from the **repo ROOT** - 0. Root-relative `excluded:` paths.
3. `cd ios && swift test` - full, never subsetted. **>= 1631**, and the ONLY failure may be the
   `RV.56` one named above. Report the number.
4. `xcodegen generate` + the UI suite you touched **by name**; report a non-zero observed count.
5. Localization gate - 0, 100% RU, report the key count (it should rise by the keys you add).
6. Release build not required unless you touch a `#if DEBUG` seam. Say which applies.

### Tests you must add

- **L1**: a **miles** vehicle's conflict message names miles; a **km** vehicle's names km. Assert
  the **rendered string**, not that the unit was computed.
- **L1**: the **RU** rendering of both, asserted as strings.
- **L4**: the message appears on Confirm for a miles car.

### Vacuous traps, named

- **Silencing the unused-variable warning by using `unit` in a log or a debug string.**
- Asserting `distanceUnit` is passed rather than what the user reads.
- Fixing EN and leaving RU with a baked-in unit.
- Interpolating `L10n.distanceUnit(...)` into the translated sentence - see closed decision 1.
- Asserting a catalogue key exists rather than what it renders.

## Screenshots

The Confirm screen showing the conflict on a **miles** car, dark, EN and RU:
`design/screenshots/RV.126-confirm-conflict.png` and `-ru.png`. Pass the reset flag with the seed.
RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
Take them **outside** a test run, and **OCR your own capture and read the text back** - a committed
screenshot has twice shown the opposite of its row's claim.

## Never `pgrep -f` for a build process

Your brief is part of your command line. Use `pgrep -x xcodebuild`. Never `pkill -f`.

## Report back

Every check with the **exit code you observed**, whether each test was **run or only written**, and
what the sibling-message audit found. Name any closed decision you think is wrong and stop there.

---

## RESUMING - the fix is ALREADY DONE (2026-09-08)

A previous run was killed mid-task. **The code change is complete and correct; judge it on its
merits, do not redo it.** What exists in the working tree:

- `OdometerConflict.quote(day:odometer:distanceUnit:)` in `ManualFillUpFormState.swift`, switching
  on the unit and returning one full localised sentence per unit.
- The unused `let unit = L10n.distanceUnit(distanceUnit)` local is **removed**, not consumed.
- `Localizable.xcstrings` has the new `"%@ already recorded %@ mi."` key, EN
  `"%@ already recorded %@ mi."` and RU `"«%@» уже зафиксирован пробег %@ миль."` (genitive plural,
  correct after a number).

**What remains, and it is the half the row is judged on:**

1. **The tests.** None were committed. All four from the check list above are still owed - the
   miles rendering, the km rendering, both in **RU**, and the L4. The previous run was mid-way
   through `ios/Tests/LocalizationGateTests/LocalizationGateP53Tests.swift` when it stopped; look
   there first and finish or replace what you find.
2. **The sibling audit.** Report whether any other user-facing string in this file (and the
   `.pace` branch's messages) bakes in a unit. Say "nothing else" if that is the answer.
3. **The screenshots**, EN and RU, per the section above.
4. **Re-run every gate.** The baseline has moved: `main` is now green at **1642 tests / 183
   suites**, 773 keys. Re-measure and report what you observe; adding one key should make it 774.

If you find the inherited code wrong, say so and fix it - a resumed run that rubber-stamps what it
inherited is the failure mode this note exists to prevent.

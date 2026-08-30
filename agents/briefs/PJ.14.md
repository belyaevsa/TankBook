# Task PJ.14 - the live "+N km since last" caption

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 2, row 12.** Named in `VISION.md:63`'s MVP fill-up row and drawn in `DESIGN.md:67`; the
caption today is the static placeholder.

## Where you may write

```
ios/App/Sources/ConfirmManual/**
ios/App/Sources/Localization/L10n.swift · ios/App/Sources/Localizable.xcstrings
ios/Sources/TankbookCore/Domain/**         (the delta value type)
ios/Tests/TankbookCoreTests/**
ios/Tests/LocalizationGateTests/**
ios/App/UITests/ConfirmManualUITests.swift
scripts/capture-screenshots.sh
docs/DESIGN.md · docs/JOURNEYS.md
```

**Do not** touch `Capture/**`, `ServiceEntry/**`, `Import/**`, `Settings/**`, `SignIn/**`,
`Welcome/**`, `Home/**`, `Reminders/**`, `Rates/**`, `Sync/**`, `Config/**`, `backend/`, `site/`,
`Spike/`, `project.yml`. **Do not commit. Do not tick `docs/TASKS.md`.**

## Verified immediately before dispatch

`ManualFillUpSections.swift:398` carries the static artboard placeholder:

```swift
var caption: LocalizedStringKey? = "last known · update after typing fuel"
```

`Vehicle.paceLimitKmPerDay` exists (`Entities.swift:55`, default 1500) and `TimelineValidator`
already uses it, so the pace rule is defined - the caption just does not consult it.

## What to build

A **live** caption under the odometer, derived from the last known value as the user types:

- typed **>** last: `+N km since last`
- typed **=** last: the equal case - say what you chose and why
- typed **<** last: `warn`, because the odometer went backwards
- typed such that the implied daily rate exceeds `vehicle.paceLimitKmPerDay`: `warn`

**Amber is attention, never alarm** (hard rule 5: `warn` for attention, red only inside system
dialogs). And this caption **must never block the save** - an implausible odometer warns and the
user decides (hard rule 13); `TimelineValidator` already flags it on save, which is a separate
thing from this caption.

**Put the delta and its state in core as a value.** There is no app unit-test target, so a caption
computed inside the view can only be reached by XCUITest, which asserts behaviour and never values -
the P3.7 lesson. The L1 below is only possible if the decision lives in core.

## Russian - the trap this row walks into by name

The row itself says: **"RU as one composed phrase, never concatenated."** `docs/LOCALIZATION.md` is
the authority and this project has shipped this bug twice:

- `"%@ spend"` composed as «%@ расходы» rendered **"АВГУСТ РАСХОДЫ"**, word-order nonsense.
- «с вашего %1$@» rendered **"с вашего телефон Android"** - a `%@` receiving runtime data must not
  sit inside a phrase that governs its case.

`+N km since last` is a **plural** carrying runtime data. RU needs one/few/many; the edges are
**11 and 21**, and note **1 and 21 both take `one`**, so a few/many error is invisible at 21 -
assert **1, 2, 5, 11, 21**. And `Text(_: String)` does **not** localise: an interpolated `String`
renders its English key while the gate reports zero violations. That blind spot has shipped **six**
times here.

## Explicitly out of scope

`TimelineValidator`'s save-time flagging (PJ.11, landed) · making `paceLimitKmPerDay` editable
(**PJ.45**, deferred) · the capture pipeline · `docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 1021 today (verified). MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L1**: the delta text and state for typed **>**, **=**, **<** last, and the **pace flag** - four
  cases, asserted as values.
- **L1**: the plural renders correctly at **1, 2, 5, 11, 21** in EN and RU.
- **L4 `ConfirmManualUITests`**: the caption **updates live** as the odometer is typed, and the save
  is never blocked by it.

Run only `-only-testing:TankbookUITests/ConfirmManualUITests` and **report the observed count**.
**A selector matching nothing prints "0 tests ... passed" and exits 0.** Note two tests in that
suite are documented as **device-specific** (`HANDOVER.md`) and fail on `iPhone 17 Pro` while
passing on `iPhone 17` - run on **iPhone 17**, and if they flake, say so rather than chasing them.
**Never `pgrep -f`** for a build; use `pgrep -x xcodebuild`.

## Mutations you must run and report

1. Return the static placeholder again. The live-update L4 must fail.
2. Drop the `warn` state for a **backwards** odometer, leaving it neutral. A test must fail.
3. Ignore `paceLimitKmPerDay`. A test must fail - if not, the pace half is unasserted.
4. Swap the RU `few`/`many` forms. Report **which numbers move** - expect 2, 5 and 11, not 21.

A mutation that does not fail is a finding. One that does not **compile** proves nothing and must be
redone. Use a **heredoc**, anchor on the **code line** not a comment, and confirm `BUILD: 0` before
believing any result - four mutations misapplied that way today.

## Screenshots

EN **and** RU, dark: the Confirm sheet with the live caption showing a **positive** delta, and one
showing the **warn** state. Name them `PJ.14-odometer-delta{,-ru}.png` and
`PJ.14-odometer-warn{,-ru}.png`, register them in `scripts/capture-screenshots.sh`, capture
**outside** a test run.

**The caption must be in frame.** Four captures of this very sheet were deleted in P5.2b because the
card sat below the fold (P6.9), and two more this week for showing a seeded state instead of the
real one. Nine deletions total on this project.

## Report back

Every command with its **real exit code** and observed counts; all four mutation results **with the
suites you ran** and the plural numbers that moved; what you chose for the **equal** case and why;
the files changed; and anything in this brief that is wrong.

En-dashes only, never em-dashes.

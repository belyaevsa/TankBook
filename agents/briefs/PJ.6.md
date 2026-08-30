# Task PJ.6 - "Type it" opens the form for the mode you are in

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 2, row 16** - and a **hard rule 15** bug. Typing is a peer entry path, not a fallback; a
"Type it" that ignores the mode the user selected sends them to the wrong form and makes the typed
door worse than the scanned one.

## Where you may write

```
ios/App/Sources/Capture/**
ios/App/Sources/Navigation/**
ios/App/UITests/CaptureUITests.swift
ios/Tests/TankbookCoreTests/**
scripts/capture-screenshots.sh
docs/JOURNEYS.md · docs/SCREENMAP.md
```

**Do not** touch `ConfirmManual/**` beyond what presenting an existing sheet requires,
`ServiceEntry/**` internals, `Import/**`, `Settings/**`, `SignIn/**`, `Welcome/**`, `Home/**`,
`Reminders/**` (PJ.4/PJ.5 just landed), `TankbookCore/Extraction/**`, `Sync/**`, `Config/**`,
`backend/`, `site/`, `Spike/`, `project.yml`.
**Do not commit. Do not tick `docs/TASKS.md`.**

## Verified immediately before dispatch

`CaptureMode` has **four** cases (`TankbookCore/Domain/CaptureMode.swift:10-13`): `fillUpAuto`,
`charge`, `service`, `expense`. The capture screen tracks the selected one
(`CaptureView.swift:25`) and offers only the ones the powertrain allows
(`CaptureMode.modes(for:)`).

**"Type it" ignores all of it.** Both call sites set the same sheet:

```
CaptureView.swift:257   activeSheet = .manualForm      (the permission-denied card's "Type it")
CaptureView.swift:394   activeSheet = .manualForm      (the main "Type it" affordance)
```

So selecting **Service** and typing gives you a fill-up form.

## What to build

"Type it" opens the form for the **current mode**: Service -> ServiceEntry, Expense -> ExpenseEntry,
Fill-up -> ManualFillUp.

**`charge` is the fourth case and the row does not mention it.** Decide deliberately and say which
you did in the report: either route it to the charge form if one exists, or leave it on the fill-up
form **and say why**. Do not silently treat four cases as three - a switch that looks complete over
an enum whose cases are not all handled is the P6.20 shape, and this project has already shipped it
once. **PJ.12 covers the dead Charge chip for EV/PHEV** and is a separate row, so do not build the
charge form here; just be explicit about what the fourth case does.

**Both call sites**, not only the main one. The permission-denied card's "Type it" (`:257`) is the
F8 escape - the one a user reaches when the camera is refused - and sending *them* to the wrong form
is worse, not better.

## Explicitly out of scope

The dead Charge chip (**PJ.12**) · the capture pipeline (PJ.1, landed) · any form's internals ·
`docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 1015 today (verified). MUST rise if you add core logic.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L4 `CaptureUITests`**: per mode, the sheet that opens is asserted **by identifier** - Service
  opens the service form, Expense the expense form, Fill-up the fill-up form. Assert the identifier
  of the sheet, not that *a* sheet appeared.
- **L4**: the permission-denied card's "Type it" obeys the mode too.
- **L1**: if you put the mode -> form mapping in core as a value (recommended - there is no app
  unit-test target, so app-side logic can only be reached by XCUITest), pin it there including the
  fourth case.

Run only `-only-testing:TankbookUITests/CaptureUITests` and **report the observed count** (21 at
last measurement). **A selector matching nothing prints "0 tests ... passed" and exits 0.**
**Never `pgrep -f`** for a build; use `pgrep -x xcodebuild`.

## Mutations you must run and report

1. Send every mode to `.manualForm` again. The per-mode test must fail **for at least two modes** -
   if only one fails, the others are unasserted.
2. Make the permission-denied "Type it" ignore the mode while the main one obeys. A test must fail.
3. Drop the fourth case from whatever mapping you write. It must not compile, or a test must fail -
   report which. A silently-unhandled case is the defect P6.20 was filed for.

A mutation that does not fail is a finding. One that does not **compile** proves nothing and must be
redone. Use a **heredoc**, **anchor on the code line rather than a phrase that also occurs in a
comment**, and confirm `BUILD: 0` before believing any result - three mutations misapplied that way
today.

## Screenshots

EN **and** RU, dark: the capture screen in **Service** mode with the service form open from
"Type it". Name them `PJ.6-typeit-service{,-ru}.png`, register them in
`scripts/capture-screenshots.sh`, capture **outside** a test run, and **check the form in frame is
the service one**, not the fill-up form.

## Report back

Every command with its **real exit code** and the observed `CaptureUITests` count; all three
mutation results **with the suites you ran**; **what you decided for `charge` and why**; the files
changed; and anything in this brief that is wrong - eleven agent pushbacks here have been correct.

En-dashes only, never em-dashes.

# Task PJ.12 - the dead Charge chip

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 2, row 16.** Narrow, but an EV user meets it on their first capture.

## Where you may write

```
ios/Sources/TankbookCore/Domain/CaptureMode.swift
ios/App/Sources/Capture/**
ios/Tests/TankbookCoreTests/**
ios/App/UITests/CaptureUITests.swift
docs/JOURNEYS.md · docs/VISION.md
```

**Do not** touch `ConfirmManual/**`, `ServiceEntry/**`, `Import/**`, `Settings/**`, `SignIn/**`,
`Welcome/**`, `Home/**`, `Reminders/**`, `Rates/**` (PJ.8 just landed), `Sync/**`, `Config/**`,
`backend/`, `site/`, `Spike/`, `project.yml`.
**Do not commit. Do not tick `docs/TASKS.md`.**

## Verified immediately before dispatch - and it is worse than the row says

```swift
// TankbookCore/Domain/CaptureMode.swift:34-40
case .ev:   return [.charge, .service, .expense]
case .phev: return [.fillUpAuto, .charge, .service, .expense]
```

`.charge` is offered, and **`defaultMode(for:)` returns the first mode**, so an **EV user lands on
`.charge` by default**. The shutter behind it is decorative for charging, and since PJ.6 landed,
"Type it" in that mode opens the **fill-up form** - a petrol form, for a car with no fuel tank. No
production code constructs a `ChargeSession`; only test seeds do.

## The decision, already made by the project - do not relitigate it

`docs/TASKS.md` -> Launch triage states plainly that **EV charging (J6) stays out of v1**. So:
**hide the chip**, do not build a charge entry form. That is the scope-consistent half of the row's
"hide it, or ship a minimal typed entry".

## What to build

1. **`.charge` is not offered** while no charge entry exists. An EV's modes become
   `[.service, .expense]` and PHEV's `[.fillUpAuto, .service, .expense]`, and `defaultMode` follows.
2. **The enum case stays** - `ChargeSession` is a real entity elsewhere in the app. What changes is
   what the capture screen *offers*. Removing a case that other code constructs would be a larger,
   worse change.
3. **Leave a single, findable marker** naming the row that restores it, so this is a deliberate
   deferral rather than a silent gap. One comment at the decision point, not a scattering.

## The honest question this creates - report on it, do not fix it here

With `.charge` hidden, **an EV user has no primary logging path at all** on the capture screen -
only Service and Expense. That follows from the triage decision, but it is worth naming rather than
discovering later. In your report, say **exactly what an EV user's capture screen shows afterwards**,
and whether anything else in the app still promises EV charging it cannot deliver (`VISION.md`
claims "EV charging is a first-class citizen"). **Do not change `VISION.md`'s claim yourself** -
report it; it is a product-owner call, and W6 is the precedent for how that gets handled.

## Explicitly out of scope

A charge entry form · `ChargeSession` anywhere else · the capture pipeline · `docs/TASKS.md` ·
committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 1019 today (verified). MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L1**: `modes(for:)` offers no `.charge` for **either** `.ev` or `.phev`, and `defaultMode` for
  an EV is a mode that actually works. Assert both powertrains - PHEV is the one an
  ICE-shaped fix forgets.
- **L4 `CaptureUITests`**: an EV seed shows **no dead mode**.

Run only `-only-testing:TankbookUITests/CaptureUITests` and **report the observed count** (25 at
last measurement). **A selector matching nothing prints "0 tests ... passed" and exits 0.**
**Never `pgrep -f`** for a build; use `pgrep -x xcodebuild`.

## Mutations you must run and report

1. Offer `.charge` to `.ev` again. The L1 and the L4 must fail.
2. Fix `.ev` but leave `.phev` offering it. A test must fail - if not, PHEV is unasserted, which is
   exactly the case a fix aimed at "the EV bug" drops.

A mutation that does not fail is a finding. One that does not **compile** proves nothing and must be
redone. Use a **heredoc**, anchor on the **code line** not a comment, and confirm `BUILD: 0` before
believing any result.

## Screenshots

EN **and** RU, dark: the capture screen for an **EV** seed, showing the offered modes. Name them
`PJ.12-capture-ev{,-ru}.png`, register them in `scripts/capture-screenshots.sh`, capture **outside**
a test run, and **check the chip row is in frame** so the absence is actually visible.

## Report back

Every command with its **real exit code** and the observed `CaptureUITests` count; both mutation
results; **what an EV user's capture screen shows afterwards**; anything still promising EV charging;
the files changed; and anything in this brief that is wrong.

En-dashes only, never em-dashes.

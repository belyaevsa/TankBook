# Task PJ.4 - Reminders reachable in a Release build

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 2, row 15.** P3.4 is ticked and **the screen cannot be reached in a shipping build.**

## Where you may write

```
ios/App/Sources/Home/**
ios/App/Sources/Reminders/**
ios/App/Sources/Garage/**            (the VehicleDetail reminders row)
ios/App/Sources/Navigation/**
ios/App/Sources/Localization/L10n.swift · ios/App/Sources/Localizable.xcstrings
ios/Sources/TankbookCore/Reminders/**
ios/Tests/TankbookCoreTests/**
ios/App/UITests/HomeUITests.swift · RemindersUITests.swift · AnomalyInsightUITests.swift
scripts/capture-screenshots.sh
docs/SCREENMAP.md · docs/JOURNEYS.md
```

**Do not** touch `Capture/**`, `ConfirmManual/**`, `Import/**`, `Settings/**`, `SignIn/**`,
`Welcome/**` (PJ.3 just landed), `TankbookCore/Sync/**`, `Config/**`, `backend/`, `site/`,
`Spike/`, `project.yml`. **Do not commit. Do not tick `docs/TASKS.md`.**

## Verified immediately before dispatch - and it is worse than the row says

The **only** navigation to `Route.reminders` is a Home banner (`HomeBanners.swift:66`), and that
banner is gated on a DEBUG launch argument:

```swift
// HomePresentation.swift:35
reminderDue: arguments.contains("-forceReminderDue"))
```

So in a Release build **there is no route to the screen at all**. And the banner does not render a
reminder - it renders a **hardcoded sentence**:

```swift
Text("Insurance renews in 12 days")
```

That is a fixture pretending to be data. No `VehicleDetail` reminders row exists either
(`SCREENMAP.md:132` lists one).

## What to build

1. **The banner derives from real reminders** - `ReminderLifecycle.derivedStatus` over
   `liveReminders` - and its text is the actual due reminder, not a constant. **No stored flag**:
   the state is derived, and it changes when a reminder completes (hard rule 2's spirit - derived,
   never stored).
2. **Retire `-forceReminderDue`.** It exists because production could not reach the state; once the
   banner is real, it can. Three test call sites use it today.
3. **The `VehicleDetail` reminders row** from `SCREENMAP.md:132`, so the screen has a second door
   that does not depend on something being due.
4. The banner is **attention, not alarm**: `warn` amber is correct, red is for system dialogs only
   (hard rule 5), and it must name its next step (hard rule 7).

**The interpolated-string trap.** A due-in-N-days sentence is a **plural** and carries runtime data.
`docs/LOCALIZATION.md`: RU needs one/few/many, the edges are **11 and 21**, and note **1 and 21 both
take `one`**, so a few/many error is invisible at 21 - assert 1, 2, 5, 11, 21. And `Text(_: String)`
does **not** localise: an interpolated `String` renders its English key while the gate reports zero
violations. That blind spot has shipped **six** times on this project.

## Explicitly out of scope

Notification tap routing (**PJ.5** - the very next row, so stay out of `NotificationDelegate`) ·
reminders in Recently deleted (**PJ.7**) · the capture pipeline · `docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 1000 today (verified). MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L1**: the banner state is **derived**, and it changes when a reminder completes. No stored flag.
- **L1**: the due-in-N-days plural renders correctly at **1, 2, 5, 11, 21** in EN and RU.
- **L4 `HomeUITests` + `RemindersUITests`**: a seeded due reminder produces the banner, and the
  banner reaches the list - **with no `-route` and no `-forceReminderDue` argument**.
- **L4**: the `VehicleDetail` row reaches the same screen.

Run only the suites you touched with `-only-testing:` and **report the observed count for each**.
**A selector matching nothing prints "0 tests ... passed" and exits 0** - it has caught the
orchestrator three times, so read the count. **Never `pgrep -f`** for a build; use
`pgrep -x xcodebuild`, never `pkill -f`.

## Mutations you must run and report

1. Hardcode the banner text again. A test must fail - if none does, the test asserts the banner
   exists rather than what it says, which is the defect this row is fixing.
2. Make the banner ignore completion, so it stays after the reminder is done. A test must fail.
3. Re-add `-forceReminderDue` as the only way to show the banner. The de-fixtured test must fail.
4. Swap the RU `few`/`many` plural forms. Report **which numbers move** - it should be 2, 5 and 11,
   not 21.

A mutation that does not fail is a finding. One that does not **compile** proves nothing and must be
redone. Use a **heredoc**, and when replacing a string that also appears in a comment, **anchor on
the code line** - a bounded replace hit a doc comment instead of the call site earlier today.

## Screenshots

EN **and** RU, dark: Home with the real reminder banner, and the reminders list reached from it.
Name them `PJ.4-home-reminder{,-ru}.png` and `PJ.4-reminders{,-ru}.png`, register them in
`scripts/capture-screenshots.sh`, and capture **outside** a test run.

**Check the banner text is a real reminder in the image**, not the old constant. Eight captures have
been deleted rather than committed here for not showing their subject.

## Report back

Every command with its **real exit code** and observed counts; all four mutation results **with the
suites you ran** and the plural numbers that moved; whether any `-forceReminderDue` call site
resisted removal; the files changed; and anything in this brief that is wrong - eleven agent
pushbacks here have been correct.

En-dashes only, never em-dashes.

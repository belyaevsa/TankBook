# Task PJ.5 - a tapped notification goes where it promised

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 2, row 15's second half** (PJ.4 landed in the previous commit). `SCREENMAP.md:176` marks the
deep link **done** and it does not exist.

## Where you may write

```
ios/App/Sources/Reminders/ReminderNotificationCoordinator.swift
ios/App/Sources/Navigation/**
ios/Sources/TankbookCore/Service/**        (the identifier -> route value type)
ios/Tests/TankbookCoreTests/**
ios/App/UITests/RemindersUITests.swift · TrendsUITests.swift
scripts/capture-screenshots.sh
docs/SCREENMAP.md · docs/NOTIFICATIONS.md
```

**Do not** touch `Capture/**`, `ConfirmManual/**`, `Import/**`, `Settings/**`, `SignIn/**`,
`Welcome/**`, `Home/**` (PJ.4 just landed there), `TankbookCore/Sync/**`, `Config/**`, `backend/`,
`site/`, `Spike/`, `project.yml`. **Do not commit. Do not tick `docs/TASKS.md`.**

## Verified immediately before dispatch

`NotificationDelegate` (`ReminderNotificationCoordinator.swift:100`) implements **`willPresent`
only**. There is **no `didReceive`**, so tapping a notification opens the app wherever it happened
to be - the reminder that fired is never shown. `NOTIFICATIONS.md:23` and `SCREENMAP.md:176` both
describe a deep link that has never existed.

The identifiers are already stable and parseable (`ReminderNotification.swift:60-61`):

```
reminder.<uuid>.<kind>
monthly-summary.*        (MonthlySummaryNotification)
```

## What to build

1. **`didReceive`** on the delegate: `reminder.<id>.<kind>` routes to **Reminders with that
   reminder's completion sheet reachable**; `monthly-summary.*` routes to **Trends**.
2. **The mapping is a pure value type in core**, not logic inside the delegate. There is **no app
   unit-test target**, so anything in `ios/App` can only be reached by XCUITest, which asserts
   behaviour and never values - this is the P3.7 lesson (`TabBarMetrics`), and it is the difference
   between an L1 that pins the mapping and no test at all.
3. **An unknown or malformed identifier must be inert** - open the app normally, never crash, never
   route somewhere arbitrary. A notification is attacker-adjacent input in the sense that it can be
   stale: a reminder deleted since it was scheduled must not produce a dead end (hard rule 7).
4. **A DEBUG hook that replays a response**, so the L4 tests can drive a tap without a real
   notification.

## Explicitly out of scope

Scheduling, cancellation, permission timing (P3.6, shipped) · silent APNs (**PR.20**) · the
reminders list UI itself (PJ.4, landed) · `docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 1010 today (verified). MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L1**: the identifier -> route mapping, including `monthly-summary`, an **unknown** identifier,
  and a **malformed** one (no dots, a bad UUID). Assert the routes, not that a function returns.
- **L4 `RemindersUITests`**: replaying a reminder response lands on Reminders with that reminder's
  completion sheet reachable.
- **L4 `TrendsUITests`**: replaying a monthly-summary response lands on Trends.

Run only those two suites with `-only-testing:` and **report the observed count for each**.
**A selector matching nothing prints "0 tests ... passed" and exits 0** - it has caught the
orchestrator three times, so read the count. **Never `pgrep -f`** for a build; use
`pgrep -x xcodebuild`.

## Mutations you must run and report

1. Route every identifier to Reminders. The monthly-summary test must fail.
2. Route an unknown identifier somewhere instead of nowhere. That test must fail.
3. Drop the reminder id from the route so Reminders opens without the right reminder. A test must
   fail - if none does, the test asserts the screen and not which reminder it carries.

A mutation that does not fail is a finding. One that does not **compile** proves nothing and must be
redone. Use a **heredoc**, and **anchor on the code line, not a phrase that also appears in a
comment** - a bounded replace hit a doc comment earlier today, and another anchored on a symbol the
agent had refactored away. Confirm `BUILD: 0` before believing any mutation result.

## Screenshots

EN **and** RU, dark: Reminders reached from a replayed reminder tap, and Trends reached from a
replayed monthly-summary tap. Name them `PJ.5-reminder-tap{,-ru}.png` and
`PJ.5-summary-tap{,-ru}.png`, register them in `scripts/capture-screenshots.sh`, capture **outside**
a test run, and **check the destination screen is what is actually in frame**.

## Report back

Every command with its **real exit code** and observed counts; all three mutation results **with the
suites you ran**; where you put the mapping and why; the files changed; and anything in this brief
that is wrong - eleven agent pushbacks here have been correct, several on stale line numbers.

En-dashes only, never em-dashes.

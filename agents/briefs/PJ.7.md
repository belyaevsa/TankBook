# Task PJ.7 - reminders are tombstoned, and the alert says otherwise

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 2, row 24.** A **hard rule 8** bug: nothing is lost silently, tombstones plus 30-day undo.

## TWO OTHER AGENTS ARE RUNNING

- **PJ.3b** holds `design/screens/`, `ios/App/Sources/Welcome/`, `WelcomeUITests`.
- **PJ.47** holds `docs/JOURNEYS.md` and `docs/ERRORS.md`.

**Use `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`** so you do not fight PJ.3b for the
device. Two known **device-specific** families (`AddVehicle`, `ConfirmManual`) fail on some
simulators; neither is in your suites, and if you see them they are not yours. **Name the simulator
in every result.**

**`ios/App/Sources/Localizable.xcstrings` is also open to PJ.3b.** Add only your own keys, and
**re-read the file immediately before writing it** - a read-modify-write over a stale copy silently
drops the other agent's keys. That file is not line-mergeable (`HANDOVER.md`).

## Where you may write

```
ios/App/Sources/Reminders/**
ios/App/Sources/RecentlyDeleted/**
ios/Sources/TankbookCore/Service/**
ios/Sources/TankbookCore/Persistence/**
ios/App/Sources/Localization/L10n.swift · ios/App/Sources/Localizable.xcstrings
ios/Tests/TankbookCoreTests/**
ios/App/UITests/RecentlyDeletedUITests.swift · RemindersUITests.swift
scripts/capture-screenshots.sh
```

**Do not** touch `docs/JOURNEYS.md`, `docs/ERRORS.md`, `design/`, `Welcome/`, `Capture/**`,
`ConfirmManual/**`, `Import/**`, `Settings/**`, `backend/`, `site/`, `Spike/`, `project.yml`.
**Do not commit. Do not tick `docs/TASKS.md`.**

## The defect, verified - and the row understates it

The app **contradicts itself across two screens**:

```
RemindersView.swift:102        "Deleted reminders are gone – this can't be undone."
RecentlyDeletedView.swift:199  "Anything you delete stays here for 30 days, in case you change your mind."
```

**The alert is the one that is wrong.** `Reminder` carries `deletedAt` (`Entities.swift:404`) and
`confirmDelete` calls **`softDeleteReminder`** (`RemindersView.swift:177`, `Repository.swift:268`).
The row is tombstoned exactly like every other entity - so the data is **recoverable and
unreachable**, because `RecentlyDeletedView` lists `FillUp`, `ChargeSession` and the rest, and never
a `Reminder`.

So this is not "add a feature". It is: **the undo already exists, the user is told it does not, and
the one screen that would let them use it does not show it.**

## What to build

1. **Reminders appear in Recently deleted, with Restore.** A restored reminder **keeps its status
   and its recurrence** - restoring a repeating reminder as a one-off would lose the thing that made
   it useful.
2. **The alert states the 30-day truth** and stops claiming the delete is permanent. Keep it a
   confirmation, not a warning: deleting is reversible, so the copy should be calm.
3. EN **and** RU. If a count appears ("N days left"), it is a plural: RU needs one/few/many, the
   edges are **11 and 21**, and **1 and 21 both take `one`**, so a few/many error is invisible at 21.

## Explicitly out of scope

The reminder lifecycle, scheduling and notifications (P3.6, PJ.4, PJ.5 - all landed) · the retention
window itself (**PR.21**, one constant per tier, deferred) · `docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 1057 today. MUST rise. NOTE: PJ.3b may move this - report what you see.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build ; echo "app build: $?"
```

- **L1**: tombstone -> restore **keeps status and recurrence**. Assert both fields, not that the row
  came back.
- **L4 `RecentlyDeletedUITests`**: a deleted reminder is listed and restores.
- **L4 `RemindersUITests`**: the alert no longer claims the delete is permanent.

Run only those two suites with `-only-testing:` and **report the observed count for each and the
simulator**. **A selector matching nothing prints "0 tests ... passed" and exits 0.**
**Never `pgrep -f`** for a build - it matches other agents' briefs and has killed one; use
`pgrep -x xcodebuild`, never `pkill -f`.

## Mutations you must run and report

1. Restore the reminder **without** its recurrence. A test must fail - if not, restore is asserted
   as "a row exists" and a repeating reminder silently comes back as one-off.
2. Put "this can't be undone" back in the alert. A test must fail.
3. Filter reminders out of the Recently deleted list again. A test must fail.

A mutation that does not fail is a finding. One that does not **compile** proves nothing. Use a
**heredoc**, anchor on the code line rather than a phrase that also appears in a comment, and
confirm `BUILD: 0` before believing any result - six mutations were misapplied that way this session.

## Screenshots

EN **and** RU, dark: Recently deleted showing a deleted reminder with Restore, and the corrected
delete alert. Name them `PJ.7-deleted-reminder{,-ru}.png` and `PJ.7-delete-alert{,-ru}.png`,
register them in `scripts/capture-screenshots.sh`, capture **outside** a test run.

**Check the subject is in frame.** Twelve captures have been deleted rather than committed here for
missing theirs - one showed a toggle in the opposite state to the invariant it illustrated.

## Report back

Every command with its **real exit code**, observed counts **and the simulator**; all three mutation
results; whether the string catalogue still holds PJ.3b's keys after your write; the files changed;
and anything in this brief that is wrong.

En-dashes only, never em-dashes.

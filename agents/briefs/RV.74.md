# RV.74 - a reminder notification must land on the car it belongs to

**This row is v1** (unmarked in `docs/TASKS.md`), unlike the rest of the reminders series. It is a
correctness bug on a path a TestFlight reviewer reaches by tapping a notification.

## The defect, diagnosed to a line

`NotificationDelegate` resolves a tapped notification to `.openRemindersFor(id)` and `TabRoots.drive`
(`ios/App/Sources/Navigation/TabRoots.swift:428-437`) does exactly two things: switch to the Log tab
and push `.reminderDeepLink(id)`. **It never changes the selected car.**

`RemindersView` then loads through `AppCarSelection.selectedVehicle` and
`liveReminders(forVehicle:)` (`RemindersView.swift:355-370`). When the tapped reminder belongs to a
car that is not the selected one, **the reminder is simply not in the loaded list**, so the screen
takes its documented branch for a reminder that no longer exists and renders the plain list -
"a stale tap is a landing, not a dead end" (`RemindersView.swift:20-25`).

That branch is correct for a **deleted** reminder and wrong here: the reminder exists, it is due,
the user tapped it, and the app silently showed them **a different car's list**. Every multi-car
user hits this.

**The reminder id is the fact; the selected car is not.** Do not "trust the tap" in the other
direction either - resolve the id, and let the resolved vehicle decide.

## What to build

1. **A repository read that resolves a reminder by id across vehicles.** None exists -
   `Repository.swift:280` is per-vehicle only. Keep it minimal and live-row-only (tombstoned rows
   are not resolvable). **If `RV.75`'s cross-vehicle query has already landed when you start, reuse
   it and do not add a second** - check before you write.
2. **Select that reminder's car before pushing**, and say in a doc comment WHERE the switch belongs -
   a router that switches, or a Reminders screen that scopes to the deep-linked reminder's own
   vehicle. Pick one, justify it, and do not leave both half-wired.
3. **The user must be able to see the car changed.** The Reminders screen names the car; do not
   switch silently with nothing on screen saying so.
4. **Keep the genuine stale case working**: a deleted reminder still lands on a plain list, never an
   error, never a detour (hard rule 7, and `NotificationRouter.swift:27-36` records the reasoning).

## Explicitly out of scope

The merged all-cars list (`RV.75`), the permanent entry point (`RV.76`), notification actions
(`RV.78`). Any change to what notifications are scheduled. The completion sheet's own behaviour.

## Tests

L1: resolving a reminder id returns its vehicle; a tombstoned reminder resolves to nothing.
L4 `RemindersDeepLinkUITests` (new): **two seeded cars**, car A selected, replay a notification for a
reminder on car B (`-replayNotificationResponse`, see `ReminderTestSeed.swift`) - the completion flow
for THAT reminder surfaces and the app is on car B.
L4: replaying an identifier for a deleted reminder still lands on the plain list.
Suites to run: `RemindersDeepLinkUITests`, `RemindersUITests`.

### Vacuous traps, named
- Asserting the Reminders screen appeared. **It already does today - it is the wrong car's.**
- Seeding **one** car: the bug cannot exist there, and the test passes against the live defect.
- Asserting the deep-link route was set, rather than what the screen then shows.

### Mutations (run, report, restore byte-for-byte)
1. Drop the car switch, keep the push -> the two-car L4 test must fail.
2. Resolve the id but ignore the resolved vehicle -> same test must fail.
3. Make the deleted-reminder path error instead of landing -> the stale-tap test must fail.

## Screenshots

`RV.74-reminders-deeplink.png` / `-ru.png`: the landing after a deep link with two cars, showing
which car it is.

## Docs to reconcile

`docs/SCREENMAP.md` (the deep-link edge now carries a car switch) and `docs/JOURNEYS.md` J7d if the
landing changes. Screen reference: `design/screens/RemindersAll.dc.html` is where this lands once
RV.75 exists; until then it is the per-car list on the resolved car.
## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and within it only:
`ios/Sources/TankbookCore/**`, `ios/App/Sources/**`, `ios/Tests/**`, `ios/App/UITests/**`, the docs
named in this brief, and `design/screenshots/**`.

**Never move, rename or delete a file you did not create.** A second Claude session works in this
checkout and there is a git worktree under `.claude/worktrees/`. Expect files, and even a red test,
that are not yours: **report them and carry on** - never "clean the baseline".
Do NOT tick anything in `docs/TASKS.md` - the orchestrator ticks at merge. Do NOT commit.
No `git add -A`, `git checkout`, `git stash`, `git clean`.

## The reminders code as it stands (verified 2026-09-05, use these, do not re-derive)

- **Core lifecycle, all pure, all L1-testable**: `ios/Sources/TankbookCore/Service/ReminderLifecycle.swift`
  (`derivedStatus`, `isActive`, `due`, `dueSortKey`, `complete`, `reschedule`, `makeReminder`),
  `ReminderBanner.swift`, `ReminderCompletion.swift`, `ReminderNotification.swift`.
  **`.attention` is derived at read time; only the transition is stored** so notifications fire
  once. Terminal rows (`.done`/`.dismissed`) never re-derive. Do not duplicate any of this.
- **The only repository query is per-vehicle**: `liveReminders(forVehicle:)`,
  `ios/Sources/TankbookCore/Persistence/Repository.swift:280`.
- **The screen scopes to the selected car**: `ios/App/Sources/Reminders/RemindersView.swift`, load
  at `:355-370` via `AppCarSelection.selectedVehicle`, then
  `notificationCoordinator.reconcile(vehicleId:)`.
- **The deep link**: `NotificationDelegate.userNotificationCenter(_:didReceive:)`
  (`ios/App/Sources/Reminders/ReminderNotificationCoordinator.swift:136-147`) ->
  `NotificationRouteParser.resolve(identifier:)` -> `NotificationRouter.Request.openRemindersFor`
  (`ios/App/Sources/Navigation/NotificationRouter.swift:17-37`) -> `TabRoots.drive`
  (`ios/App/Sources/Navigation/TabRoots.swift:428-437`).
- **The Home banner**: `ReminderBanner.bannerReminder` (one row, `.attention` only) rendered by
  `ios/App/Sources/Home/HomeBanners.swift:64-82`, whose "View" is a `NavigationLink(value: Route.reminders)`.
- `ReminderCategory` is `ios/Sources/TankbookCore/Domain/Enums.swift:146-159` (note `.other(String)`).
- Seeds: `ios/App/Sources/Reminders/ReminderTestSeed.swift`; UI suite `RemindersUITests`.

## Hard rules that decide things in this area

**2** (stats/counts are DERIVED, never stored) · **5** (amber is attention; colour is never the only
channel) · **7** (every error and every dead end names its next step) · **10** (all strings through
the String Catalog, EN + RU, full localised phrases - never concatenation) · **12** (never log a
domain value; ids, counts and codes only) · **13** (the app suggests, the user decides - every
derived value is editable at the moment it is offered and again afterwards) · **14** (it builds and
it lints before anything else counts).

## The baseline gate (CLAUDE.md rule 14)

From the **repo ROOT**, judged by exit code (`echo $?`), never by skimming output:
- `cd ios && swift build` -> 0
- `cd ios && swift test` -> 0, count reported. **Read the current count yourself before you start**
  and report before -> after; other rows are landing in parallel, so any number quoted in a brief is
  stale by the time you run.
- `swiftlint lint` **from the repo root** -> 0 errors. From `ios/` it prints thousands of phantom
  violations; that false red has cost two sessions.
- the localization gate **from the repo root** -> 0, run exactly:
  `swift run --package-path ios localization-gate --sources ios/App/Sources --catalogue ios/App/Sources/Localizable.xcstrings`
  (measured on this checkout 2026-09-06: 716 keys, 100% RU, 0 missing, 0 violations)
- `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:<the suites this brief names> test` -> 0.
  `swift build` does NOT compile `ios/App`; only `xcodebuild` does. Run `xcodegen generate` first if
  you added a file. **Check the observed count is non-zero** - a filter matching nothing prints
  "0 tests ... passed". Do NOT run the whole UI suite (2026-08-29 rule).
- **Never `pgrep -f` for a build** - your own brief is in your command line and you will match, and
  could kill, a sibling agent. Use `pgrep -x xcodebuild`.
- **Echo the exit code from the COMMAND, never through a pipe.** A pipe reports the LAST stage's
  status, so a failing build behind `| tail` reports 0 - redirect to a file and read that instead.

## Screenshots

EN **and** RU, **dark**, into `design/screenshots/`, named as this brief says.
- Capture **outside** a test run - `simctl` and `xcodebuild test` fight over the device.
- RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
- **Verify every EN/RU pair differs: `md5 -q a.png b.png`**, and report the hashes. RV.58 shipped an
  "RU" shot byte-identical to its EN one and could not tell.
- A `-` prefixed launch argument can **persist across relaunches**; reinstall between shots when a
  seeded state sticks (RV.64).
- **RU is not a formality.** Russian runs 20-30% longer and short strings expand worst. Read the
  rendered Russian for grammar and word order, not just overflow. **And check every action line
  actually renders in RU**: RV.80 is an action that appears in EN and silently does not in RU, found
  only by looking.
- You cannot see your own screenshots. The orchestrator opens all of them; do not claim they look right.

## Report back

1. Exit code of every gate, and observed test counts (before -> after).
2. Each mutation: what you broke, which named test failed, that you restored it byte-for-byte.
   **A mutation that PASSES is a finding** - say so rather than moving on. That has happened twice
   today and both times the test, not the code, was the problem.
3. Screenshot paths and md5s.
4. What the user can now do that they could not before. If the honest answer for some case is
   "nothing changed", say so.
5. Anything in this brief that was wrong. A fence can be wrong the same way a diagnosis can (RV.70):
   report it as a Residual rather than obeying quietly.
6. Whether the tests were actually **run**, not only written.

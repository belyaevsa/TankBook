# RV.78 [v1.1] - a fired reminder must be actionable from the notification

**Independent of RV.75/76/79.**

## The gap

There is **no `UNNotificationAction` anywhere in the app** - verify with a grep before you start.
The banner has no Complete and no Snooze, so the only way to push a due date is: open the app, find
the car, find the reminder, open the sheet, choose Reschedule.

`docs/JOURNEYS.md` J7c says **"snoozing beats ignoring"** - and today snoozing costs four taps more
than ignoring, which decides which one a user picks at a red light.

The delegate that would receive the response already exists and already handles the plain tap:
`ios/App/Sources/Reminders/ReminderNotificationCoordinator.swift:114-147`, routing through
`NotificationRouteParser.resolve(identifier:)` and `NotificationRouter`.

## What to build

1. **Register a notification category with two actions** - mark it done, and push it - at launch,
   and attach the category to the scheduled requests.
2. **Handle the response on the existing delegate path**, and route it through the **same lifecycle
   the screen uses**. Completion is not a second implementation: `ReminderLifecycle.complete` /
   `reschedule` own the transitions, and rescheduling re-arms the notification through the planner
   that already exists.
3. **Say what Snooze means** in days or kilometres, and write it in `docs/NOTIFICATIONS.md`, which
   is the authority for this area. The artboard says "Push a week" -
   `design/screens/ReminderNotification.dc.html` (collapsed and expanded).
4. **Complete must not silently skip the cost log.** J7c makes declining first-class, but it has to
   be a **choice the user made**. The artboard's answer: **Mark done opens the completion sheet**
   rather than completing silently. Follow it, or argue in writing for `.done(nil)` - decide and say
   why in a doc comment.
5. A completed reminder must not leave its notification armed.

## Explicitly out of scope

The merged list, the entry point, the counts, the offer-after-save. Silent APNs (`docs/NOTIFICATIONS.md`
covers that separately). Changing when reminders fire.

## Tests

L2: the category is **registered with both actions** at launch.
L4: responding with **Snooze** moves the due date and **re-arms**; responding with **Complete** lands
the reminder in the same state the sheet produces.
L1: the action handler and the sheet call **one** code path.
Suites to run: `RemindersUITests`, plus whichever new suite you add for the response replay
(`ReminderTestSeed.swift` already has the notification-replay seam - reuse it, do not invent one).

### Vacuous traps, named
- Asserting the actions are **registered** without exercising a response. Registration is the easy
  half and proves nothing about behaviour.
- A Complete that marks done and **leaves the notification armed** - assert the disarm.
- Asserting the handler was called rather than the reminder's resulting state.

### Mutations (run, report, restore)
1. Implement Complete as its own transition instead of calling the lifecycle -> the one-code-path L1
   test must fail.
2. Snooze without re-arming -> the re-arm assertion must fail.
3. Register the category without attaching it to the scheduled request -> the L2 test must fail.

## Screenshots

`RV.78-reminder-notification.png` / `-ru.png` - the **expanded** banner with both actions. Notification
banners are captured from the simulator's own presentation; if you cannot stage one reliably, say so
plainly rather than shipping a screenshot of something else. **RU action titles truncate first** -
"Отметить выполненным" is nearly three times "Mark done", so check it fits.

## Docs to reconcile

`docs/NOTIFICATIONS.md` (**the authority**: the actions, and what Snooze means in days or km),
`docs/JOURNEYS.md` J7c, `docs/SCREENMAP.md` if the action opens a screen.
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
- the localization gate **from the repo root** -> 0
- `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:<the suites this brief names> test` -> 0.
  `swift build` does NOT compile `ios/App`; only `xcodebuild` does. Run `xcodegen generate` first if
  you added a file. **Check the observed count is non-zero** - a filter matching nothing prints
  "0 tests ... passed". Do NOT run the whole UI suite (2026-08-29 rule).
- **Never `pgrep -f` for a build** - your own brief is in your command line and you will match, and
  could kill, a sibling agent. Use `pgrep -x xcodebuild`.

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

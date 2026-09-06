# RV.81 - archiving a car strips its reminders

**Product-owner decision, 2026-09-06: "archived cars strips the reminders."** The decision is made;
this row implements it. Do not re-derive whether it is right.

## The state today

- Archiving is `VehicleDetailView.toggleArchive`; it sets `Vehicle.archived` and touches nothing else.
- The reminder rows stay active and `ReminderNotificationCoordinator` keeps whatever it armed, so
  **a sold car can still fire a banner** for work nobody will do.
- The screens already agree with the decision and the notifications do not: `RV.75`'s
  `liveRemindersAcrossVehicles` excludes archived cars, and so do `RV.79`'s counts. **That split is
  the worst case** - the one surface that reaches the user without being opened is the one still
  talking.

## What this changes about RV.74, and you must handle it

`Repository+Reminders.swift`'s `liveReminder(id:)` carries a doc comment justifying why it resolves
an archived car's reminder: *"archive does not cancel armed notifications, so an armed notification
on an archived car is still a tap the user can make."* **That sentence becomes false in this
change.** Rewrite it - do not delete the behaviour. The resolve **stays**, because a notification
already delivered to the system, or one racing the archive, must still land somewhere honest rather
than dead-end (hard rule 7). Say that instead.

## What to build

1. **Cancel the car's armed reminder notifications when it is archived.**
2. **Re-arm them when it is unarchived.** Archiving is reversible, so the reverse direction is not
   optional - a car that comes back must not be silently mute.
3. **Route through the existing planner**, never a second cancellation path. `RV.78` has just
   established that the banner actions and the completion sheet share one lifecycle; arming shares
   the same code for the same reason.
4. **Do not delete or tombstone the reminders.** Archiving is "put it away", not "lose it" (hard
   rule 8), and the rows are the history the Garage row promises with "history preserved".
5. **Decide and write down what an archived car's reminders look like on its own per-car screen**
   (reached from Vehicle detail): visible but inert, or hidden. Make it consistent with the merged
   list already excluding them, and put the reasoning in a doc comment plus `docs/SCHEMA.md` if it
   is a lifecycle statement.

## Explicitly out of scope

The merged list, the counts, the banner actions - all shipped. Deleting reminders. Any change to
what archiving does to entries, stats or sync.

## Tests

L1: archiving a vehicle leaves its reminder **rows** intact - not tombstoned, not dismissed. A test
that asserts deletion is asserting the wrong thing.
L2 (**app-hosted**, the `ios/App/Tests/ReminderNotificationActionTests` precedent - XCUITest cannot
read `UNUserNotificationCenter`): archiving cancels every pending request for that car **and leaves
another car's requests armed**; unarchiving re-arms.
L1: `liveReminder(id:)` still resolves an archived car's reminder.
Suites: the hosted `TankbookTests`, plus `GarageUITests` if the per-car screen changes.

### Vacuous traps, named
- Asserting the reminders vanish from the merged list. **RV.75 already does that and it passes today.**
- Asserting cancellation without asserting the other car's requests survive.
- Testing archive without testing **unarchive** - a one-way fix hides exactly there.

### Mutations (run, report, restore)
1. Cancel every pending request rather than the archived car's -> the other-car assertion must fail.
2. Skip the re-arm on unarchive -> the unarchive test must fail.
3. Tombstone the rows instead of leaving them -> the history test must fail.

## Docs to reconcile

`docs/SCHEMA.md` (the reminder lifecycle statement, if you add one), `docs/NOTIFICATIONS.md` (what
archiving does to armed requests - **the authority for this**), and the `liveReminder(id:)` comment
named above.
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

# RV.79 [v1.1] - a car should say when it has work waiting

**Depends on `RV.75`'s cross-vehicle query.** Without it this is N queries inside a list render. If
RV.75 is not merged when you start, say so and stop.

## The gap

The Garage rows (`ios/App/Sources/Garage/GarageView.swift`) and the car switcher
(`ios/App/Sources/CarSwitcher/CarSwitcherView.swift`) show odometer, consumption and spend. Neither
carries "2 due". So the only way to learn something is waiting is to navigate to the place that
would tell you - and with the Home banner scoped to the selected car, **another car can be overdue
for a month in silence**.

## What to build

1. **A per-car attention count on the Garage row and on the car switcher row**, derived at read time
   from live reminders (hard rule 2 - never stored, never cached in the row model).
2. **Only what `ReminderLifecycle` calls attention.** Do not badge a car whose reminders are merely
   scheduled - that is the difference between a signal and noise.
3. **Colour is not the channel** (hard rule 5). Amber is attention, and **the count must also read
   as text for VoiceOver**: the accessibility label names the number.
4. **The count navigates to the merged list; it never creates.** The row's job is picking a car, and
   a create action there would compete with the count for meaning (2026-09-05 review).
5. Absent entirely when nothing needs attention - `design/screens/GarageReminderCounts.dc.html`.

## Explicitly out of scope

The merged list (`RV.75`), the entry point (`RV.76`), notification actions (`RV.78`). Any change to
what "attention" means.

## Tests

L1: the count equals the attention rows for that vehicle, and **changes when one is completed**.
L4: two cars, one with two due - the badge appears on that row and **not on the other**; the
accessibility label names the count.
Suites to run: `GarageUITests`, `CarSwitcherUITests`.

### Vacuous traps, named
- Asserting a badge **view exists** rather than its number.
- Seeding a scheduled reminder and asserting no badge **only** - assert the positive case too, or a
  badge that never renders passes.
- Reading the count from a seed constant instead of from the seeded reminders.

### Mutations (run, report, restore)
1. Count all active reminders instead of attention-only -> the scheduled-car test must fail.
2. Drop the accessibility label, keep the colour -> the VoiceOver assertion must fail (hard rule 5).
3. Cache the count on first render -> the "changes when one is completed" L1 test must fail.

## Screenshots

`RV.79-garage-counts.png` / `-ru.png` (two cars, one badged) and `RV.79-car-switcher-counts.png` /
`-ru.png`. In RU check the badge does not push the car name into truncation - Russian car metadata
lines are already the longest in the app.

## Docs to reconcile

`docs/SCREENMAP.md` (the count's navigation edge), `docs/DESIGN.md` only if you introduce a badge
treatment that is not already a token.
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

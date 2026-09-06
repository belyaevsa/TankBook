# RV.72 - "needs a look" must stop showing an entry the user has fixed

## The defect, diagnosed to a line

Open the flagged list, fix a record, save it, come back - **the stale row is still there.**
Reported by the product owner 2026-09-05.

`FlaggedEntriesView.load()` (`ios/App/Sources/Settings/FlaggedEntriesView.swift:95-116`) is a
**one-shot**: `guard !didLoad else { return }` at `:96-97`, driven by `.task` at `:72`, which does
not fire again when the screen is revealed by a pop back from Edit entry - the view stays alive in
the NavigationStack. The list is whatever it was when it first appeared.

**The app already has the signal and this screen is the one ignoring it.** Every Edit entry save
bumps `AppToastCenter.revision` (`EditEntryView.swift:328,357,413,440` ->
`Navigation/ToastCenter.swift:31-33`), which is exactly how Home avoids the same staleness (RV.25).
`ToastCenter`'s own doc comment says it: *"an edit that moved nothing visible still changed the
data, and Home must not show stale rows."*

**Worse than a refresh bug**: this list is the resolution surface for sync conflicts (S1-S5, hard
rule 8). A user who fixes a flagged entry and still sees it flagged has no way to tell whether their
fix took - the honest reading is "my correction was lost", which is the one thing hard rule 8
promises never happens. The Settings count and the list can also disagree, because
`AppSyncSurface.refresh()` **does** recompute `flaggedCount` on every appear (`AppSync.swift:345`):
"0 entries need a look" beside a list showing one.

## What to build

1. **Reload on the revision - do not just drop the guard.** Observe `AppToastCenter.revision` and
   reload when it changes (the Home pattern), so a save anywhere - Edit entry, Inbox, Recently
   deleted, a sync merge - refreshes the list. Dropping `didLoad` alone would reload on every
   appearance, still miss an in-place change, and re-query on every scroll-triggered task.
2. **An entry whose conflict is resolved must leave the list, and the empty state must be reachable
   that way.** "Nothing needs a look" after fixing the last flagged entry is the acceptance - not a
   row count.
3. **Audit the siblings, differentiated.** The same `guard !didLoad` shape is in
   `RecentlyDeletedView.swift:337`, `TireSetsView.swift:132`, `VehicleDetailView.swift:324`,
   `CarSwitcherView.swift:251`, `AccountDevicesView.swift:47` and `Destinations.swift:108`. Report
   for each whether it can go stale the same way (a screen the user returns to after changing the
   data behind it) or is correct as a one-shot (a form that must not re-read while being edited).
   **Do not fix them all silently.**

## Explicitly out of scope

The conflict resolution itself, Edit entry's behaviour, the Settings count (it already works).

## Tests

L4 (`FlaggedEntriesUITests` new, or in `SettingsUITests`): seeded flagged entry -> open the list ->
open the entry -> resolve and save -> **back** -> the row is gone **and the empty state shows**.
L1 over whatever the reload is factored into.
Suites: the new/extended flagged suite, plus `SettingsUITests`.

### Vacuous traps, named
- Asserting the list loads at all. It does today.
- Asserting the Settings **count** updates - it already does, and that is the half that works.
- **Re-entering the screen from Settings rather than popping back from Edit entry** - a different
  path, and it would pass against the live bug.

### Mutations (run, report, restore)
1. Keep the revision observation but ignore its value (reload once) -> the pop-back test must fail.
2. Reload on appear instead of on the revision -> say what fails; if nothing does, that is a finding
   about the test, not a licence to ship the weaker fix.

## Screenshots

Only if copy changes.
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

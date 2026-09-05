# RV.76 [v1.1] - Reminders needs a door that is open when nothing is on fire

**Depends on `RV.75`.** A quick view that opens one car's list rebuilds the same gap it was meant to
close. If RV.75 is not merged when you start, say so and stop rather than building against the
per-car screen.

## The gap

The Home banner (`ios/App/Sources/Home/HomeBanners.swift:64-82`) is the **single** one-tap path into
Reminders, and `ReminderBanner.bannerReminder` filters to `.attention` and returns **one** row. So:
when nothing is due there is no path at all, and when two things are due the second is invisible.
Otherwise it is Garage -> car -> Reminders, three taps (`VehicleDetailView.swift:106`), which is also
what creating a reminder costs.

**The screen where a user would PLAN is hardest to reach exactly when they are calm enough to plan**,
and the surface that should say "two things this month" says nothing until one is late.

## What to build

1. **A permanent entry point that carries a count** - `design/screens/RemindersEntry.dc.html` (the
   row, with its count, beside the banner) . Say where it lives and why: a Home header affordance, or
   a Garage-level row above the cars. Decide, justify in a doc comment, do not do both.
2. **The count is the point.** "2 need attention" is what makes the row worth a tap. It is
   **derived at read time** (hard rule 2), never stored, never seeded as a number.
3. **The row is a doorway, not a button**: it navigates and never creates. A `+` there could only
   guess the car (hard rule 13) or open the form car-empty, which is one tap later than the list's
   own card anyway.
4. **Keep the banner.** This replaces nothing; it adds the calm path.
5. **The empty state is the discovery path** (`design/screens/RemindersEmpty.dc.html`) and **its one
   action is FILLED, not the dashed card**: dashed is this app's idiom for "add one more" at the end
   of a populated list (Add car uses it twice), and on an empty screen it reads as an empty slot
   rather than an invitation.

**Do not put it on the tab bar.** The five slots are decided (`docs/DESIGN.md`) and the fifth is
reserved for Ask. **The rejected placements and their arguments are already recorded in
`docs/SCREENMAP.md`** - the tab bar, the Home banner, the Garage row, a second `+` on Vehicle
detail, and the Home header's "Type it" menu. Read them; do not re-litigate them.

## Explicitly out of scope

The merged list itself (`RV.75`), per-car counts on Garage rows (`RV.79`), notification actions.

## Tests

L4: with **nothing due**, the entry point is present and reaches the merged list. (This is the whole
bug - a test that only covers the due case proves nothing.)
L4: with two reminders due **on different cars**, the count reads 2 and the banner still shows the
most urgent.
L1: the count derives from live reminders and is **not persisted anywhere**.
L4: with **no reminders at all**, the empty state renders a **filled** primary action that opens the
form - not the dashed card.
Suites to run: `RemindersEntryUITests` (new), `HomeUITests`, `RemindersUITests`.

### Vacuous traps, named
- Asserting the entry point exists **without the nothing-due case** - that window is the bug.
- Hard-coding the count in a seed instead of deriving it from seeded reminders.
- Asserting the empty state renders without asserting **which** affordance it renders.

### Mutations (run, report, restore)
1. Filter the count to `.attention` on the selected car only -> the two-car count test must fail.
2. Hide the entry point when the count is zero -> the nothing-due test must fail.
3. Swap the empty state's filled action for the dashed card -> the empty-state test must fail.

## Screenshots

`RV.76-reminders-entry.png` / `-ru.png` (the row with a count of 2, beside the banner) and
`RV.76-reminders-empty.png` / `-ru.png` (the empty state with its filled action). **Both states, both
languages** - four files. In RU check the count phrase's plural form (2 needs "напоминания", not
"напоминаний").

## Docs to reconcile

`docs/SCREENMAP.md` (the new edge, and move your chosen placement out of the rejected list with a
line saying it was chosen), `docs/JOURNEYS.md` J7d (the Discover-it row and its second warning).
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

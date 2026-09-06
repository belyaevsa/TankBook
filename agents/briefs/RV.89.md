# RV.89 - the log must say which year

**Product-owner requirement, 2026-09-06:** *"a year must be displayed in the log and at needs a look
entries. For multi-year logs it's impossible to understand the issues. The current year might be
skipped, the previous - show the last 2 numbers."*

## The state today

`HomeFormat.day` (`ios/App/Sources/Home/HomeSections.swift:46-48`):

```swift
static func day(_ date: Date) -> String {
    date.formatted(.dateTime.month(.abbreviated).day())
}
```

"18 Jul", never a year - and it is the formatter behind the log rows, the flagged "needs a look"
list (`FlaggedEntriesView.subtitle`), Recently deleted, Trends and the parts shelf.

**The import made it urgent**: 513 rows spanning a decade all read "3 Jun" / "14 Jun", so a flagged
2015 entry is indistinguishable from a flagged 2026 one and the user cannot tell which year the
problem is in.

**The app already has the right pattern**: `ReminderRowFormat.dateString`
(`ios/App/Sources/Reminders/ReminderRowFormat.swift:98-104`) drops the year inside the current year
and shows it otherwise. This is an inconsistency to remove, not an idea to invent.

## What to build

1. **One formatter**, used by every surface that lists dated entries. Do not fix the log and leave
   the flagged list - that is half the report.
2. **Two digits outside the current year, nothing inside it.**
3. **Get the RU form right.** A two-digit year is not an apostrophe plus digits in every locale -
   use the locale's own convention rather than composing the string yourself. A composed date is the
   P1.4 `"%@ расходы"` trap wearing a different costume (hard rule 10).
4. **Decide about the month dividers** and say why: a log scrolled to 2015 shows "JUNE" with no
   other clue. Check the divider's totals row and Trends for the same gap.

## Explicitly out of scope

Time-of-day (entries carry no time - that is `RV.87`). Changing the sort. The relative phrases
("in 12 days") that `ReminderRowFormat` owns.

## Tests

L1 over the formatter, **against a frozen clock, never `Date()`**: a current-year date renders
without a year; any other year renders with a two-digit one; the 31 Dec / 1 Jan boundary is
asserted explicitly.
L4: a seeded multi-year log shows the year on the older row and not on this year's, **and the
flagged list does the same**.
Suites: `HomeUITests`, plus the flagged-list suite.

### Vacuous traps, named
- **Asserting the string contains "24"** - that matches an odometer, a volume, or a day of the month.
  Assert the rendered date substring, or assert the two dates differ in the expected way.
- Asserting the log only and not the flagged list.
- Testing with `Date()`, so only the current-year branch is ever exercised - which is what makes a
  year bug survive a green suite for a year at a time.

### Mutations (run, report, restore)
1. Always show the year -> the current-year test must fail.
2. Never show it (today's behaviour) -> the older-row test must fail.
3. Use a four-digit year -> the two-digit assertion must fail.

## Screenshots

`RV.89-log-multiyear.png` / `-ru.png`, EN and RU, dark, showing rows from two different years in one
list. Check the RU row does not overflow: the year makes the longest subtitle longer.

## Docs to reconcile

`docs/DESIGN.md` (the date convention for entry rows - it is a visual-language statement).
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

# RV.85 - do not ask for the date format the file already answers

## The defect

`MfmParser.MapRow` increments `ambiguousDates` for every row whose day component is <= 12 -
individually undecidable - and `MfmParser.cs:158-165` raises the `dateFormat` ambiguity whenever that
count is non-zero. **It never asks whether another row in the same file settles it.**

One export has one format. A single `13/05/2024` anywhere proves D/M for every row in the file, and
the parser is holding that row when it asks the user.

**Measured on the owner's export** (`~/Downloads/myfuelmanager/fuel.csv`, 513 rows): **215 rows are
individually ambiguous**, and the file **disambiguates as M/D**. The app asked anyway.

Beyond a wasted tap: the question is the import wizard's one moment of doubt, and asking it when the
answer is on disk teaches the user that the app's questions are noise.

## What to build

1. **Decide the format from the whole file.** A component > 12 in the first position proves D/M; in
   the second, M/D. Apply the proven order to **every** row, including the individually ambiguous
   ones, and **do not ask**.
2. **Two cases need a written decision, and neither may be a silent guess:**
   - **The file proves both orders.** That is not an ambiguity, it is an inconsistent file, and it
     needs its own message rather than a question the user cannot answer correctly.
   - **Nothing disambiguates** (every date has both components <= 12). The product owner said "drop
     it". The reading that costs the user nothing is to drop those **rows** into the review list as
     unresolved rather than guess a format - hard rule 8, nothing lost silently, and the review list
     exists for exactly this. **Confirm that reading in your report before relying on it**, and if
     you cannot, implement the detectable case and leave the undecidable one exactly as it is today.
3. The parser stays a pure function returning candidates (hard rule 9).

## Explicitly out of scope

The multi-car split (`RV.86`), the currency backfill (`RV.88`), same-day ordering (`RV.87`).

## Tests

L1 (backend): a file with one `13/05` row and twenty ambiguous ones resolves **all** of them as D/M
and returns **no** `dateFormat` ambiguity; the mirror case with `05/13` resolves M/D; a file proving
both raises the inconsistent-file error, not a question; a file where nothing disambiguates behaves
as decided.
L4 `ImportUITests`: the date-format question does **not** appear for a detectable file, and the
preview's dates are the resolved ones.

### Vacuous traps, named
- Testing only a file that is already unambiguous row by row.
- Asserting the question is absent **without asserting the dates came out right** - that is the half
  that matters, and a parser that dropped the question and guessed would pass.
- Leaving the client's `dateFormatAnswer` path untested once it stops being reachable in the common
  case - it still has to work for the undecidable file.

### Mutations (run, report, restore)
1. Detect from the first row only rather than the whole file -> the twenty-ambiguous-rows test must fail.
2. Return the ambiguity anyway after detecting -> the "no question" test must fail.

## Docs to reconcile

`docs/API.md` (`/import/parse` ambiguity semantics - **a contract change if the shape moves**),
`docs/ERRORS.md` (the inconsistent-file message, if you add one).
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

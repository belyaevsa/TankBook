# RV.88 - imported money must actually reach the car's currency

## The defect, and the second half is why it never heals

Measured against the owner's export: `fuel.csv` carries `Currency=USD` on every row, the target
car's `homeCurrency` is EUR, and Home shows **"0 €" for every month** beside **"500 entries pending
rates"**.

1. `ImportConversion.makeFill` (`ios/Sources/TankbookCore/Import/ImportConversion.swift:38-46`)
   builds `Money(amount:currency:homeCurrency:)` **with no rate snapshot**, so every foreign-currency
   row lands pending. That much is *correct*: `rateDate` is the entry date (hard rule 3), and a 2015
   rate is not on the device at import time.
2. **`MoneyBackfillService` has no production caller on this path.** Its only two call sites are
   `RateBackfillDebugHook` (DEBUG, `-runRateBackfill`) and
   `ManualFillUpCurrencySupport.runBackfill()` (the confirm-manual flow). Verify that yourself with a
   grep before you start. So an import commits hundreds of pending rows and **nothing ever asks
   anyone to resolve them**.

The spend numbers the app exists to compute stay zero indefinitely.

## What to build

1. **Run the backfill after an import commits**, over the rows it just wrote.
2. **Say what the user sees while it runs, and if it cannot finish.** Hundreds of historical dates
   may need fetching, some a decade old, and offline is legitimate (hard rule 1: parsing is the ONE
   network exception, so everything after it must survive without a connection). "500 entries pending
   rates" is already the honest surface - it must **drain**, and it must name its next step when it
   cannot (hard rule 7).
3. **Do not convert at import time with today's rate.** `rateDate` is the entry date and snapshots
   are immutable (hard rule 3); a 2015 fill converted at a 2026 rate is a wrong number that looks
   right.
4. **Check what the rates service can actually serve** for dates that far back, and say so. If it
   cannot, this row's real answer is what the app says about the rows it cannot resolve - decide it,
   do not leave them silently pending forever.

## Explicitly out of scope

The multi-car split (`RV.86`), the date format (`RV.85`), same-day ordering (`RV.87`). Changing the
rate provider. Backfilling anything the user did not just import.

## Tests

L1: committing an import of foreign-currency candidates leaves rows pending, and running the
backfill resolves them **with each row's own `rateDate`** - never today's.
L1: a row whose rate is unavailable **stays pending and is counted**, never silently zeroed.
L4: after importing a USD file into a EUR car, the month total is not 0 once the backfill has run.
Suites: `ImportUITests`, plus whichever suite covers the rate surfaces.

### Vacuous traps, named
- **Asserting `MoneyBackfillService` in isolation.** It works today and is not the bug - the missing
  CALLER is.
- Testing with a same-currency file, where nothing converts.
- Asserting a pending **count** without asserting a total that stops being zero.
- Freezing the clock so today's rate happens to equal the entry's - the anchoring assertion must
  fail if the code uses `Date()`.

### Mutations (run, report, restore)
1. Backfill with today's date instead of each row's `rateDate` -> the anchoring test must fail.
2. Zero the amount for an unresolvable rate instead of leaving it pending -> its test must fail.

## Docs to reconcile

`docs/SCHEMA.md` (money pair + backfill rules, if the drain changes them), `docs/ERRORS.md` (what
the pending surface says and its next step).
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

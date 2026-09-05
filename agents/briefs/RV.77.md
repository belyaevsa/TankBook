# RV.77 [v1.1] - after the user logs the work, offer the next reminder

**Independent of RV.75/76/79.** It can run before or after them.

## The gap

The maintenance loop closes in one direction only. Reminder -> completion -> entry is fully built:
`ReminderCompleteSheet` hands off to `ExpenseEntryView`, and the next cycle is anchored at the
completion, not the original due date (`ReminderLifecycle` rule 1). **The reverse is missing.** Log
an oil change yourself - which is exactly what a user who did the thing early does - and nothing
offers "remind me in 15 000 km".

`docs/JOURNEYS.md` J7c names this chain as **where competitors leak**: "a reminder marked done with
no record and no follow-up is a dead end - Drivvo's pattern". Half of it is unbuilt.

Everything needed already exists at save time: the **category** is known, and `Reminder.recurrence`
(`everyKm` / `everyMonths`) and `sourceEntryId` are already on the entity.

## What to build

1. **After saving a service or expense record, OFFER the next reminder - never create it.** It is a
   proposal the user accepts, edits or ignores (hard rule 13). Save paths:
   `ios/App/Sources/ServiceEntry/ServiceEntryView.swift:369` and
   `ios/App/Sources/ServiceEntry/ExpenseEntryView.swift:178`.
2. **Pre-fill from the record**: its category, anchored at **that record's** date and odometer -
   never "today", the same anti-drift rule completion already follows.
3. **Say where the interval comes from, and keep it honest.** A curated per-category default is a
   suggestion, not a fact (hard rule 13), and must be **editable in the same breath** - the screen
   shows it as two editable fields (`design/screens/ServiceReminderOffer.dc.html`). Put the defaults
   where `docs/PRACTICES.md` says that kind of constant belongs, and write down why each number is
   what it is. A category with no sensible interval offers nothing at all.
4. **Suppress the offer when a live reminder for that category already exists on that car.** That is
   how a user ends up with three oil reminders.
5. **Never mid-save.** The record saves, **then** the offer appears, and dismissing costs nothing -
   "Not this time" is a peer button, not a dismiss X.

## Explicitly out of scope

Changing the completion flow. The merged list, the entry point, the counts. Reminder scheduling
mechanics beyond creating the row the user accepted.

## Tests

L4 `ServiceReminderOfferUITests` (new): saving a service record with a category that has an interval
**offers** the reminder; **accepting creates it anchored at the record**; **dismissing creates
nothing**.
L1: the offer is **suppressed** when a live reminder of that category exists for that vehicle.
L1: the created reminder carries `sourceEntryId` and the recurrence.
Suites to run: `ServiceReminderOfferUITests`, `ServiceEntryUITests`.

### Vacuous traps, named
- Asserting the sheet appeared without asserting **what accepting SAVED**.
- Testing acceptance only - **a silent auto-create would pass**, and auto-create is the thing this
  row forbids. Assert the dismissal path writes nothing.
- Using a category with no interval, where the offer never fires either way.

### Mutations (run, report, restore)
1. Create the reminder on save instead of on accept -> the dismissal test must fail.
2. Anchor at `Date()` instead of the record's date -> the anchoring test must fail.
3. Drop the suppression check -> the duplicate-category L1 test must fail.

## Screenshots

`RV.77-service-reminder-offer.png` / `-ru.png` - the offer sheet after a saved record, interval
fields visible and editable. Check the RU interval phrasing reads as a sentence, not a calque, and
that "Not this time" reads as a peer choice rather than a refusal.

## Docs to reconcile

`docs/JOURNEYS.md` J7d (the Just-did-it row carries the suppression and anchor rules),
`docs/SCREENMAP.md` (the offer's place after the save), and `docs/SCHEMA.md` if you record the
per-category interval table there.
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

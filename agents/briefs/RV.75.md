# RV.75 [v1.1] - one reminders list across every car

## The gap

`RemindersView` lists one car, and the data layer cannot do better: `liveReminders(forVehicle:)`
(`Repository.swift:280`) is the only query there is. A user with three cars checks three places and
must switch cars to do it - and the Home banner derives from the **selected** car only
(`ReminderBanner.bannerReminder` over one car's rows), so another car's due work is invisible from
the surface the user actually looks at.

**Merged is the right shape, and it is not a toggle.** A reminder competes for the user's weekend,
not for a car's attention: "insurance on the Skoda" and "oil on the Volvo" are one decision. The
grouping stays exactly what it is today - **Needs attention**, then **Scheduled**, from
`ReminderLifecycle.derivedStatus` - because the question is "what needs me", never "which car".

This was reviewed on 2026-09-05 by two independent agents against the mocks and the code
(`diagnostics/RESEARCH-reminder-entry-pro.md` and `-qwen.md`); they converged on this placement.
**Read both before you design anything** - the arguments are already made.

## What to build

1. **A cross-vehicle repository query** for live reminders. **Decide and write down in its doc
   comment** what it excludes and why: tombstoned rows certainly, and **archived cars' rows** - say
   which way you went and why. If `RV.74` has already added a by-id resolve, extend that work rather
   than adding a parallel query; check before writing.
2. **The merged screen** (`design/screens/RemindersAll.dc.html`): the two existing groups, sorted by
   `dueSortKey` so a date reminder and an odometer reminder **interleave by urgency**, exactly as
   `ReminderBanner` already orders them - never grouped by car.
3. **Every row names its car.** A row that does not say which car is unreadable in a merged list.
4. **"New reminder" from here must make the car an explicit choice.** Defaulting silently to the
   selected car is the quiet guess hard rule 13 forbids. Per `design/screens/ReminderForm.dc.html`:
   **car is the first field**, empty and required when opened from the merged list, **Save inert
   until it is chosen**; pre-filled and still editable when the opener named a car.
5. **The per-car screen from Vehicle detail stays.** It is the right screen when you are looking AT
   a car.

**Do not** duplicate the lifecycle rules anywhere: attention, sorting and completion all come from
the existing core types.

## Explicitly out of scope

The permanent entry point that reaches this screen (`RV.76`) and the per-car counts (`RV.79`) - both
depend on this and are separate rows. Notification actions (`RV.78`). The offer-after-save (`RV.77`).

## Tests

L1: the new query returns live reminders for every vehicle and excludes tombstoned rows (and
archived cars' rows per your decision - assert whichever you chose).
L1: sorting **interleaves two cars' reminders by urgency**, not by car.
L4 `RemindersAllCarsUITests` (new): two seeded cars, each with one attention row - **both appear,
each naming its car**; completing one leaves the other untouched.
L4: New reminder from this screen makes the car an explicit choice - **the form arrives with the car
field EMPTY and Save disabled until one is picked**; opened from a car's list it arrives filled and
is still editable (hard rule 13).
Suites to run: `RemindersAllCarsUITests`, `RemindersUITests`.

### Vacuous traps, named
- Asserting a **count** of rows without asserting BOTH cars are represented.
- Testing with one car - the whole point is the second one.
- Asserting the new query in isolation while the screen still calls the per-vehicle one. **Assert
  what the screen shows.**

### Mutations (run, report, restore)
1. Make the query per-vehicle again behind the same signature -> the two-car L4 test must fail.
2. Sort by car, then urgency -> the interleaving L1 test must fail.
3. Pre-fill the car field from `AppCarSelection` on the merged path -> the form test must fail.

## Screenshots

`RV.75-reminders-all.png` / `-ru.png` (the merged list, two cars, both groups) and
`RV.75-reminder-form-car-empty.png` / `-ru.png` (the form opened from the merged list, car field
empty, Save inert). **Check the RU car chips do not truncate** - car names are user text.

## Docs to reconcile

`docs/SCREENMAP.md` (the new screen and its back paths), `docs/JOURNEYS.md` J7d (the Plan-it row),
and `docs/SCHEMA.md` only if the query's exclusion rule needs recording there.
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

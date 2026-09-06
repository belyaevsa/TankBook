# RV.86 - import must ask which cars to bring in

**The product owner hit this on first real use, and it is measured, not inferred.**

## The defect

`~/Downloads/myfuelmanager/fuel.csv` (the owner's own export, 513 rows) has this header:

```
Date;Fillup volume;Odometer;Total price;Currency;Fuel;Tank status after fillup;%;Note;Vehicle name
```

The last column is **`Vehicle name`**, and it holds **five different cars**:

| Vehicle name | rows | max odometer |
|---|---|---|
| Volvo | 67 | 121 727 |
| AUDI A4 Avant 2.0 TDI Komfort - 105.00kW [2009] | 389 | **426 220** |
| AUDI A6 Avant 2.5 TDI [2002] | 31 | 411 595 |
| LADA 2110 1.5 16V Komfort [2004] | 8 | 193 852 |
| NISSAN X-Trail 2.5 Columbia Elegance A/T [2006] | 18 | 70 631 |

**`MfmParser` never reads that column**, so all 513 rows land on one car.

**One defect, three reported symptoms** - do not treat them as separate bugs:
- the Volvo card reads **426 220 km**, which is the Audi's odometer (the app is right that it is the
  maximum; it is the wrong car's);
- **"117 entries excluded"** - cross-car odometer jumps;
- same-date rows whose odometer goes backwards (3 Jun 110 843 and 111 436 are different cars).

It corrupts every derived number - consumption, spend, pace - which is hard rule 2 propagating a bad
input on every recompute.

## What to build

1. **Read `Vehicle name` and group the candidates by it.** The parser stays a pure function that
   returns candidates and commits nothing (hard rule 9) - what changes is that the **grouping is
   exposed**, so the device can decide.
2. **Ask the user which cars to import** (they may not want the Lada's eight rows) **and which
   garage car each one goes into** - a new car, or an existing one. The single-car target step
   already exists (`ImportFlowModel.ensureTargetCar`); this generalises it.
3. **A file with one distinct name keeps today's flow exactly.** Do not add a step where there is no
   choice.
4. **Do not guess the mapping** by name similarity (hard rule 13). Offer it; let the user confirm.
5. **Check the corpus's other MFM fixtures** for the same column before assuming it is optional, and
   say what you found.

## Explicitly out of scope

The date-format question (`RV.85`), the same-day ordering (`RV.87`), the currency backfill
(`RV.88`). They are separate rows and two of them are downstream of this one.

## Tests

L1 (backend): a fixture with three vehicle names returns candidates **grouped by name**; a
single-name file returns one group.
L1 (client): the commit path writes each group to its own vehicle and never mixes odometers.
L4 `ImportUITests`: a multi-car file reaches a car-mapping step; after mapping, the two cars' entries
land separately.
Suites: backend `dotnet test`, plus `ImportUITests`.

### Vacuous traps, named
- **Testing a single-car file** - that is today's only tested case and it passes.
- Asserting the parse returns groups without asserting the **commit** keeps them apart.
- Asserting a row count rather than **per-car odometer continuity**, which is the symptom the user saw.

**Use the owner's real file as a fixture** - it is the reproduction, and its five cars are exactly
the shape the tests need. Copy it into the repo's fixtures rather than reading from `~/Downloads`.

### Mutations (run, report, restore)
1. Group by name but commit to one car -> the per-car continuity test must fail.
2. Default the mapping to the selected car instead of asking -> the mapping test must fail.

## Docs to reconcile

`docs/API.md` (the `/import/parse` response gains grouping - **this is a contract change, say so**),
`docs/SCREENMAP.md` (the new wizard step), `docs/JOURNEYS.md` (the import journey).
## This is the SECOND dispatch. The backend and core halves are DONE.

A first run built them, verified them, and then **stopped to ask a design
question rather than build UI it could not verify** - the right call, and the
orchestrator answered it. Read this section before anything else; do not
re-explore what it settles.

**Already committed on this branch (`c3ef9b0`), green, do not redo:**

- `MfmParser` reads the `Vehicle name` column and returns `MfmVehicleGroup`
  (name + source rows); `GroupByVehicleName` is public and tested.
- The parse response carries **`vehicleGroups` as a NEW field**, not a
  restructured candidate list, so an older client is unaffected.
- `ImportParseResponse` re-derives the grouping from stored candidates when a
  parse predates the field (the 30-day resume window).
- Core: `resolvedVehicleGroups`, `candidates(in:)`, and a commit that writes each
  group to its own vehicle.
- **Backend import tests: 28/28, exit 0.** 16 parser + the endpoint suite.

**The blocker that stopped the first run is fixed and merged in** (`RV.90`,
`db80eec`): `TankbookRedactor` reflected into `Type` and recursed until the
stack died, crashing the test host on every `POST /v1/import/parse`. If you see
a stack overflow, it is new and it is yours - report it, do not work around it.

## Your job: the client half, option A (DECIDED - do not re-ask)

Insert a `.cars` wizard step **only when the parse exposes more than one distinct
vehicle**:

1. It lists each source car with its **row count**, and an explicit destination
   per car: **Leave out / New car / an existing garage car**. Continue stays
   disabled until every car is decided - the wizard never guesses a mapping
   (hard rule 13) and never funnels into the pre-selected car.
2. On Continue, resolve **lanes** (source group -> destination vehicle) and
   classify **per lane** against that destination's own existing entries, so two
   cars can never corrupt each other's odometers.
3. The `.cars` screen **is the gate** for a multi-car file: it shows, per chosen
   car, its count, odometer span and date range, plus the duplicate count when
   merging into an existing car. Then an "Import N fills into M cars" bar.
4. **Commit stays the ONE write.**
5. **A single-car file keeps today's flow byte-for-byte** - preview, review,
   commit, untouched. This is the acceptance that protects every existing test.

**There is no artboard for this screen.** Build it from the wizard's existing
vocabulary (`ImportSourceView`, `ImportPreviewView`), and say in your report
which existing components you reused.

## You are running in a git worktree

`/Users/sbelyaev/repos/fc-rv86`, branch `rv86` - **authorized by the product owner for this
dispatch**, which is why it does not contradict `CLAUDE.md`'s standing "no worktrees" convention.
Work here and nowhere else. The main checkout at `/Users/sbelyaev/repos/fuel-counter-ios` is being
used for verification at the same time: **do not read from it, write to it, or run anything against
it.**

Two consequences that are yours to handle:

- **This worktree has its own DerivedData.** Build and test here; the first `xcodebuild` will be slow.
- `xcodegen generate` before any `xcodebuild`, because `Tankbook.xcodeproj` is generated and
  gitignored, so this tree does not have one yet.

**The evidence file is at the worktree root: `fuel.csv`** - the product owner's real My Fuel
Manager export, already copied for you. Copy it into the repo's test fixtures as part of your work
(it is the reproduction), and say where you put it.

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

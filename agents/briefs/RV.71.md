# RV.71 - warn when a scanned or typed fuel kind is not the car's

**The design is DECIDED (product owner, 2026-09-05). Implement it; do not re-derive it.**

## Why the row exists

`Vehicle.fuelKinds` records what a car takes (`Entities.swift:43`), `FuelKind` covers
diesel/petrol92-100/lpg/cng/e85/electricity (`Enums.swift:4-13`), and the extractor already resolves
a `fuelKind` from a receipt - **but nothing compares the two**, so a diesel receipt logged against a
petrol car saves without a word.

It is not cosmetic: fuel kind feeds the consumption maths, which treats litres and kWh differently,
so a wrong kind silently corrupts the series the whole app exists to compute (hard rule 2 - a bad
input propagates on every recompute). And the mis-scan is real, not hypothetical: the corpus already
holds `АИ-96` read at **confidence 1.00** on a 95 receipt, plus `receipt-032`'s `AM-95` smear.

## The decided design

**1. The comparison is by FAMILY, not by member.** Petrol grades share a tank and are a real
driver's choice - `FuelKind.isPetrolGrade` (`Enums.swift:16-22`) already encodes this.

| Scanned/typed | Car declares | Warn? |
|---|---|---|
| any petrol grade | any petrol grade | **no** - a grade choice, and the case that would otherwise annoy every user daily |
| diesel | petrol only, or the reverse | **yes** |
| LPG / CNG | neither LPG nor CNG | **yes** |
| E85 | no E85 | **yes** - E85 in a non-flex car is a real hazard, and it is not a petrol grade |
| electricity | anything | **no** - that is a charge session, a different entry path, and it would fire on every hybrid |
| anything | **empty set** | **no** - see below |

**2. An empty `fuelKinds` means "not declared", and not-declared never warns.** It is a reachable
state, not a hypothetical: Add car gates the save on `name` alone (`AddVehicleView.swift:158-161`)
and every fuel pill is deselectable (`VehicleFormControls.swift:336-342`). The warning's premise is
a disagreement between two known values; with one side absent there is no disagreement, only
absence, and a rule that fires for a whole class of cars is not a rule.

**3. But absence is repaired, not left silent.** On the first fill-up saved against a car with no
declared kinds, **adopt the confirmed kind onto the car** and say so in one line ("Saved as this
car's fuel · change in Garage"). That is a derived default, editable at the moment it is offered and
afterwards - hard rule 13, the same treatment the "last known" odometer gets. Without it such a car
can never reach the state where the warning works.

**4. When the user keeps a warned kind, OFFER - never auto-add.** The warning carries an inline
action ("Add diesel to this car") that writes the kind to `Vehicle.fuelKinds` permanently. Auto-add
is wrong here: the likelier cause is a mis-scan, and auto-adding would make the mis-scan permanent
**and** destroy the comparison that would catch the next one.

**5. It shows on BOTH doors** (product owner: hard rule 15). The check is on the **value**, not its
source - a typed diesel on a petrol-only car is the same disagreement and feeds the same maths.

## What to build

- A **pure function in core** - `FuelKindMismatch.check(scanned:declared:)` returning a value, so
  the whole rule is L1-testable and the screen only renders.
- An **amber caption on the Confirm screen's fuel row**, beside the value it is about. Never a
  modal, never blocking, **Save always reachable** (hard rules 5, 7, 13). Reuse the shape already
  shipping for the diesel+petrol discouragement note (`VehicleFormControls.swift:287-299`) rather
  than inventing a severity.
- The adopt-on-first-fill-up line and the "add to this car" action above.
- EN + RU through the String Catalog, full localised phrases.

## Explicitly out of scope

Charge sessions. Blocking or refusing any save. Changing `offeredKinds` or the pills. AdBlue -
`docs/SCHEMA.md:350` states a CHECK 4 invariant about `.adBlue` in `Vehicle.fuelKinds` but
**`FuelKind` has no such case**; that doc drift is real and is NOT this row's to fix - report it.

## Tests

L1 over the comparison, the whole point of the row: diesel receipt + petrol-only car -> warns;
petrol receipt + diesel-only car -> warns; **95 receipt + car declaring 92 and 95 -> does NOT warn**;
LPG receipt + car declaring neither LPG nor CNG -> warns; electricity -> never warns; **empty
`fuelKinds` -> does not warn**, asserted.
L1: the first fill-up against an empty-kinds car adopts the kind; a later fill-up does not overwrite
a kind the user has since edited (hard rule 13 - once theirs, permanently theirs).
L4 `ConfirmManualUITests`: the warning renders after a scan, **Save stays reachable with it on
screen**, and dismissing it changes neither value. Also assert it renders on the **typed** path.

### Vacuous traps, named
- Asserting the warning exists **without a case that must NOT warn** - a rule that fires on
  everything is not a rule.
- Asserting a string rather than that **Save still works**.
- Testing only diesel-vs-petrol and missing the **grade** case, which is the one that would annoy
  every user daily.
- Seeding a car with exactly one kind and never testing the empty set.

### Mutations (run, report, restore)
1. Compare by member instead of family -> the 92/95 no-warn test must fail.
2. Warn on an empty `fuelKinds` -> its test must fail.
3. Auto-add the kind instead of offering -> the "offer, never auto-add" test must fail.

## Screenshots

`RV.71-confirm-fuel-mismatch.png` / `-ru.png`, dark, warning visible with Save reachable. Check the
RU caption does not push Save off screen and that the inline action renders **in RU** (RV.80 is an
action that appears in EN and silently does not in RU).

## Docs to reconcile

`docs/SCHEMA.md` (the empty-set meaning and the adopt rule), `docs/ERRORS.md` (the warning and its
next step), `docs/JOURNEYS.md` if the confirm flow gains a step.
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

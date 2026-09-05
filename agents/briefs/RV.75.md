# RV.75 – Reminders across every car, on one screen

**[v1.1]** The row is `docs/TASKS.md` -> RV.75. Read it first: it carries the cause, the fix stance
and the checks, and this brief does not repeat them.

This is the **dependency** of the reminders set. RV.74, RV.76 and RV.79 all reuse the query you add
here, so the query's shape matters more than the screen's.

## Where you may write

Only inside this repository:

- `ios/Sources/TankbookCore/Persistence/Repository.swift` (the new query)
- `ios/App/Sources/Reminders/` (the screen)
- `ios/App/Sources/Navigation/` (the route, if you add one)
- `ios/Tests/TankbookCoreTests/` and `ios/App/UITests/`
- `ios/App/Sources/Localizable.xcstrings` (every user-facing string, hard rule 10)
- `docs/SCREENMAP.md` only if you change navigation the map states

**Run no `git` command.** Never move, rename or delete a file you did not create - another session
may be working in this checkout; if something is in your way, report it and carry on.
**Never `pgrep -f`**: your brief is your command line, so it matches you. Use `pgrep -x`.

## Write code first, explore second

Add the repository query and its unit test **before** touching the screen. It is the part every
other task in this set depends on, and a run that explores for an hour and lands nothing has
produced nothing.

## What already exists - build on it, do not redesign it

- `TankbookRepository.liveReminders(forVehicle:)` (`Repository.swift:280`) - the per-car query, which
  stays. It calls the private `fetchLiveForVehicle(_:vehicleId:in:)` helper (`:639`), which filters
  `deletedAt == nil` and orders by `createdAt`.
- `liveVehicles()` (`:97`) - how vehicles are listed, including whether archived ones come back.
- `ReminderLifecycle` - `derivedStatus`, `isAttentionDue`, `isActive`, `due`. **The screen's
  grouping and every status transition already live here.** Do not reimplement them.
- `ReminderBanner.bannerReminder(among:currentOdometer:now:)`
  (`ios/Sources/TankbookCore/Service/ReminderBanner.swift`) - shows the sort you must match:
  `ReminderLifecycle.due($0)?.dueSortKey(currentOdometer:now:)`, `createdAt` as the tiebreak.
- `RemindersView` (`ios/App/Sources/Reminders/RemindersView.swift`) - today's per-car screen: the
  two sections, `rowView`, the completion sheet, the dismiss and delete alerts, `newReminderCard`.
- `ReminderNotificationCoordinator.reconcile(vehicleId:)` - per-vehicle, and it stays that way.

## Read before writing

1. **`docs/TASKS.md` -> RV.75** - the authority for this task.
2. **`docs/SCREENMAP.md` -> "Reminders across cars [v1.1]"** - the decided shape, including what the
   merged list does that the per-car one does not.
3. **`docs/JOURNEYS.md` -> J7d** - where a reminder comes from; the Plan-it row is this screen.
4. `design/screens/RemindersAll.dc.html` and `design/screens/ReminderForm.dc.html` - the mocks. They
   are HTML: read them as source. Match the structure, not the pixels of a browser render.
5. `CLAUDE.md` hard rules **2** (stats are derived, never stored) and **13** (the app suggests, the
   user decides).

## What to build

**1. The query.** `liveReminders(forVehicle:)` gains a sibling that returns live reminders across
vehicles. Decide and **say in your report**: does it take an optional vehicle id, or is it a
separate function? Whichever you choose, the per-car call must keep working unchanged - RV.74 and
RV.79 will both call yours.

Two questions the row does not settle, and you must decide and justify **in code comments**:

- **Archived cars.** `liveVehicles()` tells you how archived vehicles are treated elsewhere. A
  reminder on an archived car is almost certainly not something the user wants nagging them, but
  deleting it is not your call. Say what you did and why.
- **Ordering.** Reminders from different cars interleave by urgency, never grouped by car - the
  sort is `dueSortKey`, the same one `ReminderBanner` uses. A merged list sorted by car is the
  failure mode this screen exists to avoid.

**2. The screen.** A merged variant of the reminders list. Every row **names its car** - a merged
row that does not is unreadable. Sections stay "Needs attention" then "Scheduled", derived through
`ReminderLifecycle`, never recomputed locally.

**3. The car field on the form.** `ReminderFormView` gains a car field, first in the form:

- opened from the merged list: **empty, required, Save disabled until a car is chosen**;
- opened from a car's own list or Vehicle detail: **filled in, and still changeable** (hard rule 13);
- with exactly one live vehicle it still renders - it is the only thing that says which car this is
  about - and it may arrive pre-selected.

**4. Localisation.** Every new string in `Localizable.xcstrings`, EN and RU, as a complete phrase per
language - never concatenation (the P1.4 lesson: `"%@ spend"` composed as `"%@ расходы"` rendered
"АВГУСТ РАСХОДЫ").

## Out of scope - do not build these

- The Home entry row and its count (RV.76), the Garage counts (RV.79), the post-service offer
  (RV.77), notification actions (RV.78), and the notification deep-link fix (RV.74). **RV.74 is
  tempting because your query makes it easy. Leave it.**
- Any change to `reconcile(vehicleId:)` or to how notifications are scheduled.
- A header `+`. Reviewed and rejected on 2026-09-05: both list headers spend the trailing slot on
  the car-scope chip, and the dashed card at the end of the list is the app's own idiom
  (`docs/SCREENMAP.md`). The dashed card stays where it is.

## Tests

Current baseline, measured on this checkout on 2026-09-06, immediately before this brief was
written: **`swift test` 1469 tests in 157 suites, passed, exit 0.** It must **rise**. Report the number you observed, not the number you expected.

- **L1** (`ios/Tests/TankbookCoreTests/`): the new query returns reminders from more than one
  vehicle; excludes tombstoned rows; treats archived cars the way you decided (assert it either way);
  and sorting **interleaves two cars' reminders by urgency** - build the fixture so a car-B reminder
  sorts between two car-A reminders, which is the assertion a per-car implementation cannot pass.
- **L4** `RemindersUITests` (`ios/App/UITests/RemindersUITests.swift` - extend it, do not add a
  parallel suite): with two seeded cars each holding one attention row, **both appear and each names
  its car**; completing one leaves the other in place. Opened from the merged list the form's car
  field is empty and Save is disabled; opened from a car's own list it arrives filled and can still
  be changed.

**Vacuous traps for this task** - a check that passes today is not a check:

- Asserting a row count without asserting that **both cars** are represented. A per-car list of two
  reminders passes that.
- Testing with one seeded car, where the bug cannot exist.
- Asserting the query in isolation while the screen still calls the per-vehicle one - assert the
  screen shows both cars.
- Asserting the car field exists rather than its **state** (empty vs filled, Save enabled vs not).

Name the seed you add and pass `-homeResetDatabase` with it: seeds are idempotent and silently do
nothing on a populated database, so without it you capture the previous run's state.

## The baseline gate (`CLAUDE.md` rule 14)

From the **repo root**, judged by exit code, not by reading output:

```
cd ios && swift build ; echo "BUILD=$?"
cd ios && swift test ; echo "IOSTEST=$?"
swiftlint lint ; echo "LINT=$?"          # from the ROOT - the excludes are root-relative
```

Then the named UI suite only:

```
xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:TankbookUITests/RemindersUITests test ; echo "UITEST=$?"
```

Check the test count is non-zero: a filter matching nothing prints "0 tests ... passed".
Do not run the full UI suite - that belongs to phase completion.

## Screenshots

EN and RU, dark theme, of the merged list with two cars and of the form with the car field empty:

```
xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU -homeResetDatabase <your seed>
```

Commit them to `design/screenshots/` as `RV.75-<screen>.png` / `-ru.png`. **You cannot see them** -
you have no image input - so do not claim they show the right screen. Say what you captured and let
the orchestrator open them. Never capture while `xcodebuild test` is running: they fight over the
device and both lose.

## Report back

1. The captured exit codes above, verbatim.
2. `swift test` observed count, and the count before your change.
3. The UI suite's observed test count (non-zero).
4. **The query's signature**, and your two decisions with their reasons: archived cars, and ordering.
5. Which strings you added, and confirmation both languages are present.
6. Anything you found wrong in the row or this brief. A brief that is wrong gets fixed - say so
   rather than working around it.

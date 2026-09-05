# RV.77 – a saved service record offers the next reminder

**[v1.1]** The row is `docs/TASKS.md` -> RV.77. Read it first; this brief does not repeat it.

Independent of the rest of the reminders set: it touches the service/expense save path, not the
reminders list. It can run alongside RV.75.

## Where you may write

Only inside this repository:

- `ios/App/Sources/ServiceEntry/` (the save path and the offer sheet)
- `ios/App/Sources/Reminders/` only if the sheet reuses something there
- `ios/Sources/TankbookCore/Service/` (the interval table and the suppression rule)
- `ios/Tests/TankbookCoreTests/` and `ios/App/UITests/`
- `ios/App/Sources/Localizable.xcstrings` (every user-facing string, hard rule 10)
- `docs/SCHEMA.md` if you add a field; `docs/ERRORS.md` if you add a message

**Run no `git` command.** Never move, rename or delete a file you did not create.
**Never `pgrep -f`**: your brief is your command line, so it matches you. Use `pgrep -x`.

## Write code first, explore second

The interval table and its unit test first - it is the piece that has to be right, and it is small.
The sheet second. A run that reads the whole service path and writes nothing has produced nothing.

## What already exists - build on it, do not redesign it

- `Reminder.Recurrence` (`ios/Sources/TankbookCore/Domain/Entities.swift:416`) - `everyKm`,
  `everyMonths`. This is what an accepted offer writes; there is nothing to invent.
- `Reminder.sourceEntryId` (`:411`) - the link from a reminder back to the record it came from.
  **Set it.** It is how a later reader can tell an offered reminder from a hand-typed one.
- `ReminderCategory` and `ReminderCompletion.entryKind(for:)` - the existing category mapping in the
  other direction (reminder -> entry form). Yours is the inverse; keep the two consistent.
- `ExpenseEntryView` (`ios/App/Sources/ServiceEntry/ExpenseEntryView.swift:201`) - the existing
  reminder-completion hand-off, and the shape of "after the save lands, do one more thing". Read it
  before writing your own.
- `ReminderLifecycle.isActive` - what "a live reminder already exists" means. Do not write a second
  definition.

## Read before writing

1. **`docs/TASKS.md` -> RV.77** - the authority.
2. **`docs/JOURNEYS.md` -> J7d, the "Just did it" row** - the journey this closes, and the reason it
   matters: it is the birth that does not require the user to know the Reminders screen exists.
   **J7c** is the other half, already built.
3. `design/screens/ServiceReminderOffer.dc.html` - the mock, readable as HTML source. The copy on it
   is deliberate: "Counted from this record, not from today", "A suggested interval, not a fact".
4. `CLAUDE.md` hard rule **13** (the app suggests, the user decides) and rule **7** (every error
   names its next step; monetisation appears in no error surface).

## What to build

**1. The interval table, in core, as data.** Per-category defaults ("service: 15 000 km or 12
months"). One lookup, one place. **Not** a switch statement inside the save handler: `JOURNEYS.md`
J15 and J17 have the v2 agent proposing the same intervals from invoice lines and from a diagnosis,
and three copies of these numbers will disagree. Say in your report where you put it.

A category with no sensible interval (a one-off expense) returns nothing and offers nothing.

**2. The offer, after the save lands.** Never mid-save: the record is written first, then the sheet
appears. Dismissing it must cost nothing and lose nothing.

- Pre-filled from the record: its category, **its** date, **its** odometer - never today's. A
  schedule anchored at the due date drifts; anchored at the work, it does not.
- The interval renders as **two editable fields** (km and months), not as a fixed sentence. It is a
  suggestion the user can change in the same breath (hard rule 13).
- **Create the reminder** is the primary action; **Not this time** is a peer button, not a dismiss X.

**3. The suppression rule.** No offer when a live reminder of that category already exists on that
car - otherwise a user who services twice collects three oil reminders. Use `ReminderLifecycle`'s
own definition of live.

**4. What an accepted offer writes.** A `Reminder` with the category, the title, the due date and/or
odometer computed from the record, the recurrence, and `sourceEntryId` pointing at the record.

**5. Localisation.** EN and RU, complete phrases per language, never concatenation.

## Out of scope - do not build these

- The merged list (RV.75), the Home row (RV.76), the Garage counts (RV.79), notification actions
  (RV.78), the deep-link fix (RV.74).
- **Any auto-creation.** A reminder that appears without the user tapping Create is the bug this
  task exists to avoid, not a shortcut.
- A "coming soon" or upsell anywhere in this flow (hard rule 7).
- Changing what a fill-up save does. Fuel is not the subject here.

## Tests

Current baseline, measured on this checkout on 2026-09-06: **`swift test` 1469 tests in 157 suites,
passed, exit 0.** It must rise. Report the number you observed.

- **L1**: the interval table returns the expected pair for a category that has one, and nothing for
  one that does not. The computed due values are derived from the RECORD's date and odometer - build
  the fixture with a record dated in the past and assert the due date is not counted from today,
  which is the assertion a today-anchored implementation cannot pass.
- **L1**: the suppression rule - with a live reminder of that category on that car, no offer; with a
  completed or dismissed one, the offer returns.
- **L4** `ios/App/UITests/ServiceEntryUITests.swift` - extend it, do not add a parallel suite
  (`ExpenseCaptureUITests.swift` covers the expense capture door and is the one to extend instead if
  you wire the offer there too): saving a service record with an interval category shows the offer; **Create**
  produces a reminder anchored at the record and carrying `sourceEntryId`; **Not this time**
  produces none and the record is still saved.

**Vacuous traps for this task**:

- Asserting the sheet appeared without asserting what **Create** actually saved.
- Testing acceptance only - a silent auto-create passes that. Assert the dismissal path writes nothing.
- Using a category with no interval, where nothing is offered and everything trivially passes.
- Asserting the due date exists rather than its **value** relative to the record's date.

Name the seed you add and pass `-homeResetDatabase` with it.

## The baseline gate (`CLAUDE.md` rule 14)

From the **repo root**, judged by exit code:

```
cd ios && swift build ; echo "BUILD=$?"
cd ios && swift test ; echo "IOSTEST=$?"
swiftlint lint ; echo "LINT=$?"                                   # from the repo ROOT
swift run --package-path ios localization-gate --sources ios/App/Sources \
  --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"   # ROOT, must be 0
# measured on this checkout 2026-09-06: 716 keys, 100% RU, 0 missing, 0 violations
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"
```

**Echo the exit code from the COMMAND, never through a pipe** - a pipe reports the exit code of the
last stage, so a failing build behind `| tail` reports 0. Redirect to a file instead.

`xcodegen generate` is not optional if you add a FILE: the project is generated from `project.yml`
and is gitignored, so a new source file that is never regenerated into the project builds in
`swift build` and is missing from the app.

Then only the suite you touched:

```
xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:TankbookUITests/ServiceEntryUITests test ; echo "UITEST=$?"
```

A filter matching nothing prints "0 tests ... passed" - report the observed count.

## Screenshots

EN and RU, dark, of the offer sheet over the saved record. Commit as
`design/screenshots/RV.77-service-reminder-offer.png` / `-ru.png`. **You cannot see them**: say what
you captured, do not claim what it shows. Never capture while `xcodebuild test` is running.

## Report back

1. The captured exit codes, verbatim.
2. `swift test` observed count, before and after.
3. The UI suite's observed count (non-zero).
4. **Where the interval table lives**, and the intervals you chose with your source for them.
5. What an accepted offer writes, field by field.
6. Anything wrong in the row or this brief - say so rather than working around it.

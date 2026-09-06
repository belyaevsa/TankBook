# RV.77 [v1.1] - after the user logs the work, offer the next reminder

**Independent of RV.75/76/79.** It can run before or after them.

## Read this first - what "done" means here

**The deliverable is working Swift code plus its tests.** Reading the repository, or reporting on
the state of the gates, is not the deliverable. If you finish your run without having written code,
the task has failed regardless of what you learned.

Work in this order, and do not let step 1 consume the run:

1. **Confirm the baseline** with the five commands in "The baseline gate" below, exactly as printed.
   Budget a few minutes. The baseline is known green - see the table there.
2. **Write the feature** (see "What to build").
3. **Write the tests** named under "Tests".
4. **Re-run the gates** and report before -> after counts.
5. **Run the three mutations**, report which named test went red for each, and restore.
6. **Take the two screenshots.**
7. **Report** in the shape "Report back" asks for.

A gate that is red before you have touched anything is a **you problem, not a repo problem** - the
commands below are the ones that work on this checkout, measured minutes ago.

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

Only inside `/Users/sbelyaev/repos/fc-rv77-giga`, and within it only:
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

## The baseline gate - run these commands EXACTLY as written

This checkout is `/Users/sbelyaev/repos/fc-rv77-giga`. **Every command below carries an absolute
path, so it does not matter what your shell's working directory is.** Run them as written. Do not
invent a shorter variant, and do not `cd ios` first - several of these are wrong from `ios/`.

**The baseline was measured on THIS checkout minutes before you started, and every gate was GREEN:**

| Gate | Measured result |
|---|---|
| `swift build` | exit 0, `Build complete!` |
| `swift test` | exit 0, **1487 tests in 161 suites**, 0 failures |
| `swiftlint lint` | exit 0, **0 errors** |
| localization gate | exit 0, 726 keys, 100% RU, 0 missing |
| `xcodebuild build-for-testing` | `** TEST BUILD SUCCEEDED **` |

**If a gate comes out RED for you before you have changed a single file, your command is wrong -
the repo is not broken.** Come back to this section and run the command as printed. In particular,
a wall of `identifier_name` or `trailing_comma` errors in files you never opened
(`Logging/LogEvents.swift` is the usual one) means you ran SwiftLint from the wrong directory. Never
"fix" a violation in a file this brief did not send you to.

### 1. Build the core package

    swift build --package-path /Users/sbelyaev/repos/fc-rv77-giga/ios

Expect `Build complete!` and exit 0.

### 2. Unit tests (L1)

    swift test --package-path /Users/sbelyaev/repos/fc-rv77-giga/ios

Expect `Test run with 1487 tests in 161 suites passed` BEFORE your change, and a **higher** number
after it. Report both numbers.

**`swift test` cannot run UI tests, and `--filter` will not help you.** `ServiceReminderOfferUITests`
and `ServiceEntryUITests` live in `ios/App/UITests/`, which is NOT part of the SwiftPM package.
`swift test --filter ServiceEntryUITests` matches nothing and prints a green run of **zero** tests -
that is not evidence of anything. UI tests run only through step 5.

### 3. SwiftLint - from the repo ROOT, never from `ios/`

    cd /Users/sbelyaev/repos/fc-rv77-giga && swiftlint lint

Expect **0 errors** (warnings are allowed and do not block). The config's `excluded:` paths are
root-relative, which is why running it from `ios/` produces thousands of phantom violations.
There is no `swiftlint autocorrect` subcommand; the auto-fixer is `swiftlint --fix`, and you should
not need it.

### 4. Localization gate - from the repo ROOT

    cd /Users/sbelyaev/repos/fc-rv77-giga && swift run --package-path ios localization-gate \
      --sources ios/App/Sources --catalogue ios/App/Sources/Localizable.xcstrings

Expect exit 0, 0 missing, 0 violations. Every user-facing string you add needs an EN and an RU
value in `ios/App/Sources/Localizable.xcstrings` or this gate fails.

### 5. UI tests (L4) - the ONLY way to run them

If you added a NEW file, regenerate the Xcode project first, or it will not be compiled:

    cd /Users/sbelyaev/repos/fc-rv77-giga && xcodegen generate

Then, in one command:

    cd /Users/sbelyaev/repos/fc-rv77-giga && xcodebuild \
      -project /Users/sbelyaev/repos/fc-rv77-giga/Tankbook.xcodeproj \
      -scheme Tankbook \
      -destination 'id=AB5731CE-C155-4DD9-8C4F-4A27E076373D' \
      -only-testing:TankbookUITests/ServiceReminderOfferUITests \
      -only-testing:TankbookUITests/ServiceEntryUITests \
      test > /tmp/rv77-ui.log 2>&1 ; echo "XCODEBUILD_EXIT=$?"

Notes that decide whether this works:
- `Tankbook.xcodeproj` is at the **repo root**, not in `ios/`. `xcodebuild` from `ios/` cannot find it.
- `swift build` does NOT compile `ios/App`. Only `xcodebuild` does. Your SwiftUI code is unverified
  until this step passes.
- The destination is given as `id=` - a **dedicated simulator reserved for you**, already booted.
  Do not target a simulator by name; another agent is using a different device on this machine.
- **Check the observed test count is non-zero.** `Executed 0 tests` is a filter that matched
  nothing, not a pass. Read the count out of `/tmp/rv77-ui.log`.
- Do NOT run the whole UI suite - only the two suites named above.

### How to read an exit code

    <command> > /tmp/out.log 2>&1 ; echo "EXIT=$?"

Redirect to a file and echo the code. **Never pipe into `tail` or `grep` and echo `$?`** - a pipe
reports the LAST stage's status, so a failing build behind `| tail -1` reports 0. And never
`pgrep -f` for a build: your own brief text is in your command line and you would match, and could
kill, a sibling agent. Use `pgrep -x xcodebuild`.

## Screenshots

EN **and** RU, **dark**, into `/Users/sbelyaev/repos/fc-rv77-giga/design/screenshots/`, named
`RV.77-service-reminder-offer.png` and `RV.77-service-reminder-offer-ru.png`.

Your simulator is `iPhone 17 EXP2`, udid `AB5731CE-C155-4DD9-8C4F-4A27E076373D`, already booted.
Address it by udid, never by name - another agent is on a different device on this machine.

    D=AB5731CE-C155-4DD9-8C4F-4A27E076373D
    xcrun simctl launch $D app.tankbook.Tankbook <your launch arguments>
    xcrun simctl io $D screenshot /Users/sbelyaev/repos/fc-rv77-giga/design/screenshots/RV.77-service-reminder-offer.png

For Russian, relaunch with:

    xcrun simctl launch $D app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU <your launch arguments>

- Capture **outside** a test run - `simctl` and `xcodebuild test` fight over the device.
- A `-` prefixed launch argument can **persist across relaunches**; `xcrun simctl uninstall $D
  app.tankbook.Tankbook` and reinstall between shots if a seeded state sticks.
- **Verify the EN/RU pair differs**: `md5 -q a.png b.png`, and report both hashes. A previous run
  shipped an "RU" shot byte-identical to its EN one and could not tell.
- **RU is not a formality.** Russian runs 20-30% longer than English and short strings expand worst.
  Read the rendered Russian for grammar and word order, not just for overflow, and check every
  action line actually renders in RU - an action that appears in EN and silently does not in RU is a
  known shape in this repo, found only by looking.
- You cannot see your own screenshots. The orchestrator opens all of them; do not claim they look
  right.

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

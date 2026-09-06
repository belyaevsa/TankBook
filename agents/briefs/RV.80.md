# RV.80 - an action that renders in English and not in Russian

## The defect, and it is shipping

`ImportSourceView.notSupportedCard` (`ios/App/Sources/Import/ImportSourceView.swift:245-271`) is one
`Button` whose label is a `VStack` of three unconditional `Text` views:

1. `Text("Your app isn't here?")`
2. `Text("Send us the file and we'll add it. Nothing is imported until you confirm.")`
3. `Text("Send us the file")` - the action line, `Theme.Palette.action`, `.padding(.top, 8)`

**In EN all three render. In RU only the first two do**, and the card is visibly shorter - the
affordance is simply absent. Reproduced by the orchestrator on 2026-09-06 with a fresh capture, not
inferred from an agent's report: `design/screenshots/RV.73-import-read-failed.png` (EN, link
present) against `-ru.png` (RU, link absent).

**Why it matters more than a missing line**: that card IS the dead end's next step (hard rule 7 -
the code comment above it says so), and because the whole card is a `Button`, a Russian user still
has a tappable region with **nothing telling them it is tappable**. It is also the entry point for
the corpus growth F6 depends on. **Not caused by RV.73**, which never touched this card.

## What I have already eliminated - do not spend time re-checking

The orchestrator inspected `ios/App/Sources/Localizable.xcstrings` directly on 2026-09-06:

- the key `Send us the file` **is present**, `extractionState: manual`;
- its RU value is `"Отправить файл"`, `state: translated`;
- there are **no duplicate or near-duplicate keys** for it (the four near-duplicate groups in the
  catalogue are `or`, `Added %@`, `Months`, `Updated %@` - all case-only, none related);
- **all 741 keys have an `ru` localization** - none is missing.

So this is **not** the duplicate-key-displacement shape (2026-08-31) and not a missing translation.
The string resolves and does not reach the screen. **Start from reproduction, not from the catalogue.**

## What to build

1. **Reproduce first**, in RU, and find the actual mechanism. The remaining suspects are rendering
   and layout, not localisation: bisect by rendering that third `Text` alone in RU, then in place,
   and see which step loses it. Suspect list, in the order worth trying: something in the `VStack`
   collapsing the third child under RU metrics, the `.padding(.top, 8)` interacting with the
   card's fixed sizing, and `Text` inside a `Button` label with `.buttonStyle(.plain)` under a
   different locale's font metrics.
2. **Fix the cause, not the symptom.** Forcing the line visible with a frame or a `fixedSize` may
   hide a general problem: if the same shape can drop a child anywhere else, say so and name where.
3. **Then audit for the shape**: any other multi-`Text` card whose action line is a plain `Text`
   rather than a labelled control. Report differentiated - which are affected, which are not, and
   why - and **do not fix them all silently**.

## Explicitly out of scope

Import behaviour (RV.73, shipped). Rewording the copy. Turning the card into a different control
unless that is the actual fix, in which case say so plainly.

## Tests

L4 in `ImportUITests`: **the action line is present in RU**. The suite already runs seeded RU
checks - follow that pattern rather than inventing one.
L1 if the mechanism turns out to be expressible below the view layer.

### Vacuous traps, named
- Asserting the card exists. **It does, in both languages** - that is the whole problem.
- Asserting the EN string only. It passes today.
- Asserting the card's accessibility identifier rather than the visible action line.
- A snapshot test recorded on iOS 26 (baselines are runtime-specific and not valid for 18).

### Mutation
Remove the RU value from the catalogue for that key -> your new L4 test must fail. If it still
passes, the test is not asserting what it claims.

## Screenshots

**EN + RU are the gate here**, because this is precisely a defect no assertion caught:
`RV.80-import-not-supported.png` / `-ru.png`, dark. Both must show the action line.
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

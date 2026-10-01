# PJ.43 - two error rows with no rendering: "Page N didn't save" and the stale-odometer hint

Journey: J3 multi-page capture, J7c reminder lifecycle. Product owner, 2026-10-01: build PJ.16, PJ.41,
PJ.42, PJ.43; this one first.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. Expected files: `ios/App/Sources/ServiceEntry/`,
`ios/App/Sources/Reminders/`, `ios/Sources/TankbookCore/` (only if the stale-odometer rule belongs in
core - it should, as a pure function), `ios/App/Sources/Localizable.xcstrings`, the matching tests,
`docs/ERRORS.md`, `docs/JOURNEYS.md` (J3 / J7c lines only if behaviour changes), `docs/PRACTICES.md`
(constants table, if you add a tunable). Nothing under `ios/Sources/TankbookCore/Extraction/PumpReader/`
- another session has uncommitted work there.

## Write code first, explore second

The two rows are small and the places are named below. Read the named files, then write.

## What is missing (confirm before you change anything - this is a hypothesis)

`docs/ERRORS.md` promises two messages that nothing renders:

1. **ERRORS.md:381, Service entry, "Multi-page scan interrupted"** - shows *"Page 2 didn't save – rescan
   it or continue with 1 page."*, next steps **Rescan page · Continue**. The multi-page invoice capture
   lives in `ios/App/Sources/ServiceEntry/` (`ServiceInvoiceScanner.swift`, `ServiceEntryInvoicePage.swift`,
   `ServiceEntryView+DiscardPages.swift`, the page strip `ServiceEntryPageStrip`, and `InvoicePageStore`).
   Find where a page's image is written (the store's write) and what happens today when it fails -
   most likely a `try?` that drops the page silently, which is hard rule 8's "nothing lost silently"
   and hard rule 7's "every error names its next step". Name the line in your report.
2. **ERRORS.md:462, Reminders, "Completing with km-recurrence but stale odometer"** - a hint *"Next
   cycle counts from 119 486 km – update if you've driven since."*, next steps **Edit odometer ·
   accept**. Completing a reminder lives in `ios/App/Sources/Reminders/ReminderCompleteSheet.swift`
   and `ReminderCompletionSession.swift`; a km recurrence computes the next due from the car's last
   known odometer. When that reading is old, the next cycle counts from a stale number and the user
   is never told.

## What to build

- **Page save failure.** When a page of a multi-page service-invoice capture cannot be saved, the
  user sees the ERRORS.md:381 message with the page number and the remaining page count, and two
  actions: rescan that page (back to the scanner for one page, appended in place) or continue with the
  pages that saved. The failed page is never silently dropped. A shape-only log event names the page
  index and the error domain/code, never the image (`docs/LOGGING.md`, hard rule 12). Use the error
  vocabulary's severity (`docs/ERRORS.md` top) for the styling, palette per `docs/DESIGN.md` (amber is
  attention).
- **Stale-odometer hint.** On completing a reminder whose recurrence is by distance (or distance and
  time), when the car's last known odometer reading is older than a threshold, show the ERRORS.md:462
  hint with the real number, an **Edit odometer** action (lets the user enter today's reading in the
  sheet, and the next cycle counts from it), and accepting = completing as is. Put "is it stale" in
  `TankbookCore` as a pure function over (last reading date, now, threshold). The threshold is a
  tunable: place it per `docs/PRACTICES.md` -> the constants-placement policy and add its row there;
  look first for an existing staleness constant for the odometer (grep "stale" / "lastKnown") and reuse
  it if one exists. If the sheet already lets the user edit the odometer, the hint points at that
  control instead of adding a second one - say which in your report.
- Both strings in `Localizable.xcstrings`, EN and RU, written as full phrases (no concatenation; the
  numbers via format arguments). En-dashes only, never em-dashes.

**Out of scope:** PJ.16 (capture torch and hints), PJ.41 (expense from this receipt), PJ.42 (demo
receipt) - separate rows, separate dispatches after this one. Other ERRORS.md rows that also have no
rendering: list them in your report, do not build them.

## Docs to read, in order

1. `docs/ERRORS.md` - the two rows, the severity vocabulary at the top, the 3-question audit rule
   (authority for the wording and next steps).
2. `docs/DESIGN.md` - error/hint styling, palette, type.
3. `docs/LOGGING.md` - what a log line may carry.
4. `docs/PRACTICES.md` - the constants-placement policy (for the staleness threshold).
5. `docs/JOURNEYS.md` J3 (multi-page) and J7c (reminder completion).

Extend `docs/ERRORS.md` if the real behaviour differs from its wording (e.g. the next-step names).

## Checks (judged by exit code; report each)

- `scripts/gate.sh` - swift build, `swiftlint lint` from the repo ROOT, the app Debug build, `swift
  test`, the app-target unit bundle. Exit 0.
- You will add a DEBUG-only seam to inject a page-save failure for the UI test, so also
  `RELEASE=1 scripts/gate.sh` (exit 0) - an unguarded call to a DEBUG-only type breaks Release.
- UI suites you touch, each its own `xcodebuild test -only-testing:` invocation, and read the COUNT:
  the service-entry suite (find the class covering the page strip - `ServiceEntryUITests` or the
  file that tests `ServiceEntryPageStrip`) and the reminders suite (`RemindersUITests` or the file
  covering `ReminderCompleteSheet`). A filter that matches nothing prints "0 tests" and exits 0.
- The localization gate the gate script runs (100 % RU).

## Tests you must add

- **L1, core:** the staleness rule. Oracle: the threshold constant itself - a reading exactly at the
  threshold, one day inside, one day past. **Mutation:** flip the comparison in the staleness function
  (`>` to `>=` or the reverse) - a boundary test must go red.
- **L1 or L2:** the page-save failure path keeps the failed page's slot visible and does not drop it;
  continuing saves only the pages that saved. **Mutation:** restore the silent `try?` drop - the test
  must go red.
- **L4 UI:** with the injected failure, the message shows the right page number and both actions are
  hittable; "Continue" proceeds with the saved pages. With a stale odometer seeded, completing a km
  reminder shows the hint with the number; with a fresh odometer it does not.
- `swift test` and the app unit bundle counts must rise; report before and after.

## Vacuous traps

- A message that renders but whose "Rescan page" does nothing, or rescans all pages.
- A staleness check against the odometer of the *reminder's creation* instead of the car's last known
  reading.
- A hint that shows for time-only reminders (it must not: the time cycle does not use the odometer).
- RU strings built by concatenating "Страница" + number + a fragment.

## Screenshots

EN and RU, dark theme, from a booted simulator OUTSIDE a test run (`simctl` and `xcodebuild test`
fight over the device): the page-failure message on the service entry, and the stale-odometer hint on
the reminder-complete sheet. Save to `design/screenshots/PJ.43-page-not-saved.png`, `-ru.png`,
`PJ.43-stale-odometer.png`, `-ru.png`. `simctl launch` on a running app ignores new arguments -
`terminate` first. You cannot see your screenshots: state what you captured, never that it looks right.

## Standing fences

- `swiftlint lint` from the repo ROOT, never from `ios/`.
- Check the test COUNT, not only the exit code.
- Never stash, move or `git checkout` for a clean baseline; prove a test's teeth by mutating one line
  and restoring it.
- Never `pgrep -f` / `pkill -f`; use `-x`.
- Assume you are not alone in the checkout: never move, rename or revert a file you did not create.
- Assert a frame against the window, never `isHittable` alone.
- Git is read-only for you: never commit, add, stash, reset, restore.

## Report back

Exit codes observed for every check; test counts before and after; each new test run or only written;
the failing-then-passing output of the two mutations; the line where the page used to be dropped; the
staleness threshold, where it lives and why that value; screenshots captured; **anything you found and
did not fix** (including other ERRORS.md rows with no rendering).

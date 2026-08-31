# T.1 – seven launches inherit the previous test's database (and PJ.4b is the proof)

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`:

- `ios/App/UITests/` – the launch helpers and, where needed, the seeds a test asks for
- `ios/App/Sources/**/*TestSeed.swift` – only if a seed must become able to establish the state a
  test needs; say so if you touch one

Do **NOT** touch `docs/TASKS.md`, `backend/`, or `ios/Sources/TankbookCore/` (no product change is
needed for this row - if you believe one is, stop and report instead).

Write code first, explore second.

## Use this simulator

`iPhone 17`. **Never** `pgrep -f`/`pkill -f` for a build - a brief is part of the process command
line and that pattern once killed a sibling agent 48 minutes in. Use `pgrep -x xcodebuild`.

## The defect, measured

Seven launch sites start the app **without `-homeResetDatabase`**, so each inherits whatever the
previous test left behind:

| Suite | Launch sites |
|---|---|
| `ConfirmManualUITests` | lines 203, 359 |
| `AnomalyInsightUITests` | 125 |
| `DiscardGuardUITests` | 15 |
| `HomeUITests` | 465 |
| `TankLevelUITests` | 145 |
| `TrendsUITests` | 172 |
| **`AddVehicleUITests`** | its helper is `if !args.isEmpty { app.launchArguments = args }`, so the **default launch passes no arguments at all** |

Verify that table yourself before relying on it - this project's briefs have carried wrong file
lists six times, and being right about it is part of the job.

Why it matters, twice measured already: `ConfirmManualUITests` was **27/28 red run alone** and green
in company (PJ.7e), and `AddVehicleUITests` shows **Welcome** on a pristine device and hits the
**3-car cap** on a dirty one. A suite that only passes in company is not green.

## The acceptance case: PJ.4b

`RemindersUITests.testReminderSavesDespiteNotificationsDenied` fails deterministically (3/3 alone,
and in the full suite). The element dump shows why: `reminderFormAddDateButton` is **absent because
the form already carries a due date** - `reminderFormDateButton` labelled `Feb 29, 2028` and a
`reminderFormClearDateButton` are present, so `hasDueDate` is true and the Add-date button correctly
does not render (it is the `else` branch).

`Feb 29, 2028` is `ReminderTestSeed`'s `byAdding: .month, value: 18` (lines 62, 98) measured from
2026-08-31, clamped off the non-existent 31 February. **So the form under test is showing seeded
data rather than a new reminder.** Find out why and fix the cause.

**Already ruled out, do not redo:** it is not PJ.7g - reverting its three Reminders files to their
pre-PJ.7g content still fails. It is not a flake - 3/3 deterministic.

## Named vacuous traps

- **Adding `waitForExistence` at `RemindersUITests.swift:298` so the tap lands.** That makes the
  symptom vanish while the wrong form is still presented. The test must prove the form is **new**.
- **Adding `-homeResetDatabase` to a launch whose seed then silently no-ops.** Seeds here are
  idempotent and do nothing on a populated database, so a reset without the right seed gives an
  EMPTY screen that some assertions still pass on. Assert the state you think you created.
- Making a suite pass by reordering tests, or by depending on alphabetical execution order.
- `XCTSkip`, deleted assertions, or a `sleep`.

## The bar

**Every suite you touch must pass BOTH ways**, and you must report both:

1. **Alone**, on a freshly uninstalled app:
   `xcrun simctl uninstall <device> app.tankbook.Tankbook` then `-only-testing:` that suite.
   (Note `simctl uninstall` does NOT clear the Keychain - clear a stub session explicitly if the
   suite depends on being signed out.)
2. **In company**, in a multi-suite run.

## Checks

- `swift build --package-path ios` exit 0; `swiftlint lint` exit **0 from the repo root**.
  **`swift build` does not compile `ios/App`** - also `xcodebuild ... build` → `BUILD SUCCEEDED`.
- `swift test --package-path ios` – whole suite, never subsetted; it stood at **1121**.
- Each touched suite alone AND together, per the bar above, then
  `scripts/check-ui-test-count.sh` on each log - a suite can print "passed" while some of its tests
  never ran, which happened here on 2026-08-30.
- **Mutation**: remove `-homeResetDatabase` from one launch you fixed and confirm that suite fails
  **when run alone**; restore by copying a backup back and verifying `md5` - **never**
  `git checkout`.

## Report back

Whether my table of seven sites was right; the cause of PJ.4b's seeded form and how you fixed it
(not merely how you made it pass); per-suite alone/in-company results with observed counts; the
mutation result and `md5`. Say whether you **ran** the tests or only wrote them. Do not commit.

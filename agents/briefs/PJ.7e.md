# PJ.7e – ConfirmManual: two tests red in the full suite, and the whole suite red on a clean device

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. Expected files:

- `ios/App/UITests/ConfirmManualUITests.swift`
- `ios/App/Sources/ConfirmManual/ManualFillUpTestSeed.swift`
- `ios/App/Sources/Welcome/WelcomeGate.swift` (only for part 2, and only if that is where the fix
  belongs)

Do **NOT** touch `docs/TASKS.md` (the orchestrator ticks it at merge; editing it conflicts with
other lanes), `ios/App/UITests/WelcomeUITests.swift`,
`ios/App/UITests/TankbookShellUITests.swift`, or
`ios/App/UITests/UpdateRequirementUITests.swift` – concurrent lanes own those.

Write the fix first, explore second.

## Use this simulator

`iPhone 17` unless a step below names another. **Never** `pgrep -f` / `pkill -f` for a build: a
brief is part of the process command line, so an `-f` pattern matches a sibling agent, and that has
killed one 48 minutes into its task. Use `pgrep -x xcodebuild`.

## The evidence, measured by the orchestrator – start from it

There are **two separate defects here**. Do not conflate them.

### Part 1 – the two failures that make the full suite red

Full UI suite, `iPhone 17`, idle machine, 2026-08-30: 252 executed, 5 failures. Two are yours:

```
ConfirmManualUITests.swift:133: testCrossCheckMismatchShowsAmberRefusesLockButSaveAnywayWorks
    Failed to get matching snapshot: No matches found for Descendants matching type TextField
ConfirmManualUITests.swift:391: testReducedMotionLockStillLandsWithoutAnimation
    (same failure)
```

Both die on the **price** field – `price.typeText("2.10")` / `price.typeText("2.00")` – after
`focusField` returned. The shape is documented in `HANDOVER.md`: `typeText` after a successful tap,
with the field **leaving the accessibility tree**.

**What is new, and why this is not "just the known flake":** `HANDOVER.md` records this pair as
*device-specific* – failing on `iPhone 17 Pro`, **passing on `iPhone 17`**. They have now failed on
`iPhone 17`, in a full run on an idle machine. Either the claim was always too optimistic or
something changed. Establish which, on evidence: run the pair on `iPhone 17` several times and, if
useful, on `iPhone 17 Pro` (a sibling agent may be using `17 Pro` – check with `pgrep -x xcodebuild`
and prefer `iPhone 17e` or `iPhone 17 Pro Max` if you need a second device).

The fix must make the pair **deterministically green** without weakening what they assert:
`testCrossCheckMismatch...` proves the amber cross-check message renders, the check line refuses to
lock, and **Save anyway still works**; `testReducedMotionLock...` proves the lock state still lands
with Reduce Motion forced on. Both need all three numbers actually typed – the mismatch only exists
if total, litres and price are all present.

The likely mechanic is in `focusField` (lines 29-54) and `scrollClearOfSaveBar` (lines 56-75): the
field is scrolled and tapped, then the keyboard or a re-render takes it out of the snapshot before
`typeText` runs. A re-query of the element immediately before typing, or typing through the
keyboard only once focus is confirmed, is the shape of a real fix. **Sleeps are not** – this repo
has an explicit rule against fixing this family with sleeps.

### Part 2 – the suite only passes because an earlier suite left a vehicle behind

Measured twice by the orchestrator:

- `ConfirmManualUITests` run **alone**: 28 executed, **27 failed**.
- After `xcrun simctl uninstall app.tankbook.Tankbook` (clean app data), run alone again: 26
  executed, **25 failed**.

Every one of those failures is the same early assertion – `typeItButton` never appears within 10 s
(`openManualForm`, line 78; `openForm`, line 225). In the full suite these same tests **pass**,
because suites that run earlier leave a vehicle in the database.

The mechanism, already traced – confirm it before fixing:

- `ConfirmManualUITests.launch()` (line 16) passes **only** `-seedVehicleForUITests`: no
  `-homeResetDatabase`, no `-skipWelcome`, no `-presentScreen`.
- `WelcomeGate.shouldShowWelcome()` runs **at app-root init** and returns `!hasVehicle &&
  !hasSession`. None of its escape hatches (`-skipWelcome`, a `-presentScreen`/`-openManualForm`
  debug request, `-homeResetDatabase`) is present for these launches.
- `ManualFillUpTestSeed.seedIfRequested()` creates the vehicle, is **idempotent** ("once a vehicle
  exists it does nothing"), and on an empty database runs **after** the gate has already decided.

So on a device with no vehicle the app shows **Welcome**, Home is not there, and `typeItButton`
never exists. The suite is order-dependent: it passes in a full run and fails alone. That is
precisely how a suite drifts red unseen between full runs, which is what PJ.7b cost.

Fix it so **`ConfirmManualUITests` passes when run alone on a clean device**. Decide where the fix
belongs and justify it: teaching `WelcomeGate` that `-seedVehicleForUITests` is a
tabbed-app harness flag (like `-homeResetDatabase`) is one candidate; seeding before the gate reads
the repository is another. Whatever you choose must keep `WelcomeGate`'s real guarantees intact –
**`-presentWelcome` must still reach the fresh-install state**, and a real vehicle or session must
still suppress Welcome forever. `WelcomeUITests` is another lane's file, so do not edit it, but
your change must not break it.

## Explicitly out of scope

- `TankbookShellUITests`, `UpdateRequirementUITests`, `WelcomeUITests` – other lanes.
- Re-running the **full** 28-minute UI suite; that is the orchestrator's, at phase completion.
- Anything about the `AddVehicle` device-specific pair.

## Do not "fix" these by weakening them

- No `sleep` / `Thread.sleep` / raised timeouts as the fix for the `typeText` pair.
- No `XCTSkip`, no deleted assertion, no assertion that cannot fail.
- Do not drop a typed value to dodge the price field: without all three numbers the cross-check
  mismatch does not exist and the test becomes vacuous.
- For part 2, do not paper over it by adding `-homeResetDatabase` to a launch whose test then
  depends on a seed that silently no-ops. Seeds in this repo are idempotent and **do nothing on a
  populated database** – verify the state you think you created.

## Checks

- `cd ios && swift build` exit 0; `swiftlint lint` exit **0 run from the repo root**.
- `cd ios && swift test` – **all 1062 unit tests**, never subsetted; report the observed count.
- `xcodebuild ... -only-testing:TankbookUITests/ConfirmManualUITests test` on `iPhone 17`, **the
  whole suite**, twice: once normally, and once immediately after
  `xcrun simctl uninstall <device> app.tankbook.Tankbook` – the clean-device run is the part-2
  gate. Report the **observed counts** both times ("0 tests ... passed" exits 0 and means nothing).
- Mutation-check both parts:
  - Part 1: neuter the cross-check mismatch (e.g. always report `.verified`) and confirm
    `testCrossCheckMismatchShowsAmberRefusesLockButSaveAnywayWorks` **fails** – proving your fixed
    test still discriminates rather than merely running.
  - Part 2: revert your gate/seed change alone and confirm the clean-device run goes **red** again.
  - Restore by copying back a backup file you made first and verifying with `md5`. **Never**
    `git checkout` – it has destroyed uncommitted work in this repo three times.

## Report back

Exact numbers for every run (observed counts and exit codes), which device each ran on, what you
concluded about the `iPhone 17` vs `iPhone 17 Pro` claim and on what evidence, the mechanism you
confirmed for part 2 and where you fixed it, and whether each mutation actually produced a failure
plus the `md5` match after restore. Say whether you **ran** the tests or only wrote them. Do not
commit – the orchestrator verifies and commits.

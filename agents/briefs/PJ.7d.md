# PJ.7d – two UI tests that never reach Home: the shell back-path walk and the save-under-required journey

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. Expected files:

- `ios/App/UITests/TankbookShellUITests.swift`
- `ios/App/UITests/UpdateRequirementUITests.swift`
- app sources under `ios/App/Sources/` **if and only if** the defect is in the app rather than in
  the test (decide from evidence, not convenience – see below).

Do **NOT** touch `docs/TASKS.md`; the orchestrator ticks it at merge, and editing it conflicts with
other lanes. Do **NOT** touch `ios/App/UITests/ConfirmManualUITests.swift`,
`ios/App/UITests/WelcomeUITests.swift`, `ios/App/Sources/Welcome/`, or
`ios/App/Sources/ConfirmManual/ManualFillUpTestSeed.swift` – concurrent lanes own those.

Write the fix first, explore second.

## Use this simulator

`iPhone 17 Pro` – `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`. A sibling agent is
using `iPhone 17`; do not touch it, and **never** run `pgrep -f` or `pkill -f` for a build (a brief
is part of the process command line, so an `-f` pattern matches the sibling agent and has killed
one before). Use `pgrep -x xcodebuild` if you must check whether a build is running.

## The evidence, measured by the orchestrator – start from it

A **full UI suite** run on 2026-08-30 (`iPhone 17`, machine otherwise idle): **252 executed, 5
failures**. Two of the five are yours:

```
TankbookShellUITests.swift:123: testHomeTabEdgesHaveBackPaths        XCTAssertTrue failed  (32.4 s)
UpdateRequirementUITests.swift:176: testFillUpStillSavesUnderRequired XCTAssertTrue failed  (13.7 s)
```

Both **reproduced in a second, isolated run** (10.1 s and 13.7 s), so neither is machine contention.

The two assertions:

- `TankbookShellUITests.swift:118-125` – `launch()` uses
  `["-homeResetDatabase", "-seedHomeEmptyVehicle"]`, then **taps `settingsButton` immediately**
  (line 122) with no prior `waitForExistence`, and line 123 waits 5 s for the `Settings` nav bar.
  Note what its siblings do: `testThreeTabRootsExist` waits 10 s for `tabbar.log` first. A tap on
  an element that is not there yet **silently misses** – it does not fail at the tap, it fails at
  the next assertion, which is exactly the shape here.
- `UpdateRequirementUITests.swift:174-176` – `launch(requiredArgs + ["-seedVehicleForUITests"])`,
  i.e. `-homeResetDatabase -configAppUpdate 1.2.0 1.4.0 -configRunningVersion 1.0.0
  -seedVehicleForUITests`, then waits **10 s** for `typeItButton` on Home and never sees it. Its
  siblings in the same file that pass all use `-presentScreen`, so this is the only test in the
  file that has to reach **Home** under `.required`.

## The tree has moved since those measurements

They were taken at commit `4968590`; `HEAD` is now `8f680b3`. The three commits in between changed
only the Welcome hero copy and the app icon - nothing either of your tests touches - so the evidence
stands. But **re-confirm both failures against current `HEAD` before fixing**, and if a failure has
changed shape, report that rather than fixing the old one. A brief in this repo has been stale
before; the shipped source always wins over this document.

## The question to answer first, with evidence

For each failure, decide **which of these it is**, and say how you know:

1. **A test-harness defect** – a missing wait, a tap before the screen exists, an ordering
   assumption. Fix the test.
2. **A real app defect** – e.g. an `.required` update notice or overlay that keeps Home's
   `typeItButton` from rendering or from being in the accessibility tree. Fix the app, and keep the
   test asserting the journey.

The second possibility is load-bearing for `UpdateRequirementUITests`: hard rule 1 is local-first,
and that test exists to prove **a fill-up still saves when the server says the app is out of
date**. If the app genuinely cannot reach the manual entry path under `.required`, that is a
launch-blocking bug and the test is right to be red – say so plainly rather than relaxing it.

Capture the actual screen state rather than guessing: dump the accessibility hierarchy
(`app.debugDescription`) at the point of failure and read what IS on screen. Whatever you conclude,
quote the evidence in your report.

## Explicitly out of scope

- `ConfirmManualUITests` (2 failures) and `WelcomeUITests` (1 failure) from the same run – other
  lanes own them.
- Re-running the **full** UI suite. It is 28 minutes and belongs to the orchestrator at phase
  completion. Run only the two suites named below.
- Any change to `docs/TASKS.md`.

## Do not "fix" these by weakening them

Named vacuous traps for this task:

- Adding a `sleep`/`Thread.sleep` or bumping timeouts until it passes. The documented flaky family
  in this repo is explicitly **not** to be fixed with sleeps. A `waitForExistence` on the element
  you are about to tap is a correct fix; a blind delay is not.
- Deleting an assertion, or replacing `XCTAssertTrue(...)` with something that cannot fail.
- Changing `testFillUpStillSavesUnderRequired` so it no longer saves an entry and asserts it
  **exists in the log** – that journey is the whole point of the test.
- `XCTSkip`ping either test.

## Checks

- `cd ios && swift build` exit 0; `swiftlint lint` exit **0 run from the repo root**.
- `cd ios && swift test` – **all 1062 unit tests**, never subsetted. Report the observed count.
- `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination
  'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TankbookUITests/TankbookShellUITests
  -only-testing:TankbookUITests/UpdateRequirementUITests test` – **the two whole suites**, not just
  the two tests, because a fix to a shared helper can break a sibling. Report the **observed test
  count**: a filter matching nothing prints "Test run with 0 tests ... passed" and exits **0**.
- **Mutation-check whatever you fixed.** If the fix is in the app, break the app behaviour in its
  subtlest form and confirm the test fails. If the fix is in the test, prove the test still
  discriminates: break the app path it walks (e.g. remove the back chevron's destination, or make
  the save a no-op) and confirm a **red**. Restore by copying back a backup file you made first and
  verifying with `md5` – **never** `git checkout`, which has destroyed uncommitted work here three
  times.

## Report back

Per failure: which of the two causes it was and the evidence; the exact edit; the observed test
counts and exit codes for every command; whether the mutation actually produced a failure, and the
`md5` match after restore. Say whether you **ran** the tests or only wrote them. Do not commit –
the orchestrator verifies in its own hands and commits.

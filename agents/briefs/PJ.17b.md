# PJ.17b – the empty-scan caption test races, and it is red on main

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`:

- `ios/App/UITests/ConfirmManualUITests.swift`
- `ios/App/Sources/ConfirmManual/` **only if** you prove a real app defect (decide from evidence)

Do **NOT** touch `docs/TASKS.md`, `ios/App/Sources/Persistence/AppStore.swift`, the attachment
stores, or `docs/SECURITY.md` – a sibling lane (PR.16) owns those.

Write code first, explore second.

## Use this simulator

`iPhone 17`. A sibling uses `iPhone 17 Pro`. **Never** `pgrep -f`/`pkill -f` for a build – a brief
is part of the process command line and that pattern once killed a sibling agent 48 minutes in.
Use `pgrep -x xcodebuild`.

## The evidence – measured twice, independently

`ConfirmManualUITests.testEmptyScanWithPhotoFocusesTotalAndShowsCaption` (PJ.17) is **red on clean
`main`**:

- The PJ.48 agent saw it fail 2 of 3 full runs, then reproduced it **2/2 in isolation** with its own
  work stashed and its untracked files moved aside, restoring byte-for-byte afterwards. Removing
  PJ.48's `.receiptAttachSource` modifier did not change it.
- The orchestrator reproduced it independently after PJ.48 merged: 27 of 28 passing, this one
  failing at 9.8 s.

It is **intermittent, not deterministic** - it passed in two earlier full runs the same day. Its
own description points at a keyboard/`isHittable` timing race on the empty-scan caption.

This is the **third suite this week to drift red between full runs** (PJ.7b, the GatewayCapture
pair, now this).

## What to build

De-race it the way **P2.16 did the budget tests**, which is the pattern of record here: widen from
whichever side the test allows, **with no claim loosened**. Read that fix first
(`git log --oneline --all | grep P2.16`, then the diff of `GatewayCaptureUITests.swift`).

The test's guarantee must survive intact: an **empty scan with a photo** focuses the Total field and
shows its caption. That is PJ.17's whole point - the failure state IS the manual form, keyboard on
Total, photo kept (hard rule 15 and `ERRORS.md` F1). Do not weaken what it asserts.

**Then ask what else in that file races the same way.** This repo has twice written a fix covering
exactly the defect in front of it and missed a worse sibling - both times while fixing the previous
version of it. `ConfirmManualUITests` is 28 tests; several drive the keyboard. Name the ones you
checked, even if you change nothing.

Note `focusField` was rewritten recently (PJ.7e) to stop on a **geometric** condition rather than
`isHittable`, because `isHittable` does not model the pinned save bar - a tap "on" a field under
the bar hit Save and saved the entry. If this test uses the older pattern, that is a strong lead.

## Named vacuous traps

- **Re-running until it passes and calling that a fix.** Require it green **5/5 in isolation** and
  once inside the whole suite, and report both counts.
- A `sleep` / `Thread.sleep` / a raised timeout as the fix. Explicitly forbidden for this family.
- `XCTSkip`, a deleted assertion, or an assertion that cannot fail.
- Dropping the photo or the caption from the test to make focus deterministic - that is the
  guarantee, not the scaffolding.

## Checks

- `swift build --package-path ios` exit 0; `swiftlint lint` exit **0 from the repo root**.
  **`swift build` does not compile `ios/App`** – also run `xcodebuild ... build`, report
  `BUILD SUCCEEDED`.
- `swift test --package-path ios` – whole suite, never subsetted; it stood at **1094**.
- `xcodebuild ... -only-testing:TankbookUITests/ConfirmManualUITests test` on `iPhone 17`, the
  **whole suite**, and separately the single test **5 times**. Report every observed count; a
  filter matching nothing prints "0 tests ... passed" and exits **0**.
- Run `scripts/check-ui-test-count.sh <your log>` – a suite can print "passed" while some of its
  tests never ran; that happened here on 2026-08-30.
- **Mutation**: break what the test protects (e.g. do not focus Total on an empty scan, or drop the
  caption) and confirm it **fails**; restore by copying back a backup and verifying `md5` – **never**
  `git checkout`.

## Report back

Whether it was a test race or a real app defect, and the evidence; what you changed; the 5-run
isolation result and the full-suite result; which sibling tests you checked for the same race; the
mutation result and the `md5` match. Say whether you **ran** the tests or only wrote them. Do not
commit.

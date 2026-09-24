# PU.75 - the Vision pass only when it decides, and batched predictions

## Where you may write
Only inside `/Users/sbelyaev/repos/fuel-counter-ios-wt-pu75` (a git worktree on branch `wt/pu75`).
Write code first, explore second. Do not commit.

## What to build (the research note decides the scope - `agents/research/PU.75.md` §0 and §3)
Two changes that move no pixel; build them as the note's M1 and M2 describe, nothing more:
- **M1, lazy text-line pass.** In `PumpDisplayCapture.decideAt`
  (`ios/Sources/TankbookCore/Extraction/PumpReader/PumpDisplayCapture.swift`), compute
  `textLineCount(upright)` only on the slow path, after `fastVerdict` returns false; the fast path's
  detection carries the note's sentinel `-1` ("not measured"). Every consumer of `Detection.textLines`
  is diagnostic (the note lists them); make each tolerate `-1`.
- **M2, batched predictions.** In `PumpSegmentsModel.swift`, a batched sibling of
  `probabilities(cell:)` using `MLModel.predictions(fromBatch:)` over an `MLArrayBatchProvider`, the
  per-crop feature providers built exactly as today; use it for the read's 5-crop TTA
  (`PumpReader.averaged`) and the verifier's per-candidate margin pass, averaging in the same order.
**Out of scope (the note's own fence):** every vImage replacement (M3 - they resample differently,
§0.2), the detector compression spike (M4), any Core Image / Metal / C path - those need the owner.

## The gate: a speed change moves NO reading
The note's §5.3 identity battery: the app path's committed cells must be IDENTICAL before and after.
Run `cd ios && swift test --filter "PumpReaderPipelineTests/(gateMirror|livePath)"` on `HEAD` first
(record committed/correct) and again with your change - the counts and the WRONG list must match
exactly. Also `PumpDisplayCaptureTests` and `PumpLeakConsequenceTests` with `PUMP_LEAK=1` (routing
must not change: 6 of 116 routed, 0 committing).

## Timing - Release, never Debug
`cd ios && swift build -c release --product pump-read`, then time `timingsMs` (appDecide,
appClassifyAndRead) over at least 10 pump stills and 5 receipts, before and after, same machine,
reporting medians; say if the machine was loaded.

## Checks - by exit code, from the worktree root
`cd ios && swift build --build-tests`; `swiftlint lint --quiet` from the ROOT (0 errors); the two
filtered runs above; the full `cd ios && swift test` (report failures; only ones that also fail on
`HEAD` are acceptable - prove it). The app target: `xcodegen generate && xcodebuild -project
Tankbook.xcodeproj -scheme Tankbook -destination 'platform=iOS Simulator,name=iPhone 17' test
-only-testing:TankbookTests` - report the count.

## Tests you must add
- M2: batched probabilities equal sequential ones for the shipped model on a fixture cell (bitwise).
- M1: a fast-path detection reports `textLines == -1`; a slow-path one reports a real count.
- The mutation that must go red: make the batched path average in a different order or drop a crop -
  the equality test fails. Run, paste the red output, restore.

## Report back
Exit codes and counts; before/after committed cells (must match); the Release timing table; the
mutation's red output; anything found and not fixed.

## Resumed run (2026-09-24, after a connectivity stall)
Your first run stalled mid-verification. The worktree already holds your M1+M2 edits and tests - do
NOT rewrite them; review them, then finish only what is missing. Already done, with results in
`$TMPDIR/opencode/pu75-*.txt`: HEAD tree at `$TMPDIR/opencode/pu75-head`; live path before/after
47/47 = 47/47 (identical); `PumpDisplayCaptureTests` green before (9) and after (10); the HEAD leak
run (6 of 116 routed, 0 committing, 2840 s). Still to do: `gateMirror` before/after if missing; the
leak run on the CHANGED tree; the Release timing table; `swift build --build-tests`; swiftlint from
the root; the full `swift test`; the app-target `TankbookTests` count; the mutation's red output.

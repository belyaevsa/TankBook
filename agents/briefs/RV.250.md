# RV.250 - the gate never runs the app-target unit bundle

**no-scenario: the gate itself.** `[!]`. Sibling of `RV.174`, which made `scripts/gate.sh` compile
the app - it still does not TEST it.

`RV212ServiceCreateDoorTests.testAMountedTireSetWithNoOdometerStillRefuses` failed from `RV.214`
(`daa6959`) until `RV.247`'s agent noticed it two rows later: `RV.214` changed
`ServiceEntryFormState.saveReadiness` to branch on `mode == .tires`, the test set only `tireSetId`,
and `TankbookTests` - the app-target XCTest bundle, 160+ tests - is run only when a brief names one
of its suites. The orchestrator corrected the test with `RV.247`; this row closes the door.

## Build

Add the whole app-target unit bundle to `scripts/gate.sh` as its own step after `swift test`:
`xcodebuild test -only-testing:TankbookTests` on the simulator destination the UI suites use, **in
its own invocation** (the two-bundle rule - never combined with `TankbookUITests`), reporting its
count and stopping on non-zero. Keep the UI bundle per-suite and per-brief; it is the slow one.
`docs/TESTING.md` -> the baseline gate, and hard rule 14, name the new step. `PREAMBLE.md` is
already "call the gate"; check its wording still holds.

## Teeth - prove them the way RV.174 did

Reconstruct the orphaned test as it was at `daa6959` (`git show daa6959:ios/App/Tests/RV212ServiceCreateDoorTests.swift`
into a scratch copy of the file), run the gate, show it exits non-zero at the new step with the
package steps green, revert. That output verbatim is the deliverable.

## Tests

`scripts/tests/gate.test.sh` gains the step: order package -> lint -> app build -> package tests ->
app-target tests, stop-on-first-failure, the ignored-exit-code trap for the new step.

## Mutation - named

Remove the new step; the reconstructed orphan passes the gate. Restore.

## Note the cost

The app-target bundle takes ~1-2 minutes on top of the gate; say what it measured. If it is much
slower, say so and do not make the gate skip it - that is the row's whole point.

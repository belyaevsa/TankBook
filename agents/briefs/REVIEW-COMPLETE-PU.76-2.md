# REVIEW-COMPLETE-PU.76-2 - re-check review 1's four items

Read-only except `agents/reviews/PU.76-COMPLETENESS-2.md`. Repo `/Users/sbelyaev/repos/fuel-counter-ios`.
Review 1: `agents/reviews/PU.76-COMPLETENESS.md` (INCOMPLETE). Verify each fix in
`agents/research/PU.76-SPIKE.md` with file:line, and do not re-review what review 1 passed:
1. F6 reported as not measured, and B5's re-pinning stated as not done and why.
2. The departures named: B10 (optimiser and init), B11 (augmentation beyond rotations), B9 (quad fit).
3. B7's percentile reconciled (1st vs the note's "99th") with the reason.
4. The apportionment table labels committed vs correct; the parity claim cites
   `/tmp/agentlogs/pu76-parity.log`.
Since review 1 the Swift decode moved from the test target to
`ios/Sources/TankbookCore/Extraction/PumpReader/PumpRowSegmenter.swift` and `pump-read` / the annotator
can load it (`PumpRowDetector.load(contentsOf:)`, `tools/pump-annotate/server.py`): confirm the app
target never calls `load(contentsOf:)` or constructs a `PumpRowSegmenter` (grep `ios/App`), and that
the report's "What was built" table says so. Code comments follow `CLAUDE.md` -> "Code comments".
End with **COMPLETE** or **INCOMPLETE**.

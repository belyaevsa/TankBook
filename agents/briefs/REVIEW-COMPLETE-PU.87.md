# REVIEW-COMPLETE-PU.87 - is the segmenter's ship complete and safe?

Read-only except `agents/reviews/PU.87-COMPLETENESS.md`. Repo `/Users/sbelyaev/repos/fuel-counter-ios`.
Row: `docs/TASKS.md` PU.87. The change: `git diff HEAD --stat` plus the untracked
`ios/App/Resources/RowSeg.mlpackage`, `ios/Sources/TankbookCore/Extraction/PumpReader/PumpReader+Orientation.swift`,
`ios/Tests/TankbookCoreTests/PumpLocatorTimingTests.swift`; ignore `Spike/` (the owner's corpus) and `ml/pump-reader/runs/`.
Evidence: `/tmp/agentlogs/pu87-tiers-2.log`, `pu87-leak-2.log`, `pu87-ui-4.log`, `pu87-gate-3.log`,
`pu87-app.log`; the Release timing line in the row.
Check with file:line, each MET / PARTIAL / MISSING:
1. The app loads the segmenter and nothing loads `DigitRows` any more on the app path
   (`CapturePipeline`, `PumpDisplayCapture.makeReader`, the preview analyser); `PumpRowDetector.load`
   picks the right backend for a compiled `.mlmodelc`.
2. The preview path (pixel buffers) works through `PumpRowSegmenter.rows(in: CVPixelBuffer)`; the
   compute-units choice and its reason are right; `floats(_:)` reads every backing correctly.
3. The gate change is honest: `PumpPhotoGate` 62/61, the live floor 0.98, and the separate
   "no uncautioned wrong cell" assertion - read `measureLive` and `livePath`; the one wrong cell is cautioned.
4. The orientation rule (`PumpReader+Orientation.swift`): the 180-degree comparison, when it runs,
   and that `PumpReaderOrientationTests` discriminates it.
5. The DigitRows move: every reference updated (`pump-read`, the annotator, `pump-auto-annotate.py`,
   `PumpTraceParityTests`); the annotator's shipped marker points at RowSeg.
6. Docs: `docs/EXTRACTION.md` decision 10's PU.87 amendment matches the code and numbers; comments
   follow `CLAUDE.md` -> "Code comments".
7. Hard rules touched: 13 (every pre-fill still editable), 15 (typing still a peer door), 12 (no domain
   values in any new log line).
End with **COMPLETE** or **INCOMPLETE** and what must change.

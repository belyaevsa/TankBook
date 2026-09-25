# REVIEW-COMPLETE-PU.87-2 - re-check review 1's findings

Read-only except `agents/reviews/PU.87-COMPLETENESS-2.md`. Review 1: `agents/reviews/PU.87-COMPLETENESS.md`.
Verify each with file:line; do not re-review what review 1 passed:
1. **Gate.** The two `swift test` failures are outside PU.87: `PumpRowAssignmentTests` reads only the
   hand-annotated windows (no locator) and passes on the committed corpus
   (`/tmp/agentlogs/pu87-assignment-committed-corpus.log`, run in the PU.77 worktree: 1319/1330) - the
   main checkout's failure is the owner's uncommitted, in-progress annotations under `Spike/`, which
   no row may touch; `CaptureOrientationTests` passes 3/3 isolated
   (`/tmp/agentlogs/pu87-capture-orientation-isolated.log`) - the Vision `e5rt` flake filed as RV.306.
   App-target bundle 303/303 (`/tmp/agentlogs/pu87-app-2.log`); lint 0. Judge whether this discharges
   the gate item given a corpus the orchestrator may not modify.
2. **Rule 12.** The WRONG lines print got/want. `docs/LOGGING.md` §1 scopes the privacy classes to
   "both tiers" (the app and the server); these are test-harness diagnostics over the committed PUBLIC
   corpus fixtures, the convention every scorer in `PumpReaderPipelineTests` already uses
   (`gateMirror`'s WRONG lines). Judge whether rule 12 applies; if you still hold it does, say which
   line of CLAUDE.md or LOGGING.md makes test output a tier.
3. **Strides.** `PumpRowSegmenter.floats(_:)` now checks the layout and falls back element by
   element; `PumpRowSegmenterInputTests.floatsFollowStrides`; mutation red (`/tmp/agentlogs/pu87-mutation-strides.log`).
4. **Camera path.** `PumpRowSegmenterInputTests.pixelBufferMatchesImage` feeds a BGRA pixel buffer.
5. **Comments.** `PumpRowSegmenter.swift` type doc, `PumpRowDetector.swift` type doc and `detect(in:
   CVPixelBuffer)` doc, `PumpReaderOrientationTests.swift` header, the `PumpReaderPipelineTests` floor comment.
6. **Evidence.** Timing `/tmp/agentlogs/pu87-timing.log` (and the row's range); mutations
   `/tmp/agentlogs/pu87-mutation-{strides,orientation,uncautioned}.log`.
End with **COMPLETE** or **INCOMPLETE**.

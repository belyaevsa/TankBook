# REVIEW-PU-COMPLETENESS – is this pump row actually done?

*The template. Every run gets its own copy, `agents/briefs/REVIEW-COMPLETE-<row>.md`. Dispatched to a
reviewing agent **after every row in the PU.67 tranche is built and gated, before it is committed**
(product owner, 2026-09-23: *"the agent reviewer each time validates the completeness of the
implementation"*). It is to a pump row what `REVIEW-SCENARIO.md` is to a journey: a row is not done
because its code compiles and its tests pass – it is done when what the row promised is in the tree,
wired, measured and written down. The orchestrator commits only on a `COMPLETE` verdict.*

## Fill these in for the run

- **Row:** `PU.75` - batched predictions, vectorised warps, and the Vision pass only when it decides
  (`docs/TASKS.md`, marked `[~]` in the tree pending THIS review - read its "M1 + M2 SHIPPED" text and
  its "Left open, and why").
- **Research note:** `agents/research/PU.75.md` (M1-M4, adaptations A1-A5, the identity battery §5.3).
- **The diff under review** (`git diff HEAD` in `/Users/sbelyaev/repos/fuel-counter-ios`, these files
  only): `PumpDisplayCapture.swift` (M1), `PumpSegmentsModel.swift` and `PumpReader.swift` (M2),
  `PumpDisplayCaptureTests.swift`, `PumpSegmentsModelTests.swift`, `docs/LOGGING.md` (the `-1`
  sentinel), `tools/pump-annotate/pipeline.js` (shows it as not measured), the PU.75 row. Ignore the
  RV.306 row (filed beside it).
- **Gate evidence:** identity on `main` after PU.74 - annotated 123/123, live 47/47
  (`/tmp/agentlogs/pu75-identity-main.log`); the builder's before/after on its worktree base and the
  Release timing table (`/tmp/agentlogs/PU.75.last.md`, `/tmp/agentlogs/PU.75-codex.log`); the batch
  mutation's red output (same report); gate `/tmp/agentlogs/pu75-gate-2.log` - build, lint, app build
  exit 0, `swift test` red on one Vision `e5rt` failure that the A/B shows is pre-existing (without
  PU.75 2 of 3 full runs failed, with it 1 of 3: `/tmp/agentlogs/pu75-e5rt-ab.log`), filed as RV.306;
  the app-target bundle was not reached by that gate - run
  `xcodebuild ... -derivedDataPath /tmp/pu75-review-dd -only-testing:TankbookTests test` yourself if
  you judge it needed, and say so.

**Row-specific:** judge whether shipping M1+M2 as `[~]` with vImage, device timing and the detector
spike named as open is honest against the row's Checks cell and the note's fence (A4/A5); check that
every consumer of `Detection.textLines` tolerates `-1` (the note lists them: logging, TraceServe,
`PumpReadTool`, the pipeline view, tests); confirm batching preserves the average's summation order.

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:**
`agents/reviews/PU.75-COMPLETENESS.md`. No code, no builds that write, no commits. You may run
read-only tools and the pump measurement tool (`swift run PumpReadTool`) if a number is missing –
say that you did, and that the machine may be loaded.

## What you are checking – each item MET, PARTIAL or MISSING, always with `file:line`

1. **Fidelity to the published method.** The code does what the research note says the paper does.
   Every departure is one the note lists and justifies, or one the product owner approved. An
   unlisted departure is MISSING, however good it looks – name the paper section it departs from.
2. **Wired into the app path, not only the harness.** The change reaches `PumpDisplayCapture.classify`
   and `CapturePipeline` (the path the phone runs), in Release as well as Debug. A method reachable
   only from `PumpReadTool`, a test or a `#if DEBUG` seam is the "docs naming behaviour with no call
   site" shape (`docs/DEFECT-PATTERNS.md`) – MISSING.
3. **Measured on the app path, on the named population.** The live-path floor
   (`PumpReaderPipelineTests.livePath`, the app's `classify`) ran, the committed/correct counts are
   in the gate evidence, and they match `PumpPhotoGate`'s reader constants. The row's own claimed
   movement is reported over the population the row named, with the interval beside the point
   estimate once PU.68 has landed. **Zero new wrong readings** unless the row says otherwise and the
   owner agreed.
4. **No regression elsewhere.** The receipt leak (non-pump fixtures routed as a pump) did not rise;
   the annotated floor and the law's oracle ratchet did not fall; latency, if the row touches a hot
   path, has a Release number.
5. **Tests that would fail.** Each promise has a test, and the orchestrator's mutation of it turned
   the test red (the mutation and its red output are in the gate evidence). A test that stays green
   when its behaviour is removed is PARTIAL.
6. **Docs reconciled.** `docs/EXTRACTION.md` (the pump reader section, and a numbered decision if the
   row changes one), `docs/TASKS.md` (the row's result, numbers and what was left), `docs/ERRORS.md`
   and `docs/JOURNEYS.md` J4/F2 if the user sees anything different, `CLAUDE.md` comment rules in
   every touched file (current truth only, no task ids in code comments).
7. **Everything the row promised.** Read the row's own Checks cell sentence by sentence; each
   sentence is MET, PARTIAL or MISSING. A promise quietly dropped is how PU.59's second amendment
   nearly shipped untested.

## Verdict

End with one of:
- **COMPLETE** – every item MET. The orchestrator may commit.
- **INCOMPLETE** – list each PARTIAL/MISSING item with what is needed; the orchestrator fixes it and
  re-dispatches this review (a fresh copy, same row). A gap the row cannot close becomes a new row,
  drafted here, never silently dropped.

**The standing fences appended below were written for build briefs.** Their write and stash/checkout rules apply to you; their standing checks do not.

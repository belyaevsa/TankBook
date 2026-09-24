# REVIEW-PU-COMPLETENESS – is this pump row actually done?

*The template. Every run gets its own copy, `agents/briefs/REVIEW-COMPLETE-<row>.md`. Dispatched to a
reviewing agent **after every row in the PU.67 tranche is built and gated, before it is committed**
(product owner, 2026-09-23: *"the agent reviewer each time validates the completeness of the
implementation"*). It is to a pump row what `REVIEW-SCENARIO.md` is to a journey: a row is not done
because its code compiles and its tests pass – it is done when what the row promised is in the tree,
wired, measured and written down. The orchestrator commits only on a `COMPLETE` verdict.*

## Fill these in for the run

- **Row:** `PU.69` – row angle by a fast Hough transform, with a confidence (`docs/TASKS.md`, ticked in
  the tree pending THIS review - read its "Built" text)
- **Research note:** `agents/research/PU.69.md` (A1-A10)
- **The diff under review:** `ios/Sources/TankbookCore/Extraction/PumpReader/PumpFastHough.swift` (new),
  `PumpRowDeskew.swift`, `ios/Tests/TankbookCoreTests/PumpRowDeskewTests.swift`,
  `PumpRowDeskewCorpusTests.swift` (new), the PU.69 paragraph in `docs/EXTRACTION.md`, the PU.69 row.
  IGNORE the concurrent, not-yet-committed PU.78 / PU.72 / PU.81 edits elsewhere in the tree.
- **The orchestrator's gate evidence:** `PumpRowDeskewTests` 6/6; the corpus agreement (Release):
  `PUMP_DESKEW=1 swift test -c release --filter PumpRowDeskewCorpusTests` - FHT median 0.60 / p90 1.97 /
  >6 deg 0.66 / 2.7 ms per row, the old sweep (file swapped back temporarily) 0.73 / 1.98 / 1.00 /
  8.4 ms; mutations `/tmp/agentlogs/pu69-mutation-mirror.log` (red, 5 issues) and
  `pu69-mutation-sec3.log` (red); app unit bundle 301/301 (`/tmp/agentlogs/pu69-app.log`); lint 0.

**Row-specific:** check fidelity to Algorithm 1 and A1-A10 - in particular the sign convention
(positive = clockwise, y down), the black-zone handling (A8: here by padding to height + width rows
so no pattern wraps - say whether that satisfies A8), whether the sub-slope interpolation matches A2,
and whether keeping `rowSize`/`largeTurn` for OUTPUT sizing only departs from A7 (the note retires
them; the build keeps the output geometry unchanged). The 48 -> 96 px input change is claimed under
A1's named fallback - judge that claim. The row's "app path live >= PU.67's count" check is deferred
to PU.67's re-measure (row deskew is off in the app) - say whether the row text makes that plain.

## Second pass

Review 1 (`agents/reviews/PU.69-COMPLETENESS.md`) was INCOMPLETE on four items; closed since (verify):
1. Full package suite on the composite tree: `/tmp/agentlogs/pu69-swifttest.log` - 2285 tests, the
   only failures the two floors that count pump-275, which the owner's annotator has open with its
   `reviewed` flag cleared (67 stills / 181 cells instead of 68 / 183) - a corpus state, not this diff;
   live 47/47, oracle 774 / 0.9987, fragility 0.041; `PumpTraceParityTests` in the same log.
2. F6: `/tmp/agentlogs/pu69-corpus-release.log` - AUROC 0.653 / 0.689 / 0.700 on the train split.
3. The refusal-path latency re-homed to PU.67 in the row; the sweep baseline log
   `pu69-corpus-release-oldsweep.log`; the leak argument in the row.
4. Both comments fixed.

## Third pass

Review 2 (`agents/reviews/PU.69-COMPLETENESS-2.md`) listed four fixes; closed since (verify each):
1. Latency: the row and EXTRACTION now say 8.4 -> 2.7-3.1 ms across four Release runs, the higher
   ones with PU.73's training running; logs `/tmp/agentlogs/pu69-corpus-*.log`.
2. Row text: the 188 re-count sentence, within-1-deg 0.697 [0.628, 0.758] vs the note's sweep
   baseline, the bridge re-homed to PU.76.
3. PU.70 references re-pointed to PU.76 (row and EXTRACTION).
4. Pins and mutations: `PumpRowDeskewTests` 10/10 - new `transformDoesNotWrap`,
   `confidenceIsAlwaysReported`, `subSlopeRefinement` (one-step tolerance, with the reason the
   refinement is pinned on the corpus instead), `slantedStrokesAreNotATurn`; mutation logs for
   wrap (red), vertical-band fusion (red, "turned to 10.3 deg"), refinement (corpus pair
   `pu69-corpus-no-interp.log` vs `-with-interp.log`: median 0.63 vs 0.60).
Carried items: PU.65's "max 18" corrected; PU.67's row notes the FHT re-measure.

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:**
`agents/reviews/PU.69-COMPLETENESS-3.md`. No code, no builds that write, no commits. You may run
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

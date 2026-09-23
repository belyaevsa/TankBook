# REVIEW-PU-COMPLETENESS – is this pump row actually done?

*The template. Every run gets its own copy, `agents/briefs/REVIEW-COMPLETE-<row>.md`. Dispatched to a
reviewing agent **after every row in the PU.67 tranche is built and gated, before it is committed**
(product owner, 2026-09-23: *"the agent reviewer each time validates the completeness of the
implementation"*). It is to a pump row what `REVIEW-SCENARIO.md` is to a journey: a row is not done
because its code compiles and its tests pass – it is done when what the row promised is in the tree,
wired, measured and written down. The orchestrator commits only on a `COMPLETE` verdict.*

## Fill these in for the run

- **Row:** `RV.304` – an expense fixture commits a category its expected.csv contradicts
  (`docs/TASKS.md`; read its "Built" text). Not a pump row: read the checklist's pump-specific
  wording (app path = `CapturePipeline`'s expense path; measurement = the expense corpus suites) for
  the expense-category vocabulary instead.
- **Research note:** none; item 1 reads: is the fix the narrowest one that corrects both declared
  misses without changing any other fixture's category? Check every fixture in
  `Spike/ReceiptSpike/fixtures/expenses/` and the RV.200 hand-authored ones.
- **The diff under review:** `ios/Sources/TankbookCore/Extraction/ExpenseCategoryInference.swift`,
  `ios/Tests/TankbookCoreTests/RV200ExpenseCategoryInferenceTests.swift`, the RV.304 and RV.305 rows
  in `docs/TASKS.md`.
- **The orchestrator's gate evidence:** RV.200 + RV.277 suites: 15 tests, the one remaining red is
  RV.305's total (a different function, filed); mutation (ignore `notWhen`) red on three tests
  (`/tmp/agentlogs/rv304-mutation.log`); `swiftlint` 0 errors; the app build and app unit bundle are
  running as you start (`/tmp/agentlogs/rv304-app.log` when done).

## Second pass

Review 1 (`agents/reviews/RV.304-COMPLETENESS.md`) was INCOMPLETE on item 6 only. Closed since:
the test header (`RV200ExpenseCategoryInferenceTests.swift:11-15`) rewritten; RV.302 closed by
RV.304; RV.301 annotated (category half done, total half open) and RV.304 ticked with a duplicate
note. Verify those, and only re-open items 1-5 if something changed. Ignore the concurrent edits to
`PumpReadingLaw.swift` (PU.78, not under review).

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:**
`agents/reviews/RV.304-COMPLETENESS-2.md`. No code, no builds that write, no commits. You may run
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

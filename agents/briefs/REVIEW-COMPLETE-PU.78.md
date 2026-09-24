# REVIEW-PU-COMPLETENESS – is this pump row actually done?

*The template. Every run gets its own copy, `agents/briefs/REVIEW-COMPLETE-<row>.md`. Dispatched to a
reviewing agent **after every row in the PU.67 tranche is built and gated, before it is committed**
(product owner, 2026-09-23: *"the agent reviewer each time validates the completeness of the
implementation"*). It is to a pump row what `REVIEW-SCENARIO.md` is to a journey: a row is not done
because its code compiles and its tests pass – it is done when what the row promised is in the tree,
wired, measured and written down. The orchestrator commits only on a `COMPLETE` verdict.*

## Fill these in for the run

- **Row:** `PU.78` – a last-digit misread is validated as agreement (`docs/TASKS.md`; ticked `[x]`
  in the working tree pending THIS review) and the new row `PU.81` it spun off
- **Research note:** `agents/research/PU.78.md` (M1, M2, M3; adaptations A1-A15)
- **The diff under review:** `ios/Sources/TankbookCore/Extraction/PumpReader/PumpReadingLaw.swift`,
  `ios/Sources/TankbookCore/Config/PumpPhotoGate.swift` (reader constants 47/47),
  `ios/Tests/TankbookCoreTests/PumpReadingLawTests.swift`, `PumpReadingLawExactTests.swift` (new),
  `PumpReaderPipelineTests.swift` (`committedFloor` 118), `docs/EXTRACTION.md` (the "close is exact"
  paragraph and the PJ.500 "Wired" paragraph), the PU.78 and PU.81 rows in `docs/TASKS.md`.
- **The orchestrator's gate evidence:** `/tmp/agentlogs/pu78-measure-2.log` (the final measurement:
  annotated 118/118, live 47/47, train in-sample 126/120, with the wrong list), `pu78-measure.log`
  (the FIRST measurement, WITH the pair-repair step: annotated 118/117, pump-014 3.82 wrong - why
  the step was held), `pu78-mutation-M1.log` and `-M2.log` (each revert red), the oracle ratchet
  (774 at 0.9987, fragility 0.041 - printed by `PumpReadingLawTests`), and `pu78-gate.log`
  (`RELEASE=1 scripts/gate.sh`, running as you start).

**Row-specific:**
- Item 1: the implementation departs from the note in ONE place the note did not list - M2 step 2
  (the unique single-confusion pair repair) is NOT shipped, because measured it corrupted pump-014
  (a correct heldout reading) after the owner re-framed that still; it is held as PU.81 with the
  owner's guard decision recorded. Judge whether holding a step is a legitimate response (it removes
  behaviour the note proposed; it adds none), and whether M3 (the SR+SGR risk-coverage instrument)
  being absent is a gap: the note calls it an instrument whose predicted outcome is "no threshold
  passes" - say whether its absence leaves any promise of the ROW (not the note) unmet.
- Item 3: the ROW's gate is "zero wrong on heldout, the train wrong count falls, heldout commits do
  not fall" - check each against the logs.
- Check that `closingSlack` and `pairAgreementTolerance` are gone from code and comments, and that
  every comment in `PumpReadingLaw.swift` describes the exact close.

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:**
`agents/reviews/PU.78-COMPLETENESS.md`. No code, no builds that write, no commits. You may run
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

**The standing fences appended below were written for build briefs.** Their write and stash/checkout rules apply to you; their standing checks do not - the gate is already running.

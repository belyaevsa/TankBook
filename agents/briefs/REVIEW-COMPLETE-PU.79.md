# REVIEW-PU-COMPLETENESS – is this pump row actually done?

*The template. Every run gets its own copy, `agents/briefs/REVIEW-COMPLETE-<row>.md`. Dispatched to a
reviewing agent **after every row in the PU.67 tranche is built and gated, before it is committed**
(product owner, 2026-09-23: *"the agent reviewer each time validates the completeness of the
implementation"*). It is to a pump row what `REVIEW-SCENARIO.md` is to a journey: a row is not done
because its code compiles and its tests pass – it is done when what the row promised is in the tree,
wired, measured and written down. The orchestrator commits only on a `COMPLETE` verdict.*

## Fill these in for the run

- **Row:** `PU.79` – the annotated floor reads 111 against 112 (`docs/TASKS.md`; read its "Traced" text)
- **Research note:** none (a measurement reconciliation). Item 1 reads: is the diagnosis right, and is
  lowering the floor the honest resolution rather than hiding a reader regression?
- **The diff under review** (only these paths): `ios/Tests/TankbookCoreTests/PumpReaderPipelineTests.swift`
  (`committedFloor` and its comment), the PU.79 and PU.65 rows in `docs/TASKS.md`.
- **The orchestrator's gate evidence:** `/tmp/agentlogs/pu79-gate.log` (gateMirror 111/110 green),
  `/tmp/agentlogs/pu79-mutation.log` (floor 112 red); `swiftlint` 0 errors.

**Verify the diagnosis independently:** re-run `ios/.build/opt/debug/pump-read
Spike/ReceiptSpike/fixtures/pump/pump-014-dresser-wayne-ee-glare-partial.heic` with stdin
`{"rotationCW":0,"currency":"EUR","windows":[...]}` built from pump-014's windows at `72ec6063` and at
`HEAD` (`git show <c>:Spike/ReceiptSpike/fixtures/pump/windows.json`). Then confirm no OTHER heldout
cell changed between the commit that set 112 and HEAD - e.g. that the heldout set and its reviewed
flags differ only by pump-014, or that the 110 correct cells are the same stills (the wrong cell was
pump-055 before and should still be). Items 2 and 3 (app path, live measurement) do not apply.

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:**
`agents/reviews/PU.79-COMPLETENESS.md`. No code, no builds that write, no commits. You may run
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

**The standing fences appended below were written for build briefs.** Their write and
stash/checkout rules apply to you; their standing checks do not - you change no code.

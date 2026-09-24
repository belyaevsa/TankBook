# REVIEW-PU-COMPLETENESS – is this pump row actually done?

*The template. Every run gets its own copy, `agents/briefs/REVIEW-COMPLETE-<row>.md`. Dispatched to a
reviewing agent **after every row in the PU.67 tranche is built and gated, before it is committed**
(product owner, 2026-09-23: *"the agent reviewer each time validates the completeness of the
implementation"*). It is to a pump row what `REVIEW-SCENARIO.md` is to a journey: a row is not done
because its code compiles and its tests pass – it is done when what the row promised is in the tree,
wired, measured and written down. The orchestrator commits only on a `COMPLETE` verdict.*

## Fill these in for the run

- **Row:** `PU.74` – the law refuses a close whose digit counts are impossible for their roles
  (`docs/TASKS.md`, ticked in the tree pending THIS review - read its "Built" text)
- **Research note:** `agents/research/PU.74.md` (adaptations A1-A9)
- **The diff under review:** `ios/Sources/TankbookCore/Extraction/PumpReader/PumpReadingTypes.swift`
  (the measured `PumpDisplayConventions` table, two new `PumpAbstentionReason` cases),
  `PumpReadingLaw.swift` (the unmeasured-currency refusal and the cell-count audit in the triple and
  pair tiers), `ios/Tests/TankbookCoreTests/PumpReadingLawExactTests.swift` (three new tests), the PU.74
  paragraph in `docs/EXTRACTION.md`, the PU.74 row. IGNORE the uncommitted PU.72 / PU.73 edits (`ml/`,
  their rows, the PU.73 EXTRACTION paragraph).
- **The orchestrator's gate evidence:** `/tmp/agentlogs/pu74-measure.log` (+ `-summary.log`): annotated
  121/121, live 47/47, train 122/118; law suites 38/38 with the oracle 776 / 0.9987 and fragility
  0.041 (printed by `PumpReadingLawTests`); mutations `/tmp/agentlogs/pu74-mutation-{gbpwide,default,cells}.log`
  each red; app unit bundle `/tmp/agentlogs/pu74-app.log` 301/301; lint 0.

**Row-specific:** verify the table against the corpus yourself (re-count at HEAD with the note's rule,
§5.2) - one wrong entry refuses a real currency's reads. Confirm `PumpAbstentionReason` crosses no
payload or API boundary (hard rules 9, 16). Judge the one choice beyond the note: the cell-count audit
only for currencies with three or more stills (the note's A8 speaks of n >= 3 groups).

## Third pass

Review 2 (`agents/reviews/PU.74-COMPLETENESS-2.md`) was INCOMPLETE. Its required closure, as done -
verify each, and read the row's new "Completeness review 2 INCOMPLETE, closed" text (`docs/TASKS.md`,
the PU.74 row) and the rewritten PU.74 paragraph in `docs/EXTRACTION.md`:
1. **Count-audit placement** - recorded as a justified adaptation (window-level, once per window in
   `resolve`) in `docs/EXTRACTION.md`. Judge the justification.
2. **pump-106** - the Checks sentence now says "audit catch" per the note's §5.3.
3. **Close sweep (F1/F2)** - `PumpDisplayConventionsCorpusTests.tableRefusesNoTrueClose` (229
   undisputed three-value fixtures, 224 true closes, 0 refused) and
   `tableDisambiguatesTenfoldCloses` (12 of the note's 14; pump-190 and pump-310 excluded with the
   reason in the doc comment). Judge whether excluding `csvDisagrees` fixtures matches the note
   (§5.2 line ~282) and whether the sweep replicates the law (`closes(...)` in that file).
4. **Provenance** - the orchestrator's one-decimal RUB test premise was wrong; the corpus asserts
   the display on pump-018/106 and the product on pump-065/073/158. The law is unchanged; a trial
   that read the display broke the oracle ratchet (pump-158 new wrong). Tests now assert value AND
   provenance: `rubOneDecimalPriceAndTotal` (read when the product reproduces the display) and
   `truncatedTotalStaysDerived` (derived otherwise). Mutations red then restored:
   `/tmp/agentlogs/pu74-mutation-{gbp-permissive,rub-no-truncated,rub-price-2}.log`.
5. **Second-pass law log** `/tmp/agentlogs/pu74-law-pass2.log`: oracle 784/783, fragility 0.039,
   45/45.
6. **PU.59's cautioned tier** - not shipped (the unvalidated pair still abstains); its input
   population re-measured from `/tmp/agentlogs/pu74-measure-2.log` (5 heldout stills
   `priceUnvalidated`, 22 train). Judge whether this discharges "re-measured and reported".
7. **Population and intervals** - 183 cells with Clopper-Pearson / Wilson intervals in the row and
   EXTRACTION.
8. **Comments** - no task paths in `PumpReadingTypes.swift` or the corpus test header.
**Gate:** `scripts/gate.sh` all steps exit 0 on this tree: 2299 package tests, 303 app-target tests
(`/tmp/agentlogs/pu74-gate.log`, grep `^\[gate\]`). The tiers' measurement
(`/tmp/agentlogs/pu74-measure-2.log`) was taken before this pass; the law file is byte-identical to
that run's and `PumpReadingTypes.swift` changed only in comments - verify with
`git diff ios/Sources/TankbookCore/Extraction/PumpReader/`.

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:**
`agents/reviews/PU.74-COMPLETENESS-3.md`. No code, no builds that write, no commits. You may run
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

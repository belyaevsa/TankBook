# PU.68 completeness review - interval estimates, a detector override, and the leak's consequences

Run 2026-09-23 against the working tree on base `c86755d6` (HEAD moved to `afb611a0` mid-review: the
concurrent annotator session committed its trace work at 19:54; none of the PU.68 paths moved, they
remain uncommitted). Research note: `agents/research/PU.68.md`. Diff under review: the five test
files named in the brief and the PU.68/PU.78/PU.69 rows in `docs/TASKS.md`.

**What I ran**: read-only git/grep/log inspection; `swiftlint lint` (0 errors tree-wide); an
independent Python recomputation of every headline bound and an independent re-count of all three
populations from `split.csv`/`windows.json`/`expected.csv`. No builds, no tests, no repo writes
except this file. Nothing I report is time-sensitive, so concurrent machine load does not affect it.

**Independent arithmetic check** (recomputed from the run's own k/n, exact match to 4 decimals):
photoUCB(5, 47, d=0.05) = **0.2108** and (d=0.10) = **0.1884**; cellUCB(7, 124) = **0.1034** /
**0.0931**; Wilson 1s lower(17/17) = **0.8627** - all equal the `pu68-pipeline.log` prints.
**Independent population re-count**: heldout 68 stills / 183 cells (matches livePath "of 183");
reviewed train 244 stills / 670 cells (matches the certify run's "34/244" and "of 670"); non-pump
denominator 97+9+9+1 = **116** (matches the leak run). The note's 250/668 was counted at `310e7660`
and its §6 explicitly directs a re-count at the build commit - done, and the run prints its own.
heldout2 is consumed by nothing: `isTrain` requires split == "train", `isHeldout` requires "heldout"
(PumpReaderTestSupport.swift:78-83), so the frozen draw stays frozen and uncalibrated.

## Item 1 - fidelity to the published method: **MET**

- Wilson, BCD eq. (4): centre and half-width at PumpPrecisionBounds.swift:16-22 are the formula
  term for term, with the note's κ values (:12-13). At x = n it collapses to [n/(n+κ²), 1] as §2.1
  says; `clopperPearsonLower(45, 45, 0.05)` by bisection on P(Bin ≤ x-1) = 1-α (:57-61) is exactly
  the α^{1/n} form at the boundary (0.05^{1/45} = 0.9356, the note's table value, asserted at
  PumpPrecisionBoundsTests.swift:22).
- Exact binomial UCB, RCPS App. B eq. (42): `binomialUCB` (:65-68) solves sup{R : P(Bin(n,R) ≤ k) ≥ δ}
  as the CDF = δ crossing; the note's §5.1 reachability table is asserted case by case
  (PumpPrecisionBoundsTests.swift:41-44), and falsifier F3 is a live assertion (:50-52).
- HB p-value, LTT eq. (2): `hoeffdingBentkusPValue` (:72-83) is min(exp(-n·h₁(R̂∧α, α)),
  e·P(Bin(n,α) ≤ ⌈n·R̂⌉)) exactly, including the ⌈·⌉ and the ∧α.
- A1: the certificate is framed as a fixed-threshold test, never as CRC/RCPS λ-selection
  (PumpReaderPipelineTests.swift:117-123 doc comment cites LTT + RCPS App. B; the prints say
  "does not certify <=", :144-148). A2: labelled IN-SAMPLE in the doc comment, in the report label
  ("PU.68 train split, in-sample", :136) and in the TASKS row. A4: the photo is the loss unit -
  binary `1{any committed cell wrong}` primary (:139, aggregation :585-605), fractional-loss HB
  secondary (:141-143), cell-unit UCB printed and labelled "cells within a photo are not
  independent - secondary" (:140, :145-146). A5: δ = 0.05 and 0.10 both printed (:138). A6:
  two-sided printed beside the one-sided lower in every precision line (PumpPrecisionBounds.swift:87-95);
  the gate itself is untouched, per the note §3.3 (that decision is the owner's). A7: Wilson
  estimates, exact binomial certifies, CP appears only as the named conservative cross-check in the
  estimation line - the roles are not crossed anywhere. A8: scoring inherits `CorpusScorer.tolerance`
  and the 0.1 derived band unchanged (PumpReaderPipelineTests.swift:594). A10: the reachability
  statement ships in the row ("268 clean commits needed, 183 cells exist", TASKS.md:1060).
- The one implementation choice beyond §3's letter - `isReviewedTrain` (PumpReaderTestSupport.swift:81-83)
  instead of bare `isTrain` - is §6's counted population ("same filter" includes `reviewed: true`),
  and my re-count confirms it reproduces §6's filter exactly at the build commit. Not a departure.
- No unlisted departure found. Falsifier status: F1 covered (table values + "a bound moves with the
  error count", PumpPrecisionBoundsTests.swift:55-61); F2 vacuous today (train certifies nothing, so
  nothing to contradict; heldout k = 0); F3 asserted; F4 satisfied observationally (0.2108 vs 0.1034
  on a run where pump-137 and pump-266 each committed 2 wrong cells) but is a reading rule on the
  print, not a test - acceptable, the note framed it as a run diagnostic.

## Item 2 - wired into the app path (as re-scoped by the brief): **MET**

PU.68 ships nothing to the device (note §7; the whole diff is test-bundle code, `PumpPhotoGate.swift`
and `ios/App` untouched, no `#if DEBUG` seam, so no RELEASE gate is owed). The instruments measure
the app's own seams: the certificate builds its reader through `PumpDisplayCapture.makeReader`
(PumpReaderPipelineTests.swift:127-128) - the same factory `CapturePipeline` calls
(ios/App/Sources/Capture/CapturePipeline.swift:28) - and scores through `PumpDisplayCapture.classify`
via `measureLive(appPath: true)` (:134, classify call :559; the app's classify call site is
CapturePipeline.swift:131). The leak test does the same (PumpLeakConsequenceTests.swift:29-30, :43-51).
`livePath`'s reader construction (:86-87) is component-identical to `makeReader`'s body
(PumpDisplayCapture.swift:106-110). No test-only reader anywhere in the new code.

## Item 3 - measured on the app path, on the named population: **MET**

- livePath ran green (pu68-pipeline.log: "committed 45, correct 45 ... of 183", ✔ after 571.5 s),
  with the interval printed beside the point estimate ("Wilson 95% [0.9213, 1.0000], one-sided 95%
  lower: Wilson 0.9433, Clopper-Pearson 0.9356"). Those match the note §4 table exactly.
- 45/45/183 equals `PumpPhotoGate.readerCommitted/readerCommittedCorrect/readerNumericTotal`
  (PumpPhotoGate.swift:86, :91, :95), and livePath asserts the equality, not just the floor
  (PumpReaderPipelineTests.swift:104-110) - the PU.61 "constants are this run" rule holds.
- The row's claimed movement is over the populations it named: heldout app path (45/45 + interval)
  and reviewed train (124/117, 5 of 47 photos wrong, UCB 0.2108) - every number in TASKS.md:1060
  appears verbatim in the logs, and I reproduced the bounds independently (above).
- Zero new wrong readings on heldout: 45/45 live. The annotated arm's single WRONG (pump-055 liters
  56.09 for 56.05) is **the same cell, same values, as PU.54's run at 112/111** (found in
  /tmp/agentlogs/PU.54.log) - no new wrong reading there either; what moved is coverage (-1 cell),
  see item 4. The train-split wrong cells are in-sample measurement, not shipped behaviour, and are
  filed as PU.78 (TASKS.md:1061) with all seven traced (pump-099/-137/-251/-264/-266, values match
  the log line for line).

## Item 4 - no regression elsewhere: **MET for this diff; two pre-existing reds surfaced, unowned**

- **Leak did not rise behaviourally.** PU.68 changes no routing code. PU.29's zero-receipt test is
  green in the full run (pu68-swifttest.log:5754). The leak test's 6 of 116 is a *stricter
  configuration* than the historical 5/116 (uncapped budget vs the phone's 1.5 s `slowPathBudget`,
  all four folders, detector present - PumpLeakConsequenceTests.swift:18-21, :43-44), and the row
  says so ("at an uncapped budget (receipt-091 the sixth)"). Worst case now ratcheted: ceiling 6,
  commits 0, both asserted with the fixture named on failure (:64-67).
- **The annotated floor fell (112 → 111) and gateMirror is red - not by this diff.** PU.68's only
  change to gateMirror is the interval print (:265); the failing assertion is `committed >= 112`
  (:273-274, constants :28-29). Attribution (inference, labelled): the last verified 112 was PU.65's
  gate (`d1ea3f44`, 11:10, "annotated 112/111"); the only reader-affecting commit after it is
  **`bdca96a9` (PJ.500), which rewrote the law's pair bands** (agreement 0.5% vs validation 5%,
  `PumpReadingLaw.swift` ±33 lines); `c86755d6` touched no heldout window (its windows.json diff
  contains only pump-319..328 - verified), the detector file is unchanged since Sep 22 18:52
  (mtime), and the concurrent session's `PumpReader.swift` edits are trace-nil no-ops with a parity
  suite green in the full run. So PJ.500's law change dropped one annotated cell from committing.
  **This is unowned today**: `committedFloor` is still 112 and PU.65's row text still says
  "annotated 112/111". Until triaged, `swift test --filter PumpReaderPipelineTests` cannot exit 0,
  which blocks hard rule 14 for every following row. Draft row in "findings" below.
- **Law's oracle ratchet held**: PU.21 suite green (pu68-swifttest.log:5477), oracle print
  "committed 771, correct 770 ... of 889; wrong: [pump-031]" (:2275) - pump-031 is the declared
  csvDisagrees artefact. PU.4 harness suite green (:5738).
- **Latency**: no hot path touched; note §7 owes no Release number and none is claimed.

## Item 5 - tests that would fail: **PARTIAL**

What is covered:
- The interval arithmetic: `PumpPrecisionBoundsTests` (3 tests, green inside the full run,
  pu68-swifttest.log:5528) pins the note's §4 and §5.1 tables to 4 decimals plus F3 and monotonicity.
  Mutation evidence: Wald-centred Wilson → red, 10 issues (brief + TASKS.md:1060). The count is
  consistent with the test's structure, but **the red output exists only as the orchestrator's
  one-liner - no captured log**, unlike every other gate artefact.
- The leak ratchet bit for real: the pre-gating run went red on `routed 6 > ceiling 5` and named all
  six fixtures (pu68-leak.log) - an accidental mutation with captured red output. Note: that log's
  trailing "[exited with code 0]" contradicts the recorded failure; trust the issue lines, not that
  wrapper annotation. The final form (ceiling 6, `PUMP_LEAK=1` gate) has **never run green** - it is
  skipped in the full suite (pu68-swifttest.log:3297, suite "passed" at :5219 by skip), and passing
  is arithmetic on the observed counts (6 ≤ 6, 0 ≤ 0). Acceptable, but say it plainly: the shipped
  assertion combination is unexecuted.

What is not:
- **`PUMP_DETECTOR` was never exercised.** No run in the evidence sets it; removing the env read
  (PumpReaderTestSupport.swift:29-30) turns no test red. Every comparable switch in this file was
  exercised by the row that landed it (PUMP_FUSION/DECOUPLE/ORIENT/CERTIFY/LEAK all have runs;
  PUMP_MODEL has PU.47/PU.52 history). Also unexercised is the failure shape: a set-but-nonexistent
  path silently yields `detectorURL = nil` (no detector, floors collapse to the Vision-era numbers)
  rather than an error naming the bad path - the floors would go red, so it is discoverable, but a
  candidate scoring run would look like "the candidate is terrible".
- **The per-photo aggregation has no falsifier.** Delete `m.photosWrong += 1`
  (PumpReaderPipelineTests.swift:602-604) and every test stays green - `trainSplitRiskBound`'s only
  assertion is `photosCommitting > 0` (:150). The certificate's headline k would silently print 0.
  (Today a false *certificate* is still impossible - k=0 at n=47 gives UCB 0.0625 > 0.01, F3's
  arithmetic protects the verdict - but the printed bound and the row's numbers would be wrong with
  nothing red.) The observed run is internally consistent (7 WRONG lines over 5 distinct photos =
  photosWrong 5, 124-117 = 7), which is evidence, not a guard.

## Item 6 - docs reconciled: **PARTIAL**

- `docs/TASKS.md`: the row records Built/Measured faithfully (every number checked against the logs,
  above); PU.78 drafted for the seven wrong cells with an index row (:165); PU.69's row corrected
  (coarse/fine sweep description). `scripts/tasks-index.py --check` exit 0,
  `scripts/scenario-index.py --check` exit 0 ("523 rows, every open one attached"). The row is
  unticked, correctly. Two nits: "the owner's corpus session **is creating** heldout2" is stale -
  `c86755d6` created it; and the row could record the re-counted train population (244 stills /
  670 cells at the build commit vs the note's 250/668) since the note §6 asked for the re-count to
  be printed - the log prints it, the row does not.
- **`docs/EXTRACTION.md:900-902` carries a factual error about this row's own numbers**: "45/45
  committed-correct bounds precision at only ~0.92 (Wilson, **one-sided** 95 %)". 0.9213 is the
  **two-sided** lower bound; the one-sided lower is 0.9433 (note §4 table, `precisionLine`'s output
  in every log, and the PU.68 row itself all agree). The mislabel originates in the Qwen review
  (:212) and was committed in the `c86755d6` decision-9 amendment - base, not this diff - but PU.68
  is the row with authority over this arithmetic and doc reconciliation is part of every task's
  definition of done (CLAUDE.md). One-word fix; it must not ship unfixed beside a row whose premise
  is that these bounds get quoted precisely.
- Comment rules (CLAUDE.md), touched files: research-note citations are authority links (allowed);
  "PU.68"/"PU.63"-style labels are print strings following the harness's established convention
  (PU.19/22/47/53 labels predate this row); the ceiling-provenance comment
  (PumpLeakConsequenceTests.swift:18-21) matches this file family's floor-comment convention. Two
  claims are not current truth: the certify comment says "**250 stills**, ~40 minutes"
  (PumpReaderPipelineTests.swift:123) when the population it measures is the reviewed train split,
  244 stills at the build commit (the observed run took 30 min); and the leak header says "in
  **every currency the pump corpus holds**" (PumpLeakConsequenceTests.swift:8) while the code tests
  four (EUR/RUB/KZT/GBP, :16) - the top four by corpus count (313 of 339 tagged cells; AUD, BYN and
  nine singletons untested). Per the comment rules: soften or enforce. The TASKS row names the four
  currencies correctly, so this is comment-only drift.
- `docs/ERRORS.md`, `docs/JOURNEYS.md`: correctly untouched - nothing user-visible changed.
- Lint: 0 errors tree-wide (I re-ran `swiftlint lint` after `afb611a0` landed - the brief's "one
  error in PumpReader.swift" is already historical). The five PU.68 files carry warnings only; the
  ~10 new `identifier_name` warnings in PumpPrecisionBounds.swift are single-letter formula symbols
  (x, n, k, p, z) in a tree with 304 pre-existing warnings of the same class - consistent, not
  casual.

## Item 7 - everything the row promised, sentence by sentence: **PARTIAL**

| Checks-cell sentence (TASKS.md:1060) | Verdict | Evidence |
|---|---|---|
| "Every precision the pipeline tests print carries its Wilson interval" | **PARTIAL** | True for `report()` (:617, so livePath, certify and the PU.53 arms) and gateMirror (:265). **Not true for the two opt-in arms in the same file**: `liveFusion`'s local report prints four bare precisions (:411-416) and `decoupling` prints two (:489-493). The row's Built text repeats the overclaim ("every pipeline report prints the interval and a per-photo line"; gateMirror also has no per-photo line). The note's §3.1 scoped the work to report+gateMirror, but the row promised "every", and these arms print exactly the small-n point estimates (fusion: ~51 commits) the Qwen review §2.1 exists to stop being quoted bare. |
| "a conformal risk-control bound on the wrong-commit rate is computed on the TRAIN split and reported beside the heldout point estimate, method as the note derives it" | **MET** | `trainSplitRiskBound` (:126-151) on `isReviewedTrain`; in the gate run both reports print in one log, heldout first (45/45 + interval), then train + bounds - "beside", labelled in-sample, never in place of. Method verified line-by-line under item 1. |
| "`PUMP_DETECTOR=<path>` scores a candidate without touching the dev copy" | **MET as code, unexercised** | PumpReaderTestSupport.swift:26-32 mirrors the note §3.5 spec and the PUMP_MODEL pattern exactly; dev copy untouched. No evidence run sets the variable (see item 5). |
| "a test scores what each non-pump fixture routed as a pump COMMITS (fields, values' presence only - hard rule 12) and names them" | **MET** | PumpLeakConsequenceTests scores every routed fixture × 4 currencies through the app's `classify`, prints ROUTED names and "COMMITS <fixture> [currency] <field names>" (:47-63) - field names and presence only, never values (hard rule 12 honoured); ran 2671 s, named all six, 0 commits. Caveats from item 5: final ceilings unexecuted, commit-ceiling assertion never reddened. |
| "A second frozen heldout draw is the owner's call, asked, not assumed" | **MET** | Nothing in the diff touches heldout2; the filters provably exclude it (above); the owner's own session created it (`c86755d6`). Row tense nit under item 6. |

## The full-suite failures in pu68-swifttest.log - caused by the PU.68 diff?

**No. None of the five.** 117 issues = 57 + 57 + 1 + 1 + 1, and the PU.68 diff (print lines, an
opt-in test, an env override defaulting to prior behaviour, a defaulted parameter) cannot reach any
of them:

1. **P4.12 "swept by Arm A" (57) and P4.13 "swept by the LLM arm" (57)**: images with no sweep
   record - named in the log starting at pump-285..289, i.e. **batch 8 (Sep 22)** additions; a
   corpus-sweep backlog that predates the base commit. Owner: the sweep/intake rows (P4.12/P4.13),
   not PU.68.
2. **RV.277 "no expense fixture commits a value its expected.csv contradicts" (1)**: three
   deterministic contradictions in `parts-*` fixtures (category wash/toll vs parts; total 650 vs
   159373). Fixtures, expected rows and the extractor all last changed together in **`13a04a38`
   (Sep 21)**; nothing since touched them, and the parser is deterministic - so this has been red in
   every full run on this machine since Sep 21. Owner: RV.277 / the expense-parser rows. Not PU.68.
3. **CaptureOrientationTests e5rtError (1)**: a CoreML stream-completion runtime error under
   concurrent load (the certify suite was running beside it) - the RV.203 flake class; re-run alone
   before believing it. Not PU.68.
4. **gateMirror `committed 111 < 112` (1)**: attributed under item 4 to PJ.500's law change
   (`bdca96a9`), inference labelled. Not PU.68.

## Findings I did not fix, with owners

1. **Annotated floor unowned and red** (blocks the next gate that runs the pipeline suite): trace
   the one flipped cell (gateMirror at `bdca96a9^` vs `bdca96a9`, or PU.56's ledger diff once it
   exists), then PJ.500 owns either restoring the commit or lowering `committedFloor`
   (PumpReaderPipelineTests.swift:28) **with the reason recorded in its comment**, and PU.65's row
   text "annotated 112/111" needs correcting in the same change. Suggested row if PJ.500 will not
   take it: *"PJ.500's pair bands moved the annotated arm 112 → 111 (wrong cell unchanged,
   pump-055): identify the flipped cell, then reconcile `committedFloor` or the law; PU.65's row
   text is stale."*
2. **EXTRACTION.md:901 "one-sided" → "two-sided"** (or restate as the row does: "[0.9213, 1],
   one-sided lower 0.9433"). One word; belongs in the PU.68 commit.
3. **RV.277 red since Sep 21** and **the 2×57 sweep backlog**: file or extend their own rows; both
   predate the base and both make `swift test` exit 1 for everyone.
4. The Qwen review's own §2.1/:212 wording carries the same one-sided/two-sided slip; it is a
   historical record, so correct EXTRACTION.md and leave the review file alone.

## What the orchestrator must close before re-dispatch (all cheap)

1. Add `PumpPrecisionBounds.precisionLine` to the fusion report (:411-416) and the decoupling line
   (:489-493), or narrow the row's sentence and Built text to "every precision the pipeline's
   gated and certify reports print" - silently keeping "every" while two arms print bare is the
   PU.59 shape. (Fixes item 7 sentence 1 and the TASKS overclaim together.)
2. Exercise `PUMP_DETECTOR` once and keep the log: `PUMP_DETECTOR=ml/pump-reader/.out/det/pu66c/<candidate>`
   on the annotated arm (~90-200 s) showing the numbers move off 111/110, or a set-but-nonexistent
   path showing the detector-absent collapse - either proves the switch steers the measurement.
3. Add the aggregation invariant to `trainSplitRiskBound`: `#expect` that `m.photosWrong` equals the
   count of distinct fixture names in `m.wrong` (true by construction, red if either side breaks) -
   or record an equivalent mutation (zero `photosWrong`) reddened and restored.
4. Fix the two stale comment claims (certify "250 stills"; leak "every currency the pump corpus
   holds" → name the four and why) and EXTRACTION.md:901.
5. Touch up the row: heldout2 "is creating" → created at `c86755d6`; record the re-counted train
   population (244 stills / 670 cells); capture the Wald-mutation red output in a log next time.
6. Decide the ordering for finding 1 (annotated floor) - the PU.68 commit lands on a red pipeline
   suite either way; the floor triage should not wait behind it, and hard rule 14 means the next
   row's gate cannot pass until it happens.

Recommended, not required: one `PUMP_LEAK=1` re-run of the final ceiling form for the record
(~45 min), and a re-run of CaptureOrientationTests alone to confirm the flake.

## Verdict

**INCOMPLETE** - items 5, 6 and 7 PARTIAL; items 1, 2, 3, 4 MET. The instrument itself is faithful
to the published method (independently re-derived to 4 decimals), measures the app's path on the
note's populations, and its headline numbers all reproduce; what is missing is small and named
above: two bare precision prints against an "every" promise, one unexercised switch, one unguarded
aggregation, three stale sentences (TASKS row, EXTRACTION.md:901, two comments). Close the six
numbered items and re-dispatch a fresh copy of this review. The annotated-floor drop, the RV.277 red
and the sweep backlog are real, pre-existing and must be filed - none is PU.68's, and none may be
dropped silently.

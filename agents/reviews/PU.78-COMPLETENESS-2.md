# PU.78 completeness review, second pass - the exact close, against the committed corpus

Run of `agents/briefs/REVIEW-COMPLETE-PU.78-2.md` (template `REVIEW-PU-COMPLETENESS.md`), 2026-09-24,
against the working tree at `eaf8e9d7` + the uncommitted PU.78 diff. Reviewer: reviewing agent.
Read-only except this file.

**What I ran** (all read-only; no builds, no `PumpReadTool`, so the machine-load caveat does not
apply to anything below): `git diff` / `git show` / `git log` / `git status` / `git diff --cached`,
file reads of every file in the diff and of all five gate logs, `rg` over the tree for the retired
constants and the call-site chain, `swiftlint lint` on the five touched Swift files (exit **0**,
warnings only, all pre-existing species in `PumpReaderPipelineTests.swift`), `python3
scripts/tasks-index.py --check` (exit **0**), `python3 scripts/scenario-index.py --check` (exit
**0**, 528 rows). Every number is quoted from a named log with its line; I re-measured nothing.

**Timeline I reconstructed, because three verdicts hang on it** (mtimes + log stamps):

| When | What |
|---|---|
| 00:33 | `pu78-measure.log` - the law WITH M2's repair step: annotated **118/117**, `WRONG pump-014 liters got 3.82...want 3.92`. The step is held from here |
| 00:40:20 | the owner's annotator writes `windows.json`: pump-275 hand-re-framed, `"reviewed": true` cleared (the ONLY change in the file - I verified the diff myself) |
| 01:07 | `pu78-measure-2.log` - the law WITHOUT the repair step, on the corpus loaded at its start (pre-drift = the committed `b42f38da` bytes): annotated **118/118**, live **47/47** of **183**, train **126/120** |
| 01:08 | the constants move (`PumpPhotoGate.swift`, `PumpReaderPipelineTests.swift`); the three exact tests move to `PumpReadingLawExactTests.swift` (01:09:50) |
| 01:08 | mutation logs M1 (2 red) and M2 (3 red) |
| 01:11-01:24 | `pu78-gate.log`: package 0, lint 0, xcodegen 0, app Debug build 0 (:3612), **Release build 0 (:4717)**, `swift test` **exit 1** (:10121) on the two floors against the drifted corpus |
| 01:40 | review 1 ends (INCOMPLETE, seven items) |
| 01:42:04 | `PumpReadingLaw.swift` last write - review 1's must-fix 3, the contender-comment rewrite. **Comment-only, established below** |
| 03:05 | `pu69-app.log`: `xcodebuild test -only-testing:TankbookTests` - **301 tests, 0 failures**, on the current law bytes |
| 04:00 | `pu69-swifttest.log`: full package suite on the current law bytes - **2285 tests, 294 suites, 2 issues**, both the pump-275 floors |
| 05:35 / 06:06 | `docs/EXTRACTION.md` / `docs/TASKS.md` edits (review 1's items 2 and 4, the row's new sentences) |
| 05:53 | PU.69 commits (`eaf8e9d7`) - different files; the law is untouched by it (its stat: `PumpFastHough`, `PumpRowDeskew`, their tests, docs, agents artefacts) |

**The 01:42 edit is provably comment-only.** Every code line review 1 cited by number still sits at
the same number (`:263` `pairValidationTolerance`, `:267` the note citation, `:296-300` `bandShown`,
`:301-307` the band fallback, `:310-314` the nudge, `:345-349` `exactClosing`, `:411-429`
rounds/closes, `:14` the §2.1 citation), and the one difference review 1 reported - the contender
comment it quoted STALE at `:455-460` and demanded rewritten - now sits rewritten in the same
six-line slot (the diff hunk is 12 lines out, 12 lines in, the filter code unchanged as context).
So: `pu69-app.log` and `pu69-swifttest.log` ran the CURRENT law bytes, and `pu78-measure-2.log` and
the mutation logs ran bytes that differ from current by comments. That is the hinge the gate
judgement below turns on.

---

## Item 1 - Fidelity to the published method: **MET**

Everything shipped is on the note's list; I found no unlisted departure. I re-verified review 1's
table against the note and the code rather than carrying it:

| Note | Code | Verdict |
|---|---|---|
| **M1** (note §3-M1, :279-305): close set `{round2, floor2}`, `closingSlack` retired, `exactClosing` becomes the round-branch ("implementer's call"), repair tier inherits exactness, truncated branch untouched | `PumpReadingLaw.swift:411-429` - `rounds = abs(product - t.value) < 0.0005`, `closes = rounds \|\| abs(floored - t.value) < 0.0005`; `exactClosing: rounds` (:429); the repair tier calls `closingTriples` unchanged (:135-136) and its comment "close to the cent (no tolerance widening)" (:113-114) is now literally true, as the note predicted; the truncated branch (:432-443) untouched | MET. **A5** (two exact values, not Luhn's one equation) is the note's own listed adaptation, justified by the per-head-unknown rounding mode; still zero-tolerance |
| **A14**: preset keeps the half-volume-step term, loses the additive term | `:421-423` - `presetSlack ? abs(product - t.value) <= 0.005 * p.value : ...` | MET, exactly as prescribed |
| **M2 step 1** (note :309-313): exact agreement replaces the 0.5 % band, band-filter the shown list | `:296-300` - `bandShown = shownPrices.filter { band.contains($0) }` then `closesExactly` (:318-321); `pairAgreementTolerance` deleted | MET |
| **M2 step 2**: unique single-confusion repair | **not shipped** | Held as PU.81 - judged below |
| **M2 step 3**: 5 % band fallback unchanged behind steps 1-2 (**A7**) | `:301-307`, `pairValidationTolerance = 0.05` (:263) | MET |
| **M3**: SR+SGR instrument | **absent, now recorded** | Judged below |

The `1e-7` nudge in `cents(floorOf:)` (:310-314) remains the one implementation detail the note does
not list, and review 1's judgement stands on my re-read: it is binary-representation hygiene that
cannot widen the close set (`floor(x*100+1e-7) <= round(x*100+0.5)`, so `floored` stays in
`{product, product-0.01}`), and it is commented with the reason.

### Holding M2 step 2: legitimate, and three separate authorities require it

1. **It removes behaviour the note proposed and adds none.** Item 1's MISSING case is code doing
   something the paper does not do; there is nothing here to name a paper section against.
2. **The ROW's own gate condemned the step.** `pu78-measure.log` (with the step, same corpus, same
   build, minutes before measure-2): annotated **118 committed / 117 correct**, `WRONG pump-014
   liters got 3.8200000000000003 want 3.92`. The row's gate is "zero wrong on heldout". Shipping the
   step fails the row.
3. **The note pre-authorised exactly this response.** Falsifier #5 (note :478-480): the repair
   "firing non-uniquely or uniquely-WRONGLY on any heldout or train photo (a repaired commit that
   the scorer marks wrong is a new wrong cell - **gate 1 catches it**; the uniqueness rule is the
   designed defence)." It fired uniquely and wrongly - pump-014's 3.82 x 1.834 = 7.006 -> 7.01 is
   the only single-confusion exact close against its four boards - the designed defence failed, and
   the note's own remedy (gate 1) is what held the step. The note's enumeration said pump-014's
   repair set was EMPTY (§3-M2); that was measured before the owner re-framed pump-014 (`b42f38da`).
   The data moved under the note, not the note under the data.
4. **The owner approved the departure and the path forward**, recorded in the row: PU.81
   (`docs/TASKS.md:1069`) carries the mechanism, the pump-014 arithmetic, the owner's decision
   (**A, the beam guard**, top `beamWidth` 3) and the owner's fallback (no repair rather than invent
   a threshold). That is "a gap the row cannot close becomes a new row, never silently dropped",
   done correctly.

**The falsifier that DID fire, stated plainly:** #2 - pump-275 still commits 103.31 in the
deskew-`.onRefusal` arm (now under `.shownPriceDiffers` rather than bare agreement; the arm was not
re-measured, so "still commits" is review 1's inference from the unchanged band path, and the
caution change is what the code requires). It is not a clause of the ROW: the app ships `.off`, the
heldout gate runs `.off`, and at `.off` pump-275 commits nothing (live reason histogram:
`nothingClosed`). PU.67 stays held and PU.81 is its reopen path, with the arm's re-measure in
PU.81's Checks. Falsifiers #1, #3, #4 did not fire (heldout rose on both arms with zero wrong;
pump-251's 75.36 is gone from the train wrong list; no heldout close rode the slack - A5's
enumeration precondition is satisfied by the stronger direct measurement: every arm's commits ROSE,
so there was no casualty to name to the owner). #6 is moot - no SGR fit was run.

### M3's absence: no promise of the ROW unmet, and it is now recorded in writing

- The note itself withholds runtime status from M3: "**Ship rule: theta ships only if the heldout
  gate passes at it** - and §0.2's overlap predicts it will not" (:360-361), "M3 ships no runtime
  code unless a theta passes the gate" (:486-487). Its deliverable is the curve - "the price list
  the owner reads".
- The ROW's Checks cell never names M3. It names "the published method from the note implemented at
  that seam", and the seam the row names is the tier that admitted each wrong cell (§0.1's table:
  the triple tier's slack and the pair tier's bands - M1 and M2). M3 governs a confidence threshold;
  no threshold ships, so there is nothing for it to govern. Every gate clause passes without it.
- §0.2's measured overlap (wrong photos 0.012-0.790 nats vs heldout pump-139 correct at 0.200,
  note :77-82) is why the absence is a measurement, not an oversight: no theta keeps the heldout
  floor and catches the wrong photos.
- PU.81's owner-chosen beam guard removed M3's only downstream consumer (its option C).
- Review 1's actual gap was the RECORD, and it is closed in both places the fix demanded:
  `docs/TASKS.md:1068` ("M3 ... not built: it ships no verdict, the note's §0.2 margin overlap
  predicts no threshold passes the heldout floor, and PU.81's owner-chosen beam guard removed its
  only consumer; **a row if the owner wants the price list**") and `docs/EXTRACTION.md:1105-1108`
  (same, with the Geifman & El-Yaniv attribution). The :1105 mislabel review 1 found ("the note's
  third step" for what is M2's repair step) is fixed - the sentence now reads "**M2's repair step**,
  one confusable cell of a pair repaired against a shown price" (:1108-1109). Droppable only in
  writing; it is now dropped in writing.

---

## Item 2 - Wired into the app path, Release as well as Debug: **MET**

Review 1 read the chain end to end; nothing in it has moved since (no file under `ios/App` or in the
chain is in `git status`), and I re-verified the load-bearing points myself:

- `PumpReader.read` -> `PumpReadingLaw.resolve` (`PumpReader.swift:557`); the Live-Photo fusion path
  (`PumpFrameFusion.swift:74`); `CapturePipeline.process` -> `PumpDisplayCapture.classify` (review
  1's citations `CapturePipeline.swift:44-63,:60,:126`, `PumpDisplayCapture.swift:302,:317-342` -
  files unchanged).
- **No `#if` of any kind** in `PumpReadingLaw.swift`, `PumpReader.swift`, `PumpDisplayCapture.swift`,
  `CapturePipeline.swift` (rg, no match, exit 1). Nothing here is a DEBUG seam.
- **Release compiled the mechanism**: `pu78-gate.log:4717` `[gate] release exit 0`. That build ran at
  ~01:15, before the 01:42 comment-only edit established above, so the current bytes are
  Debug-compiled twice over (`pu69-app.log` 03:05, `pu69-swifttest.log` 04:00) and
  Release-compiled modulo comments. Rule 14's RELEASE requirement attaches to `#if DEBUG` seams,
  which this row has none of; the Release run was belt-and-braces and it passed.
- **The measurement is on the app's entry point**: `livePath` and `trainSplitRiskBound` both build
  through `PumpDisplayCapture.makeReader` and report as "PU.63 live path (the app's classify)"
  (`PumpReaderPipelineTests.swift:83-117,:127-138`; report line in every log).
- **Review 1's caveat is closed**: the app-target unit bundle ran - `pu69-app.log:2`
  (`xcodebuild ... test "-only-testing:TankbookTests"`), `:3876` **Executed 301 tests, 0 failures**,
  including `CapturePipelineCompositionTests` at 03:04:47 (`:3013-3015`,
  `testADiscountedPairKeepsTheBoardPriceOut` passed) - the app-bundle test that asserts the caution
  channel PJ.500 built and PU.78 changes the frequency of. The law it compiled is the current one
  (mtime 01:42 < 03:05). Not the "docs naming behaviour with no call site" shape.

---

## Item 3 - Measured on the app path, on the named population: **MET**

### The row's three gate clauses, against the logs

| Clause | Evidence | Verdict |
|---|---|---|
| **Zero wrong on heldout** | `pu78-measure-2.log`: annotated **118 committed, 118 correct, precision 1.000** (41/68 photos), no `WRONG` line; live **47/47**, "photos: 17 committing, **0 with a wrong cell**". Same on the DRIFTED corpus at 04:00 (`pu69-swifttest.log`: 116/116 precision 1.000, 47/47, 0 wrong) - the law's behaviour is identical on both corpora; only the population differs | MET |
| **The train wrong count falls** | baseline 7 cells / 5 photos (PU.68's row, `docs/TASKS.md`) -> `pu78-measure-2.log` **6 cells / 4 photos**: the WRONG list is PU.68's minus pump-251 (099 total, 137 liters+total, 264 total, 266 liters+total) - exactly the note's prediction (§5 :461, "7 -> 6 (pump-251's 75.36 refused)"). No new wrong anywhere | MET |
| **Heldout commits do not fall** | live 45 -> **47** (`pu79-on-b42f38da.log` baseline per review 1 -> measure-2), annotated 112 -> **118** | MET |

Intervals beside every point estimate (PU.68's instrument): Wilson two-sided and one-sided plus
Clopper-Pearson on all three arms, the train photo wrong-commit UCB 0.1843 (delta 0.05) / 0.1629
(delta 0.10) and HB p 1.0000, every print labelled in-sample. `PUMP_CERTIFY=1` ran (the train test
executed, 1879.7 s). Constants match the committed-corpus run: `PumpPhotoGate.swift:86,:91,:95` =
47/47/183, `committedFloor` 118 (`PumpReaderPipelineTests.swift:30`), `liveCommittedFloor` =
`readerCommitted` (`:58-59`) - and measure-2 read exactly 118, 47/47, 183.

### The gate question the brief asks: does stating it against the committed corpus discharge it?

**Yes - discharged, with commit-hygiene conditions that bind the commit's contents, not this
verdict.** The facts, then the reasoning:

- `pu78-gate.log:10121` is `exit 1`, and the ONLY failures in the later full-suite run are the two
  population-count assertions: `committed >= committedFloor` (116 vs 118,
  `pu69-swifttest.log:5247`) and `numericTotal == readerNumericTotal` (181 vs 183, `:5289`). I
  verified the cause myself: the working-tree `windows.json` diff against HEAD touches **pump-275
  alone** - the hand re-frame of its total box (`placedBy: auto -> hand`, `zoom: 0.5105`, quad moved)
  and the removal of `"reviewed": true`. `isHeldout` is `split == "heldout" && reviewed`, so the
  heldout set drops from 68 stills / 183 cells to 67 / 181. The CORRECTNESS assertions
  (`committedCorrect == committed`, `precision >= 0.99`, `committedCorrect == readerCommittedCorrect`,
  committed == 47) all PASS in the drifted run - the row's law is green on both corpora; only the
  denominator moved.
- **No permissible action could make the working-tree gate green while pump-275 is open.** The
  standing fence forbids touching, reverting or checking out the annotator's files; re-setting the
  constants to 116/181 would pin the gate to a MID-EDIT corpus, contradict the committed one, and
  un-measure the very still PU.81 and PU.67 turn on. The row is being scored against a moving
  population it does not own.
- **The commit tree's green is established, not merely predicted.** The commit will carry the
  committed corpus (`b42f38da` bytes - pump-275 reviewed, 68 stills, 183 cells). On exactly those
  bytes, measure-2 read 118/118, 47/47 of 183, train 126/120 - every floor assertion satisfied
  (118 >= 118; 183 == 183; 47 == 47). On the current law bytes, the 04:00 full suite passes
  everything else (2283 of 2285) and reproduces the identical law behaviour (oracle 774, fragility
  0.0412, reason histograms shifted only by pump-275's absence: `nothingClosed` 22 -> 21, stills
  51 -> 50). The two evidence lines meet at the commit tree; a fresh-checkout gate run would
  re-derive arithmetically certain results at the cost of an hour of a loaded machine.
- **The precedent is exact, twice over.** PU.79 (`docs/TASKS.md:1070`): the owner's pump-014
  re-frame cleared `reviewed` in the working tree, and the row closed "when `gateMirror` reads 112
  **on that commit**" - floors evaluated against the corpus commit, constants moved in the corpus's
  commit. And PU.69 committed at 05:53 - forty minutes before this review - under the SAME two red
  floors, its review 5 ruling them "pump-275 corpus state ... not this diff" and directing the
  identical hygiene (`PU.69-COMPLETENESS-5.md:62-64,:77-85`). Holding PU.78 to a stricter standard
  than the commit that landed under it an hour ago would be arbitrary.
- **The row's sentence is the opposite of a silent pass**: it names the corpus the gate is stated
  against (`b42f38da`, 68 stills, 183 cells), names every log, names the sole red cause and its
  owner, and binds the follow-up in writing - the constants are re-measured and moved **in the
  commit that carries the owner's pump-275 edit**, as pump-014's were. Hard rule 14's purpose (a
  known-good state, verified by exit code) is met: every tier this row touched has a green exit code
  on its bytes - lint 0 (re-run by me on the current files), package build 0, app Debug build 0,
  app bundle 301/301 exit 0, Release build 0 - and the only red exit code in evidence is two
  assertions scored against a population the owner is mid-edit on, which the commit will not
  contain.

**Conditions on the commit (blocking for its contents, not for this verdict):**

1. **`Spike/ReceiptSpike/fixtures/corpus.sqlite` is STAGED right now** (`git status`: `MM`;
   `git diff --cached`: 26 718 208 -> 27 086 848 bytes, while the worktree copy is already
   27 127 808 - the index holds a mid-session annotator state that matches NEITHER HEAD nor the
   working tree). A bare `git commit` would ship it alone. Unstage it, or commit strictly by
   pathspec. PU.69's review 5 gave this same warning and it is back.
2. **Do not let the owner's corpus files ride**: `windows.json` (its pump-275 state is what reddens
   the floors), `pump-live/corrections.jsonl`, `video-labels.json`, `videos.json`, `corpus.sqlite`.
3. **`docs/TASKS.md` carries concurrent PU.72/PU.73 edits** (PU.72's "Built" result, PU.73's tick
   and result - its own completeness review was still running at 06:13). Stage the file knowingly,
   per the owner's sequencing for those rows; PU.78's commit owns the PU.78 tick, the PU.81 row and
   the index lines 167-168.
4. **Include the untracked artefacts the row cites by path**: `ios/Tests/TankbookCoreTests/
   PumpReadingLawExactTests.swift` (the suite the mutations and the gate evidence name - the commit
   is broken without it), `agents/research/PU.78.md` (cited from `PumpReadingLaw.swift:14,:267` and
   `docs/EXTRACTION.md:1095`), `agents/briefs/RESEARCH-PU.78.md`, `REVIEW-COMPLETE-PU.78.md`,
   `REVIEW-COMPLETE-PU.78-2.md`, `agents/reviews/PU.78-COMPLETENESS.md` and this file.
5. **Not this row's**: the `ml/pump-reader` changes (temperature.py, model.py, train.py, their
   tests, `runs/2026-09-23`, `runs/2026-09-24`) belong to the PU.72/PU.73 commits.
6. When the owner's pump-275 edit commits, the promise in the row activates: re-measure and move
   `readerNumericTotal` (:95), `readerCommitted`/`Correct` (:86,:91), `committedFloor`
   (`PumpReaderPipelineTests.swift:30`) and its history comment (:27-29) **in that commit** - and
   PU.81 should note whether the hand re-frame alone changes pump-275's read.

---

## Item 4 - No regression elsewhere: **MET**

- **Receipt leak did not rise**: `pu69-swifttest.log:5269` "PU.38 heldout classification: 5/6 pumps
  (5 fast), **0/8 receipts leaked**" - unchanged, on the current law bytes. Routing lives in
  `PumpDisplayCapture.decide`, untouched. Review 1's structural argument also stands and I
  re-checked it against the code: every new predicate is a strict subset of the retired one
  (`rounds` subset of `miss <= 0.011`; `floored` in `{product, product-0.01}` so its exact match
  implies `miss < 0.0105`; preset `<= 0.005p` subset of `<= 0.011 + 0.005p`; an exact pair close
  against a band-filtered shown price sits within half a cent over litres of `implied`, so the
  5 %-gated branch cannot lose it). A leaked fixture can commit strictly less than before.
  `PUMP_LEAK=1` not re-run; the row does not promise it and PU.68's finding (0 commit a field) can
  only be strengthened by a narrowing.
- **Annotated floor rose**: 112 -> 118 (measure-2), 116/116 even on the drifted subset.
- **Oracle ratchet rose**: `pu69-swifttest.log:3423` "PU.21 oracle strings: committed **774**,
  correct 773, precision **0.99871**, coverage 0.871 of 889; wrong: [pump-031 ... the declared
  artefact]" - against floors 294 / 0.996 (`PumpReadingLawTests.swift:16-17`), pre-row 771/770. On
  the current bytes, matching the row's claim exactly.
- **Fragility holds**: `:3544` "PU.21 fragility: committed 995, wrong 41 (**0.0412**)" against the
  0.10 ceiling - and the M1 mutation reads 1035/53 = 0.0512, so exactness LOWERS the fragility
  wrong rate. Review 1's caveat (no like-for-like pre-row baseline on the current corpus) stands as
  a caveat, not a fall; the row's "0.041 (<= 0.10)" is honest.
- **Latency**: the row now carries the immateriality argument review 1 accepted as the alternative
  ("Latency: immaterial by construction - ... inside the same loops; no stage, call or allocation
  is added"). I verified it in the code: `cents(floorOf:)` is computed ONCE per (litres, price)
  pair, hoisted above the totals loop (:412); per triple the close costs one or two abs-comparisons
  where the slack cost one, and the preset branch LOST an addition. Microseconds of flops inside a
  loop dominated by per-cell model inference (the live arm takes ~600 s for 68 stills in Debug;
  PU.75's row records Release read 112-164 ms per photo on a Mac). No Release timing was taken;
  the argument is sound and it is in the row, so the next reviewer does not re-ask. MET on review
  1's own offered remedy and note §6's allocation ("the Release number is owed by the implementation
  (the row's gate)" - the row's Checks cell does not name it; the row now answers it in writing).

---

## Item 5 - Tests that would fail: **MET**

Both mutations are in the evidence with verbatim red output, on the right tests, for the right
reasons (I read both logs in full):

- **M1 revert** (`pu78-mutation-M1.log`, restore the 0.011 interval) - **2 red**: "a total one cent
  off the product does not close: the check is exact" fails BOTH asserts with `reading.total.value
  → 75.36` (pump-251's shape, green-wrong again - precisely what the note §6 asked this mutation to
  demonstrate), and "a pair near a shown price but not exact is a difference, not agreement" fails
  with `committedCount → 3` plus the missing caution (with slack back, 10.00 x 2.008 = 20.08 closes
  against a shown 20.01). The corpus instruments move in the same log (oracle 780, fragility
  0.0512), and the `floored was never used` warning is the mutation's own fingerprint - the revert
  replaced the predicate, it did not delete the mechanism.
- **M2 revert** (`pu78-mutation-M2.log`, restore `pairAgreementTolerance`) - **3 red**: the near-miss
  pair, "a pair a cent off an exact close against the board is cautioned, not agreed", and "PJ.500:
  a shown price the pair closes exactly against carries no caution; 0.4 % off does" - all on
  `expected shownPriceDiffers`. Oracle and fragility UNCHANGED (774 / 995-41), which is the correct
  coverage shape: M2 moves cautions, not committed cells, and without these three tests the
  mutation would be invisible.
- **Traceability**: the logs cite `PumpReadingLawTests.swift:224,:243,:254-255,:440`; those tests
  now live at `PumpReadingLawExactTests.swift:14,:31,:45` and `PumpReadingLawTests.swift:378` (the
  split landed 01:09:50, after the 01:08 mutation runs). Names and assertion texts match the tree
  one-to-one; the row now says so ("The mutation logs were taken before the three new tests moved
  ... their line numbers do not address the tree"). Review 1's must-fix 7 closed.
- **The branches nobody mutated are still pinned**: the floor half of the close is load-bearing in
  `ambiguityWindowIsLoadBearing` (rewritten to 7.00 x 2.001 = 14.007 - rounds to 14.01, floors to
  14.00 - asserting `closed.count >= 2`, "the beam must offer a second closing triple for this test
  to mean anything"; dropping the floor branch takes it to 1 and reddens it) and
  `partialReadCarriesFieldReason` (same arithmetic); the preset narrowing is covered by
  `readWindowIsLoadBearing` and the extractor/repair tests (review 1's citations, files unchanged
  since). The exact-closes suite passes on the current bytes (`pu69-swifttest.log:5096`, its
  one-cent test at `:4711`).

---

## Item 6 - Docs reconciled: **MET**

Review 1's five gaps, each verified closed in the tree:

1. **M3 recorded, mislabel fixed**: `docs/EXTRACTION.md:1095-1109` - the "close is exact" paragraph
   names the paradigm, the retired constants, the preset exception, all three measured movements,
   the ownership of what stays wrong (099/264/266 -> PU.73, 137 -> PU.74), M3's absence with its
   three reasons and "if the owner wants the price list it is its own row" (:1105-1108), and
   "**M2's repair step** ... held as PU.81" (:1108-1109). The row carries the same record.
2. **The contender comment rewritten**: `PumpReadingLaw.swift:455-460` now describes the exact
   close - "a competing triple that reaches the SAME total **only by flooring** is a false close of
   an operand" - matching what the filter (:461-463) does.
3. **The four doc edits**: `docs/EXTRACTION.md:1017-1023` ("by more than rounding", the duplicated
   "by" gone; "**Agreement is exact since PU.78**" with pump-275's 0.056 % example); `:901` (the
   45/45 bound dated "the app path on 2026-09-23; **47/47 since PU.78**"); `:1133` ("(45/45 then;
   47/47 since PU.78)"); `docs/TASKS.md:1062` (PJ.500: "(The 0.5 % agreement band was retired by
   PU.78, 2026-09-24: agreement is exact; the test is now `pairAgreementIsExact`.)").
4. **`docs/ERRORS.md` and `docs/JOURNEYS.md` correctly unchanged** (neither is in `git status`):
   review 1 established the ERRORS trigger copy ("near but not equal to") became literally true and
   J4 has said "more than rounding" since PJ.500 - the user sees no new surface, only a truer one;
   the caution channel and its confirm are unchanged, only their frequency moves. Hard rule 7
   untouched; no UI change, so no screenshots owed.
5. **Index gates**: `scripts/tasks-index.py --check` exit 0 (index carries the PU.78 tick and the
   PU.81 row, `docs/TASKS.md:167-168`); `scripts/scenario-index.py --check` exit 0, 528 rows, PU.81
   attached to J4/F2.

**The comment audit the brief asks for.** `rg closingSlack|pairAgreementTolerance` over `ios/`,
`backend/`, `design/`, `scripts/`: **zero hits** - gone from code and code comments entirely. The
remaining hits are records that SHOULD name them (`docs/TASKS.md:1062,:1068`, `agents/research/
PU.78.md`, the briefs, both reviews, `ml/pump-reader/REPORT.md`'s dated PU.34-era entry). Every
comment in `PumpReadingLaw.swift` now describes the exact close: the header (:9-15, "the shown total
is the product rounded or floored to the cent, never a value near it", with the §2.1 authority
citation), the repair tier (:113-114, now literally true), the `pairOutcome` doc (:265-274, steps 1
and 2 - correctly NOT narrating the unshipped repair), the nudge (:310-311), `closesExactly`
(:316-317), `Triple.exactClosing` (:345-348), the inline close comment (:414-419, the preset bound
as "a bound from the volume display's resolution, not a tolerance on the total"), and the contender
filter (:455-460). CLAUDE.md's same-change audit rule is satisfied in every touched file - the test
files' rewritten comments (`exactOperandBeatsSlackOperand`, `partialReadCarriesFieldReason`,
`pairAgreementIsExact`, `ambiguityWindowIsLoadBearing`, the `committedFloor` history at
`PumpReaderPipelineTests.swift:27-29`) all state the current rule.

Two advisories, neither blocking (both pre-existing shapes review 1 ruled non-must-fix):
`PumpReadingLaw.swift:260-262` still carries a mutable measured count ("6 of 8 pair commits") in a
comment - CLAUDE.md forbids the species, the claim is a counterfactual about the band ALONE so
PU.78 does not contradict it, and the cheapest fix (keep the justification, drop or source the
count) belongs to whoever next opens the file; and `PumpReadingLawTests.swift:151-152`'s display
name still says "inside the truncation slack" for a scenario that can no longer occur (its comment
was correctly rewritten to say the near miss "no longer closes at all") - the repo's lineage-naming
pattern (PU.51/PU.54/PJ.500 prefixes) covers it, but a rename would make it current truth.

---

## Item 7 - Everything the row promised, sentence by sentence

The Checks cell of `docs/TASKS.md:1068`:

| Sentence | Verdict |
|---|---|
| "Each of the seven wrong cells traced to the law tier and the rule that admitted it (pump-read tool, app path)" | **MET, exceeded**: the note §0 traces **eight** cells (7 train + heldout pump-275) through `pump-read --trace-serve` -> the app's `classify` (`TraceServe.swift:78-80`), replicating the law's verdicts in Python **to the nat** (pump-137 `-12.234401` vs `-12.234401477523217`), and refutes the row's own working inference for three of the eight (251/137 are the triple tier's slack, not the pair bands) - the trace doing its job |
| "the published method from the note implemented at that seam" | **MET**: M1, M2 steps 1 and 3 at exactly the traced seams; M2 step 2 held as PU.81 with the owner's decision (legitimate - item 1); M3 absent and recorded in writing with its three reasons and the reopen path (item 1) |
| "train split (in-sample, `PUMP_CERTIFY=1`) and heldout app path both reported with PU.68's intervals" | **MET**: measure-2 ran certify (1879.7 s), both arms print two-sided/one-sided Wilson + Clopper-Pearson, train adds the UCB at both deltas and the HB p-value, every print labelled in-sample |
| "zero wrong on heldout" | **MET** on both arms and both corpus states (118/118 and 116/116; 47/47, "0 with a wrong cell") |
| "the train wrong count falls without heldout commits falling" | **MET**: 7 -> 6 cells, 5 -> 4 photos, pump-251 gone, no additions; heldout 45 -> 47 and 112 -> 118 |
| "oracle ratchet and fragility hold" | **MET**: 774 at 0.99871 (floors 294/0.996) and 0.0412 (ceiling 0.10), both on the current bytes at `pu69-swifttest.log:3423,:3544`, both moving the RIGHT way under the M1 mutation |
| "completeness review COMPLETE" | **This review** |

Every result-cell claim I checked is accurate against the logs and the tree: the eight-cell trace,
M1/M2 as described, both constants retired, the preset bound kept, the repair held ("it corrupted
pump-014" - the measure.log line), 45->47 / 112->118 / 124-117->126-120, 41/68 photos, the
ownership of what stays wrong, oracle 774 at 0.9987, fragility 0.041, both mutation counts (2 red /
3 red), M3's record, the mutation-line-number note, the latency argument, and the gate sentence -
including its hardest number: "2285 tests, the only failures the two floors that count pump-275"
is exactly `pu69-swifttest.log:5300` plus the two ✘ lines. Review 1's two inaccurate claims (the
constants vs the drifted tree) are resolved by the gate sentence stating which corpus they belong
to. **PU.81** is properly drafted: mechanism, pump-014's arithmetic (3.82 x 1.834 = 7.006 -> 7.01,
the unique close against four boards), the owner's decision A and fallback, a Checks cell, the J4/F2
link, an index line. PU.67's row now points forward to it ("the re-measure (with PU.81's guard)"),
closing review 1's found-not-fixed 8.

---

## Found and not fixed

1. **The staged `corpus.sqlite`** (index bytes match neither HEAD nor worktree) - orchestrator,
   **blocking for the commit's contents** (condition 1 above).
2. **`docs/TASKS.md` carries the concurrent PU.72/PU.73 edits** - orchestrator/owner sequencing
   (condition 3).
3. **The untracked artefacts** (ExactTests + the six agents/ files) must ride the commit
   (condition 4).
4. **The deskew-`.onRefusal` arm was not re-measured after PU.78**; `docs/EXTRACTION.md:1128-1133`
   still quotes its pre-PU.78 52/51 - **owned by PU.81** ("PU.67 re-measured on it"); the app
   ships `.off`.
5. **`agents/research/PU.72.md:98`, `PU.74.md:148,:297`, `agents/briefs/RESEARCH-PU.72.md:19`**
   cite `closingSlack (:27)` as a live constant - **owned by PU.72/PU.74**, both open, both about
   to meet implementers; a "retired by PU.78" line at each site is cheaper than a rediscovery.
6. **The two comment advisories** (law :260-262 "6 of 8" count; LawTests :151 "truncation slack"
   display name) - no row owns them; one clause each at next touch.
7. **No sibling fix is owed** - review 1 checked the nearest siblings (`CrossCheck.
   crossCheckTolerance`, `PumpExtractor.exactTolerance`, `DigitRepair`) and its reasoning holds on
   re-read: a receipt's total comes from a different device than its line items (a tolerance there
   is a consistency signal), while a pump head's total is its own product (zero tolerance is
   correct), and the other two are already exact.

---

## Verdict

# COMPLETE

Every item MET. The orchestrator may commit - **subject to the six commit-hygiene conditions under
item 3** (unstage or pathspec around `corpus.sqlite`; exclude the owner's corpus files; stage
`docs/TASKS.md` knowingly; include `PumpReadingLawExactTests.swift` and the six cited agents/
artefacts; leave `ml/pump-reader` to PU.72/PU.73; re-set the constants in the commit that carries
the owner's pump-275 edit, as the row promises). The gate is discharged against the committed
corpus: the law is green on every byte of it that can be run without touching the owner's
annotation session, the only red assertions in evidence are two population counts that the commit
will not contain, and the row says all of this out loud, in writing, with the precedent named. No
gap needs a new row beyond the two already filed (PU.81, and M3's price list if the owner ever
wants it - recorded in both docs).

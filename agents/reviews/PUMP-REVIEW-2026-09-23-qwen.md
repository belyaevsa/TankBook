# PUMP-REVIEW (qwen, 2026-09-23) - an outside review of pump-display recognition

Read-only review, second independent look after `agents/reviews/PUMP-DECIDE-2026-09-22-fable.md`.
Read: `docs/EXTRACTION.md` → "The pump reader" (lines 816-1084, decisions 1-11 with all
amendments), `ml/pump-reader/REPORT.md` (all 2259 lines), `CORRECTIONS.md`, every `PU` row and
`PJ.500` in `docs/TASKS.md` (lines 988-1046) and `docs/TASKS-DONE.md:704`, the four prior reviews
named in the brief, all 18 Swift files under `ios/Sources/TankbookCore/Extraction/PumpReader/`,
`PumpPhotoGate.swift`, `CapturePipeline.swift`, `PumpReaderPipelineTests.swift`, the training code
(`ml/pump-reader/src/pump_reader/`, `detector/train.swift`), `docs/JOURNEYS.md` J4/F2,
`docs/DEFECT-PATTERNS.md`, `HANDOVER.md`. **I ran no build, no test and no measurement**; every
number below is quoted from a file with its location, or computed from quoted numbers and labelled
as arithmetic. Literature references were verified against the arXiv API on 2026-09-23 where the
entry says so; the few classics not on arXiv are marked "not verified online". One file written:
this one. Where I infer, I say so.

The product owner's goal, unchanged from 2026-09-22: *"improve the recognition of pump's photo,
lift it and make it faster."*

---

## 0. The verdict in one page

1. **The architecture is right and its precision mechanism works.** The live app path commits
   **45/45 cells at precision 1.000, 15/68 photos fully right** (`PumpPhotoGate.swift:86-95`,
   PU.63), and the arithmetic law on perfect strings commits **763 at 0.9987** (`REPORT.md` PU.54,
   lines 2056-2061). Nothing else in this codebase's history - Vision+rules (53/865 at 0.946 on
   macOS 26, 13 hits on macOS 27, RV.295) or the cloud model (31/46 with a factor-of-ten shift and
   6.5-8.3 s median, `docs/EXTRACTION.md:1095-1135`) - has ever met the 0.99 floor on pumps. The
   segment-level output + constrained decode + uniqueness law is the reason, and the evidence
   supports keeping it.

2. **The binding constraint is geometry, and it is now priced.** The apportionment (PU.64,
   `docs/EXTRACTION.md:1059-1069`) puts the losses at: oracle 108 → rows found 95 (-13) → verifier
   kept 78 (-17) → **the detector's framing 45 (-33)**. The framing loss is not misplacement, it is
   the **upright rectangle**: 140 of 190 heldout hand boxes are turned (median 1°, p90 4°, max 18°)
   and Create ML emits upright boxes only. Hand boxes redrawn as *perfectly placed upright*
   rectangles commit 89 but at **0.944** - worse precision than the detector's noisy boxes at
   1.000. Read together with PU.58 (band trim: more rows kept, live 47 → 44 off, two wrong
   readings, dropped) and PU.66 (three retrains, all refused, all produce wrong readings where the
   shipped model makes none), the corpus is saying one sentence: **tighter or cleaner upright boxes
   do not help; turned boxes do.** The one change that has ever lifted the app path without a single
   wrong reading is turning rows to their digits' angle: deskew `.onRefusal` measures **54/54**
   (PU.65, commit `d1ea3f44`) against 45/45 off, and is built, tested, and sitting behind a flag the
   owner has not flipped.

3. **"Faster" is solved on paper and unmeasured on a phone.** Release decision 13-73 ms,
   classify+read 112-164 ms on 12 MP stills (`REPORT.md:1123-1128`) against a 3 s budget - but on a
   Mac. No device number exists (RV.295 open; PU.39's Capture Lab never run), the 31 MB detector's
   ANE behaviour on an iPhone 12 is unknown, and the latency the user actually feels in J4 is
   dominated by the receipt-OCR arm `CapturePipeline.process` runs **serially after** the pump read
   (`CapturePipeline.swift:57-77`). There are also three cheap code-level speed wins nobody has
   filed (§2.6): a Vision text-line pass that runs on every photo and decides nothing on the fast
   path, five separate Core ML predictions per cell where one batched call fits, and per-pixel
   Swift loops for warp/resample/downscale.

4. **The measurement instrument is the weakest component in the system.** The yardstick is 68
   stills / 183 cells; the review of 2026-09-20 computed a **±13-cell sampling noise band** at that
   size (PU.32 review, cited in fable §8 item 8), and the last four live moves (43 → 45 → 47 → 54)
   are all inside or near it. "Precision 1.000 on 45 commits" has a 95% Wilson lower bound of
   **≈0.92** (arithmetic from the quoted n, §2.1); the annotated tier's 110/111 gives ≈0.95.
   Neither tier can statistically distinguish 0.99 from 0.95 today. The gate that decides shipping
   (`allowsPumpPhoto`) still reads the **composite constants 53/56/53/865** whose binding test is
   macOS-26-only and was skipped for the whole tranche (PU.61, `PumpPhotoGate.swift:39-64,137-139`).
   And the detector candidates are scored from a dev path, not the shipped resource (`REPORT.md:
   1685-1689`). Every recommendation in §3-§4 is priced against this instrument, and the first
   recommendation for any of them is to widen it.

5. **Where I differ from the fable review.** It predicted (fable §5) that a vertical-only box swap
   would "recover most of Run A" and priced PU.58-class trims as the right shape. PU.64's
   apportionment and PU.58's own measurement have since falsified the trim half: upright-rectangle
   boxes at perfect placement read 89 at **0.944**, and the shipped trim lost live cells. The
   apportionment's real lesson is stronger than fable drew from its Run-A prediction: the gap
   between 45 and 111 is not "box tightness" but **box orientation plus label noise** (hand quads
   meet each other at IoU only 0.75-0.79; "the detector's median IoU (0.80) is that noise,
   learned", `REPORT.md:1160-1169`). That reorders the work: deskew first (measured, free), label
   consistency second, an oriented-box detector third - and no further upright-box refits at all.

---

## 1. Question 1 - the current solution as an approach and architecture

### 1.1 What it gets right (ranked)

**1. The law is the precision mechanism, and it is the only one that has ever worked.**
`PumpReadingLaw.resolve` commits only when `litres × price = total` closes **uniquely** within
nat-space windows (`PumpReadingLaw.swift:45-152`): `closingSlack` 0.011 (one cent + rounding,
line 27), `ambiguityWindow` 3.0 and `readWindow` 6.0 with the documented rationale that one
misread cell ≈ 3.5 nats (lines 28-38), `maxSubstitutions` 1 (line 343). The measured consequence:
live precision 1.000 across 45 commits while every coverage-raising candidate that weakened a
guard was refused (band-only pairs at 0.831, PU.54; round-10 seeds at 0.914-0.971, `REPORT.md:
736-748`; PU.48 candidate at 0.944/0.964). This is exactly what F2 demands ("a confident wrong
value is worse than a nil", `docs/EXTRACTION.md:1086-1093`) and exactly what the cloud model fails
(silent swaps that pass `a×b = b×a`, decimal shifts that pass scale-invariant arithmetic,
`docs/EXTRACTION.md:1116-1135`).

**2. Segment-level outputs instead of a 10-class head.** 8 sigmoids + a lookup over the 117 valid
patterns (`PumpSegmentsModel.swift:18-22,59-71`) made constrained decoding a pure win (digit-only
0.532 → 0.666 with no retraining, PU.16, `REPORT.md:279-296`), made the repair tier composable
(one substituted cell with a known posterior, `PumpReadingLaw.swift:115-151`), and made the dp bit
separable from the digits - including the mutation test that proved the dp bit load-bearing
(0.89 → 0.49 chance, `REPORT.md:664-681`). The origin decision (`docs/EXTRACTION.md:829-833`) is
validated by four years' worth of downstream use in four rounds.

**3. The verifier/decision split, model-free by construction.** PU.47 moved the keep decision to
`PumpRowGeometry` (cell count, pitch-to-band, ink band, mark position, blank layout -
`PumpRowGeometry.swift:22-103`) and the decoupling test proves it: kept rows are **identical
(216)** for round 6 and a round-11 candidate (`PumpReaderPipelineTests.swift:400-466`,
`REPORT.md:1492-1511`). That ended the worst coupling in the system - three classifier retrains
had each moved the live number down without touching a pixel of the read (rounds 8/9/10: live
11 → 4 → 2, fable §2). One classifier coupling survives in the *display decision* (§2.2).

**4. The three-tier measurement ladder with a frozen split.** Oracle strings (763 @ 0.9987) /
annotated hand quads (111 @ 0.991) / the app's own `classify` (45 @ 1.000), on a heldout split
drawn once and never redrawn (decision 9, `docs/EXTRACTION.md:873-897`), with ratchet floors
wired into the gate's own constants so a reader change moves what the gate reports (PU.61,
`PumpReaderPipelineTests.swift:53-58,105-114`). The apportionment test (PU.64) completes it: one
live stage swapped in at a time against the oracle chain, so every cell lost has a stage's name on
it. This is unusually good empirical hygiene; most of what follows criticises its *power*, not its
design.

**5. Latency architecture.** The fast path decides from the detector's own rows with no warping,
slicing or classifier (`PumpDisplayCapture.decideAt`, lines 192-216; `fastVerdict` 135-148), the
slow path is wall-clock capped at 1.5 s (line 100), and the orientation search runs the
detector+slicer only, never the classifier, per orientation (`PumpReader.orientationScore`,
lines 384-398). Measured result: decision 13-73 ms, classify+read 112-164 ms in Release
(`REPORT.md:1123-1128`).

### 1.2 Where it is structurally limited (ranked)

**1. Upright rectangles are the wrong primitive for the locator, and the ceiling is label noise.**
The detector can only emit what Create ML supports (axis-aligned boxes,
`detector/train.swift:19-25`), while the world it must frame is turned: 140 of 190 heldout hand
boxes are rotated, and an upright box around a turned row is, for a long thin row, mostly
background at its corners - which is also why PU.66's rotation-augmented retrain failed by
construction ("a turned copy's label is the upright box around a turned row - background by
construction", `docs/TASKS.md:1046`). The slicer then inherits the mismatch: its band and pitch
come from what is inside the box (`PumpGlyphSlicer.prepare/context`, lines 145-234), so a box that
carries bezel poisons the thresholds (PU.35: any vertical margin collapsed live 29 → 3-15;
PU.55: pump-092's loss is a function of the box's **vertical extent alone**, `REPORT.md:
1918-1922`). And no retrain can out-tighten the labels: adjacent hand quads differ by up to a
quarter of the row height, meeting at IoU 0.75-0.79; the shipped detector's median IoU 0.797-0.80
*is* that noise (`REPORT.md:1160-1169`). Evidence supports the judgement: the apportionment's -33,
PU.58's dropped trim, PU.66's three refusals, and the deskew arm's +9 at zero wrong readings all
point the same way.

**2. The cascade has hard early exits and no feedback.** A row the verifier drops disappears from
every downstream stage (apportionment: -17; "a row the slicer miscounts is not read badly, it
disappears", `docs/EXTRACTION.md:1066-1069`). The geometry rules are slicer measurements dressed as
row properties (`PumpRowGeometry.Reason` is literally `cellCount/pitch/inkBand/decimalMark/
blankLayout`, lines 22-28), so slicer defects convert into recall loss at the verifier. The only
retry in the shipped pipeline is the orientation search and (behind the flag) the deskew retry
(`PumpDisplayCapture.classify:304-337`). Nothing lets the law say "this row miscounted, re-slice
it wider/narrower" - PU.34 measured exactly that once (expanding the crop: 22 → 17 at 0.71) and
reverted, but a *law-requested* re-slice of an abstaining row, rather than a blanket expansion, was
never tried (inference).

**3. The arithmetic is scale- and swap-blind, by design and by measurement.** `litres × price =
total` cannot see a consistent tenfold shrink (pump-106: 5.1 × 70.31 = 358.58 commits,
`REPORT.md:411-414`) or an operand swap. The law deliberately forbids role swaps
(`PumpReadingLaw.swift:17-18`) and decimal placement comes from currency convention + the mark
hint (`PumpReadingTypes.swift:197-235`), which is the right trade - but the digit-count signature
guard PU.32's review proposed (a total never has fewer cells than its litres, an EUR price is
exactly 4 digits in 63/63 corpus fixtures, PU.14 §2) was **never implemented** (fable §13, PU.32
"Found and not fixed"). Today the residue is mitigated only by F2's non-pump-specific nets
(odometer delta, consumption outlier, `docs/JOURNEYS.md` F2 "The residue").

**4. The reader's cross-check is theatre on reader commits.** Every `.read` triple closes by
construction, so `crossCheck = .lock` whenever the reader commits three fields
(`PumpDisplayCapture.swift:389`), and the F2 "refuses to lock" detection row can never fire on a
reader commit - consistent-wrong reads pass with a green lock. PU.14 named this before the build;
it is still true. (Evidence: the code line; label as accepted design, but it means the 0.99 floor's
residual failures reach the user with maximum UI confidence.)

**5. Coverage is the open product question, and the gate cannot answer it yet.** Live coverage is
45/183 = 0.246 against the 0.60 floor (`PumpPhotoGate.swift:102-105,122`); the annotated tier
shows the read stage can do 0.607 at 0.991, so the gap is entirely upstream of reading. But
`allowsPumpPhoto` still reads the composite constants (line 137-139), whose binding test skips on
this machine - so PU.6 remains unanswerable by construction, exactly as PU.61's row says
(`docs/TASKS.md:1040`).

**6. Single-frame reading, settled.** Live Photo fusion measured +1 committed cell inside seed
noise at 45× the read time (PU.19, `REPORT.md:874-900`); correctly refused on this corpus, harness
kept. Not a structural flaw, a settled negative.

### 1.3 Does the evidence support the judgement?

Yes, with one statistical caveat that applies to everything above: at n=183 asserted cells and
45-54 commits, the live tier's point estimates carry a ±13-cell sampling band and a Wilson lower
bound of ~0.92 on "precision 1.000" (§2.1). The *ordering* of stages (framing ≫ verifier ≫
detection ≫ assignment ≫ read) is supported by the apportionment, which is a within-corpus
decomposition and not subject to the same band. The *magnitudes* of recent moves are.

---

## 2. Question 2 - the implementation as written

### 2.1 What the tests prove, and what they cannot

Prove:
- **Regression, not estimation.** `livePath` asserts `committed == liveCommittedFloor` (exact
  equality, `PumpReaderPipelineTests.swift:97-98`) and the floor *is* the gate's reader constant
  (lines 56-57) - a strong drift alarm, correctly wired after PU.61/PU.63.
- **The verifier is model-free** (decoupling test, lines 400-466; kept rows byte-identical across
  two classifiers).
- **Assignment at 0.995 over 1278 windows** with the floor kept at 0.99 and the 7 residual misses
  named (PU.60, `docs/TASKS.md:1039`).
- **Named mutations are load-bearing**: the dp bit (0.89 → 0.49 when dropped, `REPORT.md:664-681`),
  the slicer's pitch snap (`PumpGlyphSlicer.Options.pitchSnap` seam, lines 36-40), the detector
  gate's ordering (`test_detector_gate.py`, PU.57).

Cannot prove:
- **The precision floor.** 45/45 gives a one-sided 95% Wilson bound of ≈0.92; 110/111 annotated
  gives ≈0.95 (arithmetic from the quoted counts). "Live precision ≥ 0.99" is, strictly, not
  established by any measurement in the tree - it is established *not to have been violated*. The
  abstention design makes violations rare by construction, which is the real argument; but the
  number on the gate is a point estimate. A second frozen draw (fable §8 item 8; batches 6-9 are
  untrained-on by any shipped model) is the only thing that fixes this.
- **The app's own runtime conditions.** The live arm calls `classify` with `budget: .infinity` in
  a **Debug** Mac test (lines 509-515) while the app uses 1.5 s in Release on a phone; PU.63
  itself measured the cap changing the count (42 uncapped vs 39 capped in Debug, "42 is what a
  user gets" - inference carried from that row, not measured on a device). No device number exists
  anywhere (RV.295).
- **The shipped detector.** `PumpReaderTestSupport.detectorURL` reads
  `ml/pump-reader/.out/det/DigitRows.mlmodel`, not the bundle resource; candidates are scored by
  overwriting the dev copy, which is how PU.48's two exports got conflated (`REPORT.md:
  1685-1689,1881-1889`). No `PUMP_DETECTOR=` override exists (fable §10 note b).
- **Leak consequences.** 5 of 116 non-pump fixtures route as pump displays (PU.65; unchanged by
  PU.63). Routing is measured; **what those five then commit, and with what provenance, is not**
  (inference from absence - no test or report line scores their readings). A leaked receipt whose
  display rows close arithmetically becomes a `.pumpPhoto` entry with reader fields composed over
  the receipt parse (`CapturePipeline.swift:63,78-84`).

### 2.2 Hidden coupling between stages (ranked)

**1. The display decision still reads the classifier on the slow path.**
`PumpDisplayCapture.displayRows` keeps a Vision-proposed row only at
`meanMargin >= classificationMinimumMargin` (1.5) (`PumpDisplayCapture.swift:266-277`). PU.47
decoupled the *verifier*; this decoupled nothing here - a retrain can still silently change which
photos classify on the slow path (pump-035 at 31 text lines is exactly such a photo). The report
flagged it and "no row owns it" (`REPORT.md:1538-1542`).

**2. The law is coupled to the classifier's posterior scale.** The nat windows (6.0/3.0/4.0,
`PumpReadingLaw.swift:27-43`) are calibrated to "one misread ≈ 3.5 nats" *for the round-6
model's* margin distribution; PU.52 showed retrains move cells across the close/no-close cliff
(per-still: gains and losses on named stills) and that is why every better-annotated classifier
lowered live (83/39 → 95/29 → 97/36, `REPORT.md:1288-1296`). A read-stage stability measure, or
thresholds re-fitted per candidate on the train split, "no row owns" (`REPORT.md:1547-1551`).
Related: the repair tier fabricates "certain" substitutes at a fixed confidence 0.97
(`PumpReadingTypes.swift:101-106`), a constant of the same calibration.

**3. The slicer's mark overrides the classifier's evidence, destructively.** When the slicer marks
any cell of a row, every other cell's dp bit is clamped to ≤0.49 and the marked cell is raised to
0.95 (`PumpReader.swift:214-245`). Slicer dp agreement is ~0.52-0.54 (131/250, PU.42), so on a
row where the slicer marked the wrong cell, the classifier's dissenting evidence is erased before
the law sees it, and `decimalMarkPenalty` 4.0 then *steers* placement toward the wrong cell - a
4-nat penalty exceeds the 3-nat ambiguity window, so a wrong mark that closes arithmetic beats a
right placement that also closes (inference from the constants, `PumpReadingLaw.swift:39-43`;
measured consequence: the annotated tier's residual wrong cells, e.g. PU.42's pump-083 "dp one
cell early", `REPORT.md:1037-1043`). The single-decimal-mark rule keeps only the strongest mark
(`PumpReader.singleDecimalMark:252-262`) - a good guard, but it runs *after* the override.

**4. The verifier computes classifier margins it no longer uses, by running the classifier.**
`PumpReader.verdicts` still predicts every cell of every candidate to fill the diagnostic
`meanMargin` (lines 509-519), so on the slow path each kept row is classified twice (once for the
diagnostic, once in `read`). Dead weight in latency and a standing temptation to re-couple.

**5. The composite gate governs the user-facing switch with un-rerunnable constants.**
`allowsPumpPhoto = measuredPrecision ≥ 0.99 && measuredCoverage ≥ 0.60` over 53/56/865
(`PumpPhotoGate.swift:137-139,39-64`), asserted only by `CorpusAccuracyGateTests` which is
`.visionMeasuredRuntimeOnly` (macOS 26) and skipped on this machine for the entire tranche
(PU.61). The reader's constants beside them are live-bound and Vision-free - good - but they do
not decide anything yet.

### 2.3 Numerical choices, graded

- **Sound:** Otsu on the column profile (`PumpGlyphSlicer+Primitives.swift:93`), LCN by division
  against a vertical box blur with polarity decided before normalisation (`PumpGlyphSlicer.swift:
  145-180`), autocorrelation pitch with a fundamental-vs-body halving/doubling guard (lines
  208-230), circular mean for grid phase (line 331), direct 8×8 homography solve instead of SVD
  with an honest rank caveat (`PumpQuadWarp.swift:12-14,200-231`), Decimal-via-string for money
  (`PumpReadingLaw.decimal:312-314`), vImage affine warp for levelling (`PumpRowDeskew.swift:
  298-322`).
- **Questionable:** (a) `SegmentNet` ends in **global average pooling → linear(64→8)**
  (`model.py:27-48`) - GAP destroys the spatial layout that *is* the segment code; the measured
  symptoms fit: d/g weakest segments ~0.58-0.59, dp bit AUC 0.52-0.548 on real cells
  (`REPORT.md:55,295,334`). A flattened or 1×1-conv-over-features head is a same-size change.
  (b) Unweighted `BCEWithLogitsLoss` over 8 bits (`train.py:94,185`) with dp present on ~20.6% of
  cells (`REPORT.md:318-322`) - focal loss or a pos_weight on dp is the textbook fix and was never
  A/B'd (inference from the report's ablation list). (c) FLOAT16 model output (`REPORT.md:718-720`)
  feeding nat-space thresholds - fine today, but it halves the resolution of the very margins the
  law's windows are calibrated in. (d) `profileSharpness` for deskew is a squared first difference
  of row means (`PumpRowDeskew.swift:166-177`) - reasonable, polarity-free, and validated by the
  54/54 measurement; no objection.

### 2.4 Things that make the measured numbers misleading (ranked)

1. **Basis drift with no ledger row.** The cell count moved 175 → 183 → 186 → 182 across rounds and
   corpus sessions (fable §2 notes a-b; PU.63's gate constants are 44/44/182 on 67 reviewed
   stills while the brief says 45/45/183 on 68). Rounds separated by a basis change are not
   comparable, and the ledger does not always say when one happened. This is
   `docs/DEFECT-PATTERNS.md` §7 in the measurement itself.
2. **Debug-Mac floors standing in for Release-device behaviour** (§2.1) - including the
   slow-path budget, which PU.38 showed changes the count in Debug (42 vs 39).
3. **The annotated tier uses the annotation's `rotationCW`** (`PumpReaderPipelineTests.swift:171`)
   - correct for isolating the read stage, but it means "annotated 111" is not a number any phone
   can reach without the orientation search finding the same orientation; PU.53 showed the search
   reproduces the annotation's choice on the rotated stills, so the tiers are consistent, but the
   dependency deserves stating wherever 111 is quoted as a ceiling.
4. **Train-split contamination of thresholds.** `PumpRowGeometry`'s bounds are measured on the
   train split (documented, `PumpRowGeometry.swift:14-18`) - correct discipline - but the law's
   nat windows, the slicer's dozen fractions (`PumpGlyphSlicer.Options`, lines 35-109) and the
   0.1 widening margin (PU.35's sweep on **heldout**, `REPORT.md:767-778`) were tuned against
   heldout live numbers in several cases. The heldout is therefore not fully held out of the
   *pipeline's constants*, only of the models'. A change's "+N live" can partly be re-fitting.
   (Inference, labelled: the sweeps' own tables are the evidence.)
5. **Detector candidate scoring from a mutable dev path** (§2.1) - already produced one documented
   mix-up (PU.57, `REPORT.md:1881-1884`).

### 2.5 Robustness and correctness notes in the code itself

- `fastVerdict` ignores its `textLines` parameter (`PumpDisplayCapture.swift:135`) - intentional
  since PU.63, documented, but the parameter is now a trap for readers; the Detection still
  carries the count for logging.
- `decideAt` computes `textLineCount(upright)` **before** the fast check (line 195) - a full
  `VNRecognizeTextRequest` on a 1600-px downscale (`PumpVisionProposer.swift:64-65`,
  `PumpPanelLocator.swift:31,161`) on **every photo including receipts**, whose result the fast
  path never reads. ~4 ms in Release on the Mac (REPORT.md:1125-1126), unmeasured on device.
  Making it lazy is a one-line speed win (§2.6).
- `PumpRowGeometry.maximumInteriorBlankRun = 1` (line 74) and the decimal-places rule (lines
  61-68) are honest, corpus-derived, and named per-reason in drop diagnostics (PU.64) - good.
- `PumpRowAssignment.assign` hard-codes the column order `[total, liters, unitPrice]` top-down and
  the short-column fallbacks `[liters]` / `[total, liters]` (line 109). On a partial detection
  (two of three rows found) the roles are a guess resolved only later by the law - and when the
  guess is wrong the pair tier is exactly what commits it: PU.59's held measurement (1 of 10 cells
  right; "almost all role misassignments", `docs/EXTRACTION.md:1040-1047`) is this line's failure
  mode, not a digit failure. The hold was the right call.
- `CapturePipeline.composed` (lines 110-117) correctly blocks the rules arm's price beside a
  cautioned pair (PJ.500), and PU.62 measured the fallthrough as 4 cells, all right, all on
  stills the reader abandoned. Residual (inference): when the reader commits a *pair without
  caution* (shown price agrees within 0.5%, `PumpReadingLaw.swift:301-303`), `unitPrice` is
  `.abstained` with no caution, so the rules arm may fill it with the board price; that is within
  0.5% of the implied price by construction, so harmless in value - but the entry's price then has
  rules-arm provenance beside reader-provenance fields, and `crossCheck` stays the rules arm's own
  outcome over the mixed triple (line 83 promotes to `.lock` only on a reader triple). No test
  names this composition.

### 2.6 Speed, as implemented

Measured facts: Release decision 13-73 ms; classify+read 112-164 ms; Debug is 7-25× slower and is
not a latency fact (`REPORT.md:1123-1135`); the Debug decision was once dominated ~337/440 ms by a
per-pixel Swift downscale (`PumpPanelLocator.downscaleRGB:161`), 4 ms in Release; the preview
detector runs ~80 ms/frame on the simulator (PU.40). Unmeasured: everything on a phone.

Code-level wins available without touching a model (all inference from the code, each trivially
measurable with `timingsMs` in `pump-read`):
1. **Lazy `textLineCount`** on the fast path (§2.5) - removes a Vision pass from every pump photo
   and every receipt that the fast path accepts/refuses quickly.
2. **Batch the TTA.** Five crops per cell are predicted in five separate `model.prediction` calls,
   each building its own `CVPixelBuffer` (`PumpReader.swift:558-577`,
   `PumpSegmentsModel.swift:41-52,83-108`). Core ML supports batched pixel-buffer inputs; one call
   per cell (or per row) cuts per-call overhead ~5×.
3. **vImage/Accelerate for `resample`, `warpToStrip`, `downscaleRGB`, `grayscale`** - the deskew
   file already uses `vImageAffineWarp_ARGB8888` (`PumpRowDeskew.swift:317`); the hand-rolled
   bilinear loops (`PumpQuadWarp.swift:165-195,254-277`, `PumpReader.swift:580-608`) are the same
   work unvectorised. Matters most on the iPhone 12 floor, where no number exists.
4. The **31 MB detector** (30.3 MiB, PU.48) is flagged "the owner's call before ship" since PU.33
   and has shipped in every build since; Create ML's 8-bit quantiser trips on its anchor constants
   (`REPORT.md:507-508`), but a MobileNetV3-class or quantised replacement is untried.

---

## 3. Question 3 - other options for the issues we already know

For each: what it would take, what it serves (precision / coverage / speed), and how it would be
measured **on this corpus**. Ranking within each issue is my own.

### 3.1 Detector framing (the -33)

1. **Ship deskew `.onRefusal` in the app** (already built: `PumpRowDeskew`, wired at
   `PumpDisplayCapture.classify:326-335`, flag `PumpReader.deskew`). Serves **coverage** (+9 cells:
   45 → 54) at measured precision 1.000, no new receipt leaks (5/116 either way), cost bounded to
   photos that committed nothing anyway (a second slice+read on ~50/68 stills). Measurement exists
   (PU.65); what remains is the owner's flip and a beta watch. This is the cheapest coverage in the
   tree.
2. **Deskew *with band refit* (`fitsBand: true`) on the refusal path.** The turned box keeps the
   detector's height today (`PumpRowDeskew.swift:90-96`); the refit path (lines 97-116) exists and
   is unmeasured on the app path. Serves coverage; it is the *quad-shaped* analogue of PU.58's trim,
   and unlike PU.58 it operates after the turn, which is the axis PU.55 proved matters. Measure:
   the PU.65 harness arms (live off / on-refusal / on-refusal+fitsBand), ship rule = adds cells,
   zero wrong readings (the owner's PU.58 rule).
3. **Label consistency before any retrain.** The detector's IoU ceiling is the hand quads' own
   0.75-0.79 (`REPORT.md:1160-1169`); PU.66 round 3 proved hand-only labels are the best recipe
   and that the limit is their count (249 stills + 60 verified frames). Serves coverage
   *indirectly* - it is the precondition for 4. Take: re-pin the heldout's 190 boxes under the
   "keep shape" rule, and re-run `detdata`/`measure.swift` (CORRECTIONS.md §6 says recall@0.7 is
   the number that should move). Do not gate on heldout IoU alone - gate on the apportionment arm.
4. **An oriented-box row detector** (the drastic option, §4.1). Serves coverage and precision
   together (it is the only measured shape that reaches the annotated tier's geometry).

Not worth repeating: any further upright-box refit (PumpBoxRefiner 22 → 21 deleted; PU.58 dropped;
crop expansion 22 → 17 at 0.71 reverted) and any retrain on today's labels judged by recall@0.5
(PU.57's gate exists precisely to refuse those).

### 3.2 Role assignment

The annotated floor is 0.995 (PU.60); the live damage is on **partial detections**, where
`PumpRowAssignment`'s fixed order (line 109) guesses, and it is what holds PU.59's cautioned tier
at 1/10.

1. **Digit-count signature constraints (model-free).** An EUR price is exactly 4 digits in 63/63
   corpus fixtures (PU.14 §2, "free, unimplemented audit"); a total's cell count is ≥ the litres'
   on every head; a price row is the narrowest of the three on stacked heads. Re-rank or veto the
   fixed order when counts contradict it. Serves **precision** (of the future pair tier) and
   coverage (unblocks PU.59's reopen condition, which the held row itself names). Measure:
   `PumpRowAssignmentTests` floor (must hold 0.99), then the cautioned-tier arm of PU.59's
   measurement - the reopen gate is literally "when role assignment lifts the cautioned tier"
   (`docs/TASKS.md:1038`).
2. **A guarded permutation tier in the law.** Today roles never swap (`PumpReadingLaw.swift:17-18`)
   - right for F2, but pump-032's shape (price row read as litres) would be caught, not committed,
   if the law tried the swap **only** when the count signature supports it and the band rejects the
   assigned reading. Serves coverage; risk is the swap-blindness F2 exists for, so the guard must
   be the count signature plus the band, never arithmetic alone. Measure: oracle fragility (must
   stay ≤0.10), annotated/live floors, zero new wrong cells - and name pump-019-at-0° as the L5
   (PU.59's brief already requires it).
3. **Read-then-assign as a second pass**: assign provisionally, and when the law abstains with
   `noTotalWindow`/`noLitersWindow` (7 of 50 abstentions post-PU.54, `REPORT.md:2035-2044`), retry
   the assignment over unassigned/role-less windows before abstaining. Cheap, contained in
   `readPhotoDetailed`'s existing retry shape. Measure: the live histogram's two reason counts.

### 3.3 Tilt and rotation

1. **The size rule is what refuses tilted stills, not the angle.** The 8 tilted stills the app
   refuses fail `minimumWidestRowFraction = 0.18` (`PumpDisplayCapture.swift:88`) because a turned
   display projects narrower (pump-302: widest row 0.10, PU.65). A rotation-aware size rule -
   estimate the row angle from the detector row's aspect or the deskew search, and scale the
   threshold by ~cos(θ) - is model-free and serves **coverage** on the 20 past-12° stills (3
   commit at `.onRefusal` today). Measure: the PU.65 tilted arm (0 → ?) **and** the 116 non-pump
   fixtures (leaks must stay 5). Risk: receipts photographed at an angle could newly pass; the
   detector's stacked-row requirement is the guard that must hold.
2. Whole-photo levelling: measured twice, adds nothing on the app path (54 → 54; rows too small
   after rotation). Settled; do not retry without new evidence.
3. The orientation search (0/90/270, confidence-gated at 0.5) is shipped, honest, and reproduces
   the annotation's orientation (`REPORT.md:2103-2171`). 180 is deliberately not searched - fine
   while the corpus holds no upside-down display; revisit if the shoot list ever produces one.

### 3.4 Glare and low contrast

1. **Frame selection over frame fusion.** PU.19 fused probabilities and pixels across frames:
   +1 cell, 45× time. Selection is different and untried on the app path: from a Live record's
   frames, pick the one whose rows pass geometry with the best pitch/contrast statistics, then
   read once. Serves coverage on the glare fixtures (pump-021: 3/185 windows extracted, pump-022:
   5/310, `REPORT.md:444` - the slicer cannot even count them). Measure: the existing
   `PUMP_FUSION=1` harness, selection arm vs still arm on the 17 heldout records; ship rule = beats
   the still by more than the ±2-cell seed noise at equal precision. Cost: 3-5 reads, still far
   under budget in Release. (Inference: selection should beat fusion where glare *moves* between
   frames, which is decision 2's own premise.)
2. **The washed-column join** PU.42 named for pump-038 (reflection washes the band's top half;
   runs survive only below the midline, `REPORT.md:1086-1088`): a rule that joins a column whose
   ink survives in *part* of the band to its glyph. Serves coverage on one named class; measure =
   the count-agreement ratchet (236/251) plus live.
3. **Capture-side, not read-side**: PU.39's Capture Lab exists to pick the production preset
   (exposure/quality) and has never been run; PU.40's preview guidance ("Tilt", "Move closer")
   already attacks angle and distance at the source. A glare-specific hint (the preview detector
   sees the row but geometry refuses it → "shade the display") is a product decision, not a
   reader one. Serves coverage upstream of every number in this review.

### 3.5 The receipt leak (5 of 116)

1. **First measure what the five commit** - routing is known, consequences are not (§2.1). If any
   of the five produces a committed reading, that is a wrong-provenance `.pumpPhoto` pre-fill
   reaching Confirm, and it outranks any tightening. Read-only; the `pump-read` tool already
   reports `appRoutedAsPump` (PU.65).
2. If they commit: tighten the **slow path only** (the five leaked under the old ≤30-line rule,
   PU.63). Options: raise `classificationMinimumMargin` for Vision-proposed rows, or require a
   detected row to participate in the slow-path verdict. Trade-off is explicit and measured:
   pump-035/-112 live on the slow path (31 and 35 text lines), so tightening risks the +5 cells
   PU.63 bought. Serves precision; measure = leaks over all 116 non-pump fixtures **and** the live
   floor.

### 3.6 The price-less pair (PU.59, held at 1/10)

The row's own reopen condition is role assignment (§3.2) - I agree, and add:
1. Do not reopen on the currency-wide band alone; PU.54 measured that at 0.831 and the six wrong
   stills are named (`REPORT.md:2024-2061`).
2. When it reopens, the split gate must print the cautioned tier's precision separately with the
   stills named (the owner's ruling already says so, `docs/EXTRACTION.md:1033-1038`), and
   `composed` must keep the rules arm's price out - PJ.500 shipped that channel; verify it with a
   test on the *agreeing* pair case too (§2.5's residual).
3. A per-fuel band (decision 11's amendment names it: "a fuel-kind band, if the pipeline ever
   carries one") would let the band do real validation work; the pipeline does not carry fuel kind
   for a pump photo, and inferring it from the price is circular. Park.

---

## 4. Question 4 - drastic improvements

Each with its cost and its falsifier. "Large step" is measured against the only end-to-end number
that matters: live committed cells at precision ≥0.99 (45 today, 54 with the flag; annotated 111
shows the read stage's headroom; gate coverage 0.60 = ~110 cells).

### 4.1 Replace the row detector's output primitive: oriented quads, not upright boxes

**The change.** A row proposal becomes a quad (or box+angle). Three routes, cheapest first:
(a) **Post-hoc quad construction** - keep Create ML, but every detected box is immediately turned
by `PumpRowDeskew` and height-refit to its ink band *before* the verifier and slicer see it (today
this happens only on refusal, and only without refit). This is §3.1.1+2 promoted from retry to
default; the `.always` arm measured churn (46/46, "turning a box moves where its ends fall",
PU.65), so it must be re-measured with the refit and with the verifier's rules re-fitted on the
train split to the *deskewed* framing - that re-fit is the real cost.
(b) **Angle-regression head on the existing detector's features** - a small custom Core ML model
(box + θ per row) trained on the 190 hand quads + owner-verified frames; the labels already are
quads, so no new annotation. Cost: leaving Create ML for PyTorch→coremltools (the classifier's
toolchain already exists), iOS 18 op validation.
(c) **An off-the-shelf oriented detector** (YOLOv8n-OBB class, converted) trained on the same
labels. Cost: bundle size discipline (against the 31 MB already flagged), conversion validation,
and the DOTA-style tooling.

**Why it could be a step, not a round.** The apportionment's -33 is framing; hand boxes as upright
rectangles read 89 at 0.944 while hand *quads* read 111 at 0.991 - the 22-cell and 4.7-point
difference between those two arms **is** the orientation of the box, at identical placement. No
other single variable in the tree has that measured spread.
**Serves:** coverage primarily (45 → toward 89-111), precision secondarily (0.944 → 0.991 is the
upright-rectangle penalty the law currently pays as abstentions).
**Cost:** (a) days; (b)/(c) 1-2 weeks including the verifier re-fit and the label-consistency pass
(§3.1.3), which is a precondition for (b)/(c) because the models cannot beat IoU ~0.78 on labels
that agree with each other at 0.75-0.79.
**Falsifier:** re-run the apportionment with the new locator arm swapped in. If the framing loss
does not fall below ~15 cells, or live does not pass ~65 at zero wrong readings on the 68 heldout,
the primitive was not the problem and the whole family closes - PU.58's rule ("adds cells without a
wrong reading") applied at the stage level.

### 4.2 Replace slicer+classifier with a row-level sequence reader (CTC/attention)

**The change.** A CRNN-class model reads the whole deskewed strip and emits a sequence over
{0-9, '.', ',', blank} - deleting the cell-count class (PU.37's six failure classes: dim glyphs,
pitch harmonics, over-merges, mark over-fires, split over-counts, snap/blank), the dp second look,
the dim-glyph recovery, the widening margin and the whole `PumpGlyphSlicer` option surface (~700
lines). The law keeps its shape: CTC per-position posteriors become the beam's ranked candidates
exactly as `PumpCellReading.ranked` does today; decimal placement becomes a read character with
the conventions as a prior, not a hint.
**Why it could be a step.** The slicer's count agreement is 236/251 on *hand quads* and materially
worse on detector boxes (PU.34: 28 of 117 miscounted); count errors are invisible recall loss at
the verifier and wrong-value risk at the law. Sequence models are the standard answer to
"segmentation is the bottleneck" in text recognition, and the corpus already holds the training
data: ~8.5k windows with strings from the train split (`REPORT.md:421-423`), plus synthetic strips
from the existing renderer.
**Serves:** coverage (the -17 verifier drop is mostly slicer miscounts) and robustness to framing
(a loose box costs a CTC reader far less than a grid snap - this is inference from how CTC aligns,
and it is the hypothesis the spike tests).
**Cost:** the largest build in this list - a training pipeline (exists), row-level labels (exist),
law integration (the nat windows must be recalibrated from scratch, §2.2.2), and a parallel
measurement period. 2-4 weeks.
**Falsifier, staged so it fails cheap:** first train offline and score **strings** on the annotated
tier's strips. If CTC digit accuracy on hand-box strips does not beat the current 0.732 digit-only
(count-correct basis, `REPORT.md:363-368`), or the law over CTC posteriors commits fewer than 111
cells at ≥0.99 on the annotated tier, stop before touching Swift. The PU.32 review estimated
annotated ~85-110 for this idea; the annotated tier has since moved to 111, so the bar is higher
than when it was proposed.

### 4.3 Make the law scale-aware: the digit-count signature as a first-class guard

**The change.** Every candidate carries its cell count and the display's decimal convention; the
law refuses any close whose operand counts are impossible for their roles (a 3-cell EUR price, a
total with fewer cells than its litres, a litres value with 3 decimals), and uses counts to break
the `ambiguous` ties that today abstain (3 field-level `ambiguous` refusals on the live path,
`REPORT.md:1735-1737`).
**Why it could matter more than its size.** It attacks the two blind spots the cloud-model postmortem
named (swap, scale) *inside* the component that is otherwise the system's strength, and it is the
precondition that makes §3.2.2 (guarded permutation) and PU.59 (cautioned pair) safe to open -
together worth the 6 `priceUnvalidated` stills, the 23 `nothingClosed` refusals' ambiguous subset,
and the F2 residue.
**Serves:** precision (kills pump-106-class consistent shrinks) then coverage (unblocks the pair
tier).
**Cost:** days. Pure Swift in the law + the conventions table; the oracle-string harness (763
@0.9987, fragility 0.050 against a 0.10 ceiling, `REPORT.md:2056-2061`) scores it directly.
**Falsifier:** the oracle ratchet must not lose commits and fragility must not rise; pump-106's
fixture must abstain or be caught; if the signature fires on legitimate heads (KZT totals with 0
decimals, RUB one-decimal prices - `PumpReadingTypes.swift:218-231`) on more than a named handful
of corpus fixtures, it is too blunt and dies there.

### 4.4 Replace the display decision with a learned pump/not-pump classifier

**The change.** A ~100 KB Core ML binary on a downscaled frame, trained on 318 pumps + 116
non-pumps (labels exist; the detector's negative set is a subset), replacing both the fast-path
stacked-row rule and the slow path's Vision-line ceiling.
**Serves:** speed (deletes the per-photo Vision text-line pass, §2.5), robustness (removes the last
Vision dependency from the decision - the component whose OS-version drift took the rules parser
from 53 to 13 hits, RV.295), and precision at the door (the 5 leaks become a measured, trainable
quantity instead of an emergent one).
**Cost:** days; the risk is a new failure class (a real display refused by a small classifier),
which PU.63 just paid down (+21 stills classified) - so the gate for adopting it is that it must
classify **every** still the current rule classifies, plus reduce leaks.
**Falsifier:** 116 non-pump fixtures must leak ≤5 → target 0-2; the 68 heldout pumps must not lose
a single classification; pump-035/-112 (the slow-path survivors) must pass. Any regression against
PU.63's measured +21 kills it.

### 4.5 Not drastic, but on the critical path: widen the yardstick

A second frozen heldout draw (~60 stills from batches 6-9, which no shipped model trained on -
round 6 trained on the 2026-09-20 export of 148 stills, PU.33 on 153; decision 9's own rule
permits it) halves the ±13-cell band and makes every number above decidable. Owner's call, zero
code, and it is a prerequisite for believing any of §4.1-§4.4 rather than merely measuring them.

---

## 5. Question 5 - research that helps, down to the low level

Verification key: **[V]** = title/authors/year confirmed via the arXiv API on 2026-09-23;
**[K]** = well-known classic not on arXiv, cited from knowledge, **not verified online today** -
treat the link as the standard one, not a checked fetch.

### 5.1 Line, angle estimation and rectification (for §3.3, §4.1a)

- **Otsu, N. (1979). "A Threshold Selection Method from Gray-Level Histograms." IEEE Trans.
  Systems, Man, and Cybernetics 9(1).** [K] Already the slicer's run threshold
  (`PumpGlyphSlicer+Primitives.swift:93`); cited because the profile-histogram variant used here
  (Otsu over a 1-D column profile, not an image) is a legitimate but non-standard use whose
  failure mode - a bimodal split with no digits - is the `cellCount` drop reason.
- **Duda, R.O., Hart, P.E. (1972). "Use of the Hough Transformation to Detect Lines and Curves in
  Pictures." Communications of the ACM 15(1).** [K] The classical alternative to
  `PumpRowDeskew`'s profile-sharpness search: a Hough pass over the strip's edge pixels gives the
  row angle with a confidence (accumulator mass) the sharpness score lacks - useful for the
  rotation-aware size rule (§3.3.1), where today the angle is known only after a ±30° warp search.
- **Grompone von Gioi, R., Jakubowicz, J., Morel, J.-M., Randall, G. (2010). "LSD: A Fast Line
  Segment Detector with a False Detection Control." IEEE TPAMI 32(4).** and **Akinlar, C., Topal, C.
  (2011). "EDLines: A real-time line segment detector with a false detection control." Pattern
  Recognition Letters 32(13).** [K] Sub-pixel segment extraction with a *statistical* false-alarm
  bound; on a deskewed strip, the digits' horizontal a/d segments are near-perfect line evidence,
  and an LSD-style band fit is the model-free version of PU.58's trim that does not read bezel as
  ink (the acontrario test rejects the bezel's low-contrast gradient). Directly applicable inside
  `PumpRowDeskew.fitsBand`.
- **Bezmaternykh, P., Nikolaev, D. (2019). "A Document Skew Detection Method Using Fast Hough
  Transform." arXiv:1912.02504.** [V] https://arxiv.org/abs/1912.02504 - fast Hough-based angle
  estimation; the cheap prior for the whole-photo angle that PU.65's `levelAngle` currently gets by
  deskewing every row and taking the median.
- **Lin, Y., Pintea, S.L., van Gemert, J.C. (2020). "Deep Hough-Transform Line Priors." ECCV 2020.
  arXiv:2007.09493.** [V] https://arxiv.org/abs/2007.09493 - learned priors over the Hough
  parameter space; relevant only if angle estimation on glare-washed rows (pump-038's class) proves
  too weak classically.
- **Pautrat, R., Barath, D., Larsson, V., Oswald, M.R., Pollefeys, M. (2023). "DeepLSD: Line
  Segment Detection and Refinement with Deep Image Gradients." CVPR 2023. arXiv:2212.07766.** [V]
  https://arxiv.org/abs/2212.07766 - the refinement half is the interesting part: classical
  segments refined by a learned gradient field. The analogue here is detector boxes refined by a
  learned row-ink field - a principled version of the deleted `PumpBoxRefiner`, which failed
  because it refined on *classical* ink the bezel poisons.
- **Jaderberg, M., Simonyan, K., Zisserman, A., Kavukcuoglu, K. (2015). "Spatial Transformer
  Networks." NeurIPS 2015. arXiv:1506.02025.** [V] https://arxiv.org/abs/1506.02025 - the
  learned-rectification option: an STN in front of the row reader predicts the affine turn per row
  and warps differentiably, replacing the search in `PumpRowDeskew` with a forward pass. Cost: a
  training round with quads as supervision (they exist); benefit: constant-time rectification
  instead of a ±30° × 0.2° sweep (the sweep is the deskew retry's main latency).

### 5.2 Row/text detection with oriented output (for §4.1b/c)

- **Liao, M., Shi, B., Bai, X., Wang, X., Liu, W. (2018). "TextBoxes: A Fast Text Detector with a
  Single Deep Neural Network." AAAI 2018. arXiv:1611.06779.** [V]
  https://arxiv.org/abs/1611.06779 - quadrilateral text boxes from a single-shot detector: the
  exact output primitive §4.1 needs, at digit-row scale.
- **Ma, J., Shao, W., Ye, H., Wang, L., Wang, H., Zheng, Y., Xue, X. (2018). "Arbitrary-Oriented
  Scene Text Detection via Rotation Proposals." IEEE TPAMI 40(2). arXiv:1703.01086.** [V]
  https://arxiv.org/abs/1703.01086 - rotation-proposal heads; the two-headed (box + angle) design
  is route (b) of §4.1.
- **Xie, X., Cheng, G., Wang, J., Yao, X., Han, J. (2021). "Oriented R-CNN for Object Detection."
  ICCV 2021. arXiv:2108.05699.** [V] https://arxiv.org/abs/2108.05699, and **Xia, G.-S. et al.
  (2018). "DOTA: A Large-scale Dataset for Object Detection in Aerial Images." CVPR 2018.
  arXiv:1711.10398.** [V] https://arxiv.org/abs/1711.10398 - the standard oriented-box machinery
  and its evaluation conventions (IoU on rotated boxes); if §4.1b/c runs, its gate should be
  rotated-box IoU, which will read *higher* than today's upright median 0.797 on the same labels -
  the gate arithmetic of decision 10 must be restated in those terms before the first candidate is
  judged.
- **Deng, D., Liu, H., Li, X., Cai, D. (2018). "PixelLink: Detecting Scene Text via Instance
  Segmentation." CVPR 2018. arXiv:1801.01315.** [V] https://arxiv.org/abs/1801.01315 -
  segmentation-then-min-area-rect: the detector-free route to quads (per-pixel row mask →
  `minAreaRect`-equivalent computed with Accelerate). Attractive here because the rows are huge
  relative to the frame; the false-positive control is the existing keypad/stacking rules.
- **Zhou, X. et al. (2017). "EAST: An Efficient and Accurate Scene Text Detector." CVPR 2017.
  arXiv:1704.03155.** [V]; **Liao, M. et al. (2020). "Real-time Scene Text Detection with
  Differentiable Binarization." AAAI 2020. arXiv:1911.08947.** [V]; **Baek, Y. et al. (2019).
  "Character Region Awareness for Text Detection." CVPR 2019. arXiv:1904.01941.** [V] -
  https://arxiv.org/abs/1704.03155, /1911.08947, /1904.01941. Relevant as the *negative* control:
  these detect text regions generally; CRAFT's character-level heatmaps in particular would give
  per-glyph centres, dissolving the slicer's pitch problem - but they are trained on natural text,
  and the corpus's own measurement (Vision's text boxes: locator median IoU 0.008 before the
  detector, PU.4) is the local evidence that generic text detection does not transfer to seven-
  segment rows. Cite them to bound the option, not to recommend it.

### 5.3 Segment-display reading (for §4.2)

- **Shi, B., Bai, X., Yao, C. (2017). "An End-to-End Trainable Neural Network for Image-based
  Sequence Recognition and Its Application to Scene Text Recognition." IEEE TPAMI 39(11).
  arXiv:1507.05717.** [V] https://arxiv.org/abs/1507.05717 - CRNN: the reference architecture for
  §4.2. **Graves, A., Fernández, S., Gomez, F., Schmidhuber, J. (2006). "Connectionist Temporal
  Classification." ICML 2006.** [K] not on arXiv - the alignment-free training objective that lets
  the 8.5k window strings supervise a row reader with no per-cell labels.
- **Baek, J., Kim, G., Lee, J., Park, S., Han, D., Yun, S., Oh, S.J., Lee, H. (2019). "What Is
  Wrong With Scene Text Recognition Model Comparisons? Dataset and Model Analysis." ICCV 2019.
  arXiv:1904.01906.** [V] https://arxiv.org/abs/1904.01906 - the CTC-vs-attention evidence base;
  its irregular-text findings (CTC weak on heavy perspective without rectification) map onto the
  tilted-still class and argue for pairing §4.2 with §4.1/STN, not alone.
- **Moreira, L.P. (2022). "Automated Medical Device Display Reading Using Deep Learning Object
  Detection." arXiv:2210.01325.** [V] https://arxiv.org/abs/2210.01325 - the closest published
  analogue to this problem (seven-segment device displays, detection + per-digit reading); useful
  mainly as confirmation that the two-stage detect-then-read shape is what the applied literature
  converges on, and that end-to-end display reading remains unsolved generically.
- **Salomon, G., Laroca, R., Menotti, D. (2020). "Deep Learning for Image-based Automatic Dial
  Meter Reading: Dataset and Baselines." arXiv:2005.03106.** [V] https://arxiv.org/abs/2005.03106
  - adjacent domain (rotating-dial utility meters) whose baseline design - detect the digit row,
  classify per position, sequence-model the carry - parallels the law's decimal-recovery problem.
- **Li, M., Lv, T., Chen, Y., Cui, L., Wei, F. (2023). "TrOCR: Transformer-based Optical Character
  Recognition with Pre-trained Models." AAAI 2023. arXiv:2109.10282.** [V]
  https://arxiv.org/abs/2109.10282 - listed for completeness and **against**: a pretrained
  transformer OCR is the "cloud model" failure class in on-device clothing (scale/swap blindness,
  latency, bundle size); the corpus's own P4.12 measurement is the local falsifier.
- Honest note: the *seven-segment-specific* peer-reviewed literature is thin (the arXiv search on
  2026-09-23 returned Moreira's paper as essentially the only direct hit); most published work on
  segment displays is template matching (the classical OpenCV/Tesseract treatment) which the
  corpus's pump-004 fixture (Vision's `4`-for-`9` at confidence 1.00) and the washed-out class
  already refute. The segment-sigmoid + valid-pattern decode design in this repo is, as far as the
  searchable literature shows, ahead of what is published for this display class - labelled as
  inference from a negative search, not a proof.

### 5.4 Constrained decoding (for §4.3 and the existing law)

- **Hokamp, C., Liu, Q. (2017). "Lexically Constrained Decoding for Sequence Generation Using Grid
  Beam Search." ACL 2017. arXiv:1704.07138.** [V] https://arxiv.org/abs/1704.07138 - the formal
  frame for what `PumpReadingLaw.candidates` does informally: the "lexicon" here is the set of
  (digit-string, decimal-placement) pairs the currency conventions allow, and grid beam search is
  the drop-in if §4.2's CTC reader needs the same constraint enforced *during* decoding rather
  than by post-filtering the beam (today: beam 3 / 12 strings per field then filter,
  `PumpReadingLaw.swift:22-24,353-387`).

### 5.5 Calibration and abstention (for the 0.99 floor, the nat windows, PU.59)

- **Guo, C., Pleiss, G., Sun, Y., Weinberger, K.Q. (2017). "On Calibration of Modern Neural
  Networks." ICML 2017. arXiv:1706.04599.** [V] https://arxiv.org/abs/1706.04599 - temperature
  scaling per classifier release would make the nat windows (6.0/3.0/4.0) *transferable across
  retrains*: fit T on the train split, then the law's constants stop being round-6-specific
  (§2.2.2's unowned seam). This is the cheapest fix to the "every retrain lowers live" pattern
  that does not require decoupling anything else.
- **Geifman, Y., El-Yaniv, R. (2017). "Selective Classification for Deep Neural Networks." NeurIPS
  2017. arXiv:1705.08500.** [V]; **Geifman, Y., El-Yaniv, R. (2019). "SelectiveNet: A Deep Neural
  Network with an Integrated Reject Option." ICML 2019. arXiv:1901.09192.** [V]
  https://arxiv.org/abs/1705.08500, /1901.09192 - the risk-coverage framework the PU.20 frontier
  table already computes empirically (0.99 holds to 25% coverage, 0.95 to 54%, `REPORT.md:
  398-403`); SelectiveNet's trained reject head is the per-cell version of an abstention the law
  currently can only express per-triple (PU.51: "no per-glyph abstain - the classifier always ranks
  ten digits", `REPORT.md:1718-1720`).
- **Angelopoulos, A.N., Bates, S. (2021). "A Gentle Introduction to Conformal Prediction and
  Distribution-Free Uncertainty Quantification." arXiv:2107.07511.** [V]
  https://arxiv.org/abs/2107.07511 - the statistically honest version of the 0.99 floor: a
  conformal risk control on the train/val split can certify "wrong-commit rate ≤ 1% with
  probability 1-α" *at the current sample size*, which the point estimate cannot (§2.1). Also the
  right tool for the cautioned tier PU.59 holds: certify the cautioned commits' error rate
  separately rather than trusting a 10-cell measurement either way.
- **Müller, R., Kornblith, S., Hinton, G. (2019). "When Does Label Smoothing Help?" NeurIPS 2019.
  arXiv:1906.02629.** [V] https://arxiv.org/abs/1906.02629 - the shipped recipe already uses LS
  0.05; this is the reference for *why* it helped the frontier rank (it regularises the logit gaps
  the nat windows read) and the warning that it erases relative-margin information - relevant if
  temperature scaling (§ above) is ever fitted on top.
- **Lin, T.-Y. et al. (2017). "Focal Loss for Dense Object Detection." ICCV 2017.
  arXiv:1708.02002.** [V] https://arxiv.org/abs/1708.02002 - the dp bit's fix candidate: dp is
  ~20.6% of cells and its AUC on real cells is 0.52-0.55 (`REPORT.md:295,334`); focal loss or a
  pos_weight targets exactly this imbalance inside the existing unweighted BCE (`train.py:94,185`).

### 5.6 Speed and native packaging (for "make it faster")

- **Howard, A. et al. (2019). "Searching for MobileNetV3." ICCV 2019. arXiv:1905.02244.** [V]
  https://arxiv.org/abs/1905.02244, and **Jacob, B. et al. (2018). "Quantization and Training of
  Neural Networks for Efficient Integer-Arithmetic-Only Inference." CVPR 2018.
  arXiv:1712.05877.** [V] https://arxiv.org/abs/1712.05877 - the reference path for replacing the
  31 MB Create ML detector (flagged "owner's call before ship" since PU.33; its 8-bit quantiser
  trips on the anchor constants, `REPORT.md:507-508`) with a quantised MobileNetV3-class backbone
  at ~2-6 MB, ANE-resident. Precondition: the PU.39 Capture Lab session on an iPhone 12 that would
  first prove the current detector is slow there - it may not be.
- **Apple Accelerate/vImage** (`vImageAffineWarp_ARGB8888`, `vImageScale_ARGB8888`) - already used
  once in the tree (`PumpRowDeskew.swift:317`); the hand-rolled bilinear loops (§2.6.3) are the
  remaining gap. [K] Apple documentation, not a paper.
- **Core ML batch prediction** (`MLModel.predictions(from: [MLFeatureProvider])`) - one call for
  the five TTA crops per cell, or all cells of a row (§2.6.2). [K] Apple documentation.

---

## 6. Contradictions and rot found while reading (reported, not fixed)

1. **PU.65's commit message vs the shipped default.** `d1ea3f44` says "the row-turn retry `classify`
   already has lifts the app path 45 → 54", but the retry is gated on `reader.deskew == .onRefusal`
   (`PumpDisplayCapture.swift:326`) and `makeReader` constructs with the default `.off`
   (`PumpReader.swift:33-39`; `CapturePipeline.swift:28-30` passes no mode). The app today is 45,
   not 54; the row's "Left: the owner's decision" is consistent, the commit message reads as if it
   shipped. No file changed; flagging the wording.
2. **The brief's annotated numbers (111/110, 33/68) vs the test's floor comments (112/111, 34/68,
   `PumpReaderPipelineTests.swift:27-28`) vs PU.63's gate constants (44/44/182 on 67 stills).**
   All three are "current" against different corpus commits - the basis drift of §2.4.1, live, in
   three files at once. The row that owns reconciliation is arguably PU.61's composite half; none
   of the three names the others.
3. **`PU.49` remains two rows** (the cut hanging-comma row, `TASKS-DONE.md:704`, and the open
   tilted-display row, `TASKS.md:1029`) - known since the fable review (§13.6), still unfixed.
4. **The swiftlint crash on gitignored `build/` DerivedData** (`REPORT.md:1552-1558`, "no row owns
   it") predates this review and is not mine to fix.
5. Fable review items I could not confirm as landed: PU.56 (per-reason ledger as an instrument -
   PU.51 shipped reasons, the *ledger/differ* half is still absent), PU.41/PU.48/PU.55/PU.5/PU.34
   row-status hygiene (several still `[ ]`/`[~]` though measured and closed in the report).

---

## 7. Goal accounting (precision / coverage / speed), condensed

| Recommendation | Goal served | Trade |
|---|---|---|
| Ship deskew `.onRefusal` (§3.1.1) | coverage +9 | latency only on photos that committed nothing |
| Fitsband-on-turn arm (§3.1.2) | coverage | must pass the zero-wrong-readings rule |
| Label consistency + oriented detector (§3.1.3-4, §4.1) | coverage, then precision | 1-2 weeks; verifier re-fit; gate restated in rotated IoU |
| Count-signature guards (§3.2.1, §4.3) | precision, then coverage (unblocks PU.59) | none measured; oracle fragility is the ratchet |
| Guarded permutation tier (§3.2.2) | coverage | F2 risk; needs the signature first |
| Rotation-aware size rule (§3.3.1) | coverage (tilted 20) | leak surface grows; measure on all 116 negatives |
| Frame selection on Live records (§3.4.1) | coverage (glare) | 3-5× read time on the refusal path only |
| Leak consequences + slow-path tightening (§3.5) | precision | risks pump-035/-112's +5 cells |
| CTC row reader (§4.2) | coverage, framing robustness | biggest build; recalibrates every nat constant |
| Learned display decision (§4.4) | speed, precision-at-door, runtime-drift immunity | new refusal class; must not lose PU.63's +21 |
| Lazy textLines, batched TTA, vImage (§2.6) | speed | none; pure wins, unmeasured on device |
| Second frozen heldout draw (§4.5) | measurement power for all of the above | owner's call; doubles scoring time |
| Temperature scaling + conformal floor (§5.5) | precision (statistical), retrain-transferability | training-pipeline work, no user-visible change |

---

## If I could do exactly three things

1. **Flip deskew to `.onRefusal` in the app** - it is built, measured at 54/54 against 45/45 with
   no new leaks (PU.65), and it is the only coverage in the tree whose experiment has already been
   run.
2. **Attack the upright-rectangle primitive, in the measured order: fitsband-on-turn arm first,
   label consistency second, an oriented-quad detector third, judged by a re-run of the
   apportionment and the zero-wrong-readings rule** - because -33 framing cells is the largest
   priced loss and every upright-box fix has now been measured and refused.
3. **Widen and harden the instrument before the next model round: a second frozen heldout draw,
   Wilson/conformal intervals beside every point estimate, a `PUMP_DETECTOR=` override, a device
   Capture Lab session, and a measurement of what the five leaked receipts actually commit** -
   because every number this review ranks by sits on a 183-cell yardstick with a ±13-cell band and
   no phone has ever timed any of it.

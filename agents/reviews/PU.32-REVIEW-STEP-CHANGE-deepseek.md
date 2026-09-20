# PU.32 review: what would DRASTICALLY raise the pump reader's quality

Read-only review. Every claim points at a file, a number or a fixture. The one-line
answer up front, then each of the seven questions, then a ranked proposal table and
the list of what I could not verify.

## The one-line answer

The classifier is not the bottleneck and more corpus is not the bottleneck. **The
live path commits 11 cells where the annotated path commits 66** (`PumpReaderPipelineTests`
`liveCommittedFloor = 11` vs `committedFloor = 66`, `ios/Tests/TankbookCoreTests/PumpReaderPipelineTests.swift:26-36`),
a 6x gap owned by the **locator + verifier**, and the verifier's margin threshold is
fitted to round 6's classifier so every retrain since has slid the live number *down*
(11 -> 4 -> 2, `ml/pump-reader/REPORT.md` rounds 8-9). The one thing that moves a
number on the heldout split by a step is **a learned locator/verifier on the box
labels the corpus already has** (217 stills + 2 766 tracked frames), not another
retrain and not 200 more stills. Even that only closes the gap to the annotated
ceiling, which is itself **66/175 = 37.7 % coverage at 0.970 precision** - below the
0.60 coverage floor the gate demands. Reaching the gate is a classifier+law ceiling
problem, and it is not reachable with this pipeline at its current per-cell digit
accuracy (~0.73 on real cells).

---

## 1. Architecture: is the pipeline the right one, or is the ceiling structural?

The pipeline is locate -> slice (8 segments/cell) -> classify -> arithmetic law
(`PumpReader.readPhoto`, `ios/Sources/TankbookCore/Extraction/PumpReader/PumpReader.swift:84-98`).
The funnel that matters (`PumpLivePathDiagnosticTests`, opt-in diagnostic) over 31
owner stills, from `docs/TASKS.md` PU.24:

| stage | count |
|---|---|
| locator puts a candidate on a true row | 29 / 31 |
| verifier keeps a true row | 25 / 31 |
| two transaction rows verified | 17 / 31 |
| row assignment right | 15 / 31 |
| live path commits | 11 cells, 3 / 64 photos |

Two independent facts pin where the ceiling is:

1. **The ceiling is not the classifier on perfect localisation.** The annotated
   path (perfect quads from `windows.json`) commits 66 at 0.970, 18/64 photos
   (`REPORT.md` round 8). The live path commits 11. The gap is 55 cells, and it is
   lost in the locator/verifier/assignment column above, not in the classifier.
2. **The ceiling is not the law either.** On oracle strings (perfect digits),
   `PumpReadingLaw` commits 294/320 at 0.996 (`PumpReadingLawTests`
   `committedFloor = 294`, `precisionFloor = 0.996`). So the law CAN reach 0.99+
   precision at 92 % coverage *given correct digits*.

What sits between those two facts is the classifier's per-cell digit accuracy on
real cells, which is ~0.73 on count-correct windows (`REPORT.md` round 4: digit
only 0.732/0.753). That is what drags the real-pixel law down from 294 to 66
committed, and it is the number the whole question reduces to.

**Verdict: the pipeline shape is right, and its ceiling is not structural.** The
segment-classifier + law design is exactly what hard rule 13 needs (per-cell
posteriors, abstain, digit repair composes over the posterior ordering,
`docs/EXTRACTION.md` "The pump reader" items 3-4). The ceiling is set by per-cell
digit accuracy, which is a **data** problem, not an architecture problem. Compare
the three options:

**(a) Single detector+recognizer (small CRNN/CTC over the whole row, no slicer).**
- What it needs from the corpus: row-level text labels - which `windows.json`
  already has (the `text` string per window). No per-cell boxes needed; CTC
  aligns the sequence. The train export already holds ~8 550 warped windows with
  their strings (`PumpTrainSliceExportTests` -> `realglyphs.py` manifest).
- On-device cost (iPhone 12, iOS 18, Core ML): a small 1D-CNN/BiLSTM+CTC is
  1-2 MB and runs in single-digit ms. Feasible. The renderer already draws full
  rows (`render_row_of_labels`, `ml/pump-reader/src/pump_reader/row.py`), so
  synthetic row data exists.
- Plausible held-out reach: it removes the two stages that lose most on real
  pixels - the slicer (12 % of held-out windows miscount, 25 % on the train
  export) and the dp bit (which keeps per-window near zero). But it does NOT
  change the per-cell digit accuracy ceiling, because it trains on the same
  synthetic+real cells. I estimate it lifts the *annotated* path from 66 to
  roughly 80-90 committed at the same 0.97 precision, and the live path only as
  far as the locator lets it. It is the right *next* architecture but not a step
  change on its own.
- Rejecting reason for "do it now": it abandons the per-segment posterior that
  `DigitRepair` and the law's ambiguity window are built on, and it needs the
  same real-data fix (question 4) to actually pay.

**(b) Display-level detector (YOLO-nano class) feeding the existing cell classifier.**
- What it needs: window/box labels. **The corpus already has them** - the
  `windows.json` quads for 217 stills, carried into 2 766 tracked frames by
  `pump_reader.track` (`ml/pump-reader/src/pump_reader/track.py`), plus the four
  running-display videos' 4 010 frames (196 labelled). This is the only proposal
  whose training data exists today without new capture or new annotation.
- On-device cost: a YOLO-nano / small SSD is ~1-2 MB, Core ML, ms-range on iPhone
  12. Feasible.
- Plausible reach: fixes the 29/31 -> 31/31 candidate hit and, more importantly,
  gives the verifier *tight* boxes so its aspect/height/edge filters stop dropping
  true rows, and ranks the display rows first so `maximumCandidates = 48`
  (`PumpReader.swift:79`) stops mattering. This closes most of the 6x live->annotated
  gap: live committed plausibly 11 -> 40-50, photos every field right 3 -> 12-15/64.

**(c) Keep the pipeline, fix the weakest stage.**
The funnel's biggest single drop is verifier "two transaction rows verified"
25 -> 17, and `REPORT.md` round 9 states it outright: *"the live number is a
verifier number, not a classifier number"*. The weakest stage to fix first is the
**verifier**, specifically its `minimumMeanMargin = 1.0` threshold
(`PumpReader.swift:68`) which was fitted to round 6 and is why rounds 8/9 slid
11 -> 4 -> 2. This is near-free (see question 3).

**Stage to replace first: the verifier** - because the funnel says locator+verifier
owns the 6x gap, and because the round-8/9 slide proves the live number is currently
a *verifier* artefact, not a classifier one. Replace it with (b)'s detector confidence
+ a count sanity check, decoupled from the classifier's margin distribution.

## 2. The slicer: hand-built projection, or learned, or CTC?

Facts: 210/238 held-out windows count-agree (floor 0.85, `docs/TASKS.md` PU.24);
25 % of train-export windows miscount; and on six glare fixtures the slicer gives
almost nothing (`pump-021` 3/185, `pump-022` 5/310 windows - `REPORT.md` round 6).
The slicer is now a long, hard-won classical device (`PumpGlyphSlicer.swift`, 527
lines: LCN, polarity, Otsu, autocorrelation pitch with harmonic guard, pitch-to-body
check, split-merge, short-count retry).

**Is a hand-built projection slicer the right tool?** The pitch-snap premise is
sound - seven-segment glyphs sit on a physical fixed pitch - and it has been pushed
from 40 % (PU.4) to 88 % (PU.24) count agreement. The remaining 12 % is dominated
by glare/washed-out displays where *no threshold* recovers a pitch, and by heads
where the comma sits in its own narrow cell (Gilbarco). Classical tuning is at
diminishing returns: the losses are optical, not algorithmic.

What the corpus gives you for a learned segmenter today: **quads + text, no
per-cell boxes**. The 25-28k real cells (`realglyphs.py`) carry the *slicer's own*
boxes, only from count-agreeing windows - circular supervision, but 88 % of it is
right on heldout. A per-column ink/gap classifier would be trained on those
slicer-derived cells; it would smooth over the glare cases but inherits the same
circularity and cannot beat the count-agreement number its labels came from.

**The CTC path that needs no slicer is the better fit for what the corpus has.**
The `text` string per window is a row label (digit sequence + separator). The
renderer draws full rows, and the train export has ~8 550 warped rows with strings.
This removes the slicer's 12 % miscount entirely, removes the dp bit (a comma/dot
becomes a sequence token instead of a corner pixel), and needs no per-cell boxes.
Cost: a new ~1-2 MB model and a rewrite of the read stage; the law and row
assignment stay.

**Recommendation:** do not sink more effort into the hand slicer. Choose between
the CTC row recognizer (bigger change, removes the stage) and a learned
per-column classifier (smaller change, keeps the architecture but is
label-circular). For a *step* change, CTC wins because it deletes the stage that
both miscounts and drops whole windows the law never sees.

## 3. The locator / verifier: the 6x gap, and the box labels already in hand

Today: `PumpVisionProposer` (Vision line boxes + rectangle-detector character
boxes, grouped and merged) plus the classical projection, ranked by
boxCount x height (`PumpPanelLocator.locate`, `PumpPanelLocator.swift:24-43`).
Median IoU 0.008 -> 0.62 (PU.24). It misses 2/31 photos entirely and ranks true
rows low enough that `maximumCandidates` was raised to 48 (`PumpReader.swift:79`).

The verifier (`PumpReader.verify`, `PumpReader.swift:122-138`) drops true rows at
mean margins 0.7-1.1 (its threshold is 1.0) and by count (< 3 cells) and by
aspect. The round-8/9 slide (11 -> 4 -> 2) is *entirely* this threshold moving
against a new classifier's margin distribution.

**The locator I would build:** a small detector (YOLO-nano / SSD, 1-2 MB) trained
on the 217 stills' window quads, augmented by the 2 766 tracked frames whose quads
`track.py` already maps through ORB homographies. Train on stills, throw in
tracked-frame boxes as jitter/augmentation. Two outputs are enough: a display-level
box and its three row boxes (total/liters/price), or just per-row boxes. Row
assignment (`PumpRowAssignment`) then runs unchanged on the detector's boxes.

**What recall/precision it needs to make live match annotated:** the annotated
path commits 66. To close the gap the detector must (a) propose a true row on
31/31 (not 29/31), (b) yield IoU >= ~0.7 so the strip the slicer sees is the strip
the classifier was trained on, and (c) let the verifier keep both transaction rows
on ~80 % of photos (today 17/31 = 55 %). A detector's own confidence must *replace*
the classifier-derived mean-margin as the keep signal, with a count sanity check
(>= 3 cells, <= `PumpReadingLaw.maxCells`) retained. That is the key change:
**the verifier must stop using the classifier's margin as a row filter**, because
that couples two things that drift independently (proven by rounds 8/9).

## 4. Training data: the real share is not too small - it is wrongly sampled

The real set is 25-30k cells from the train split's tracked frames, mixed at 30 %
of each batch with brightness/contrast/polarity/shift jitter
(`ml/pump-reader/src/pump_reader/train.py` `RealGlyphs`, `--real-frac 0.3`).

Three defects, all in the sampling, none in the volume:

1. **Per-frame near-duplicates dominate.** The cells come from tracked Live frames
   (`realglyphs.py` -> `track.py`); one clean still contributes hundreds of frames
   whose cells differ only photometrically. The 25k cells are drawn from ~5 677
   windows over ~148 stills + 1 906 frames, so a handful of well-tracking stills
   (clean, straight-on, feature-rich Wayne/Gilbarco EUR/RU) dominate, while the
   hard fixtures contribute almost nothing (`pump-021` 3 windows, `pump-022` 5).
2. **Under-represented heads.** The synthetic renderer has exactly five profiles -
   `gilbarco, wayne, dresser, scheidt, tokheim`
   (`ml/pump-reader/src/pump_reader/profiles.py:136`). No Tatsuno, no Wayne Pignone,
   no Adast, and no Gilbarco Veeder-Root *keypad* head. VFD prior is 5 %
   (`dataset.py:43`). The corpus's ~35 GVR-keypad heads (PU.30) and the Tatsuno
   amber panel have no synthetic profile at all, and Scheidt VFD (the faintest,
   most different palette, `pump-010`, `pump-062`) has only ~10 stills.
3. **The real cells train on the slicer's *clean* output only.** `realglyphs.py:87-89`
   skips any window the slicer miscounts, so the model never sees the hardest
   real cells - exactly the ones the classifier must get right for coverage.

What changes, ranked by effect/cost:
- **Per-fixture (per-still) balancing of the real sampler** - near-free, one loop
  change in `RealGlyphs.batch` to sample uniformly over stills rather than frames.
  Directly attacks defect 1.
- **Hard-example mining on the *train* split's verifier misses** (heldout is frozen
  by decision 9, so mine train only) - medium cost, targets the faint Wayne LCD and
  washed-out displays.
- **A real-only fine-tune stage** (short, low LR, synthetic kept in the loop) -
  low cost, but risks overfitting to the train heads; do it last, measure on heldout.
- **Add profiles for Tatsuno / GVR-keypad / Pignone and raise the VFD prior** -
  medium cost, fixes a real palette blind spot the synthetic set has.

**How many more stills for the next doubling, and which kinds:** the next doubling
must add *diversity*, not count. Concretely: Scheidt & Bachmann VFD (+20), Tokheim
(+15), night/low-contrast (+15), each with the Live record kept, is ~50 stills and
would roughly double the *effective* real-cell diversity. But the honest prediction:
rounds 6/8/9 all landed within 7 committed cells on 175, so even the best-chosen
50 stills move the annotated path from 66 to maybe 70-75 at 0.97 - a few points,
**not a step**. The step is in question 3, not here.

## 5. Measurement: 175 cells and a +-7 swing is not a number

The heldout is 64 stills / 175 asserted numeric cells. Three recipes (rounds 6/8/9)
land within 7 cells of each other, and **every round is seed 0** - there is zero
seed variance measured. `REPORT.md` round 9 says it: *"a retrain needs 3 seeds
before a number means anything"*.

Minimum evaluation to insist on before believing a number:
1. **3 seeds per recipe**, report mean and range of committed and precision. A
   single-seed +-7 on 175 is within run-to-run noise; you are currently shipping
   noise as a floor (`committedFloor = 66`, `precisionFloor = 0.96`).
2. **Bootstrap CI over the 64 photos** (resample photos, report 95 % CI on
   committed and on "photos every field right"). On 175 cells the CI on a +-7 move
   is wide; treat anything under ~10-15 cells as indistinguishable.
3. **Per-head and per-currency breakdown.** The aggregate 66/175 hides that the
   commits are concentrated on clean Wayne/Gilbarco EUR/RU photos. Report
   committed/precision per head type (Wayne, Gilbarco, GVR-keypad, Tokheim,
   Scheidt) and per currency - the per-head table already exists in `score.py`
   (`per_make`, `ml/pump-reader/src/pump_reader/score.py:422-425`) but is never
   surfaced in the law-facing numbers.
4. **The split shape is right; do not re-stratify.** The random 70/30 (decision 9)
   is the correct shape for generalization; a per-head stratification would shatter
   the already-tiny per-head cells and break the frozen-split decision. Add per-head
   *reporting*, not per-head *splitting*.

Two measurement flaws worth naming in the doc:
- **The live precision floor (0.99) is currently unmeasurable** - it is a precision
  over 11 committed cells, where one wrong cell is a 9-point drop. It is a formality
  until live commits are ~100+.
- **The gate's coverage floor (0.60) is written against `measuredNumericTotal = 611`
  (the rules-parser corpus), not against the reader's heldout 175.** The reader's
  honest coverage denominator is 175; comparing the reader's 66/175 = 37.7 % to a
  floor scaled to 611 muddies what "0.60" means for this arm.

## 6. The law and the ship gate: reachable at all?

Gate: precision >= 0.99 at coverage >= 0.60 (`PumpPhotoGate`,
`ios/Sources/TankbookCore/Config/PumpPhotoGate.swift:71-81`).

What the arithmetic can and cannot disambiguate (`PumpReadingLawTests`, and
`docs/EXTRACTION.md` "the four-price display" / pump-003): the cross-check is
**blind to a swap** (`a x b == b x a`) and **blind to scale** (`liters x price ==
total` is scale-invariant; pump-003 has 12 solutions before bands, and a factor-of-ten
volume survives every automatic filter). The law guards these with priors - digit
counts, price bands, min/max liters, idle-pump zero - but they are priors, not
proofs, and `pump-106` (the tenfold shrink that multiplies out) is the committed
counterexample: 5.1 x 70.31 = 358.58, every check green.

Two ceilings, both below the gate:
- **Annotated path:** 66 committed at **0.970** precision, 37.7 % coverage. Both
  precision and coverage are below the gate's 0.99 / 0.60, *even with perfect
  localisation*. The 0.970 < 0.99 is not a rounding error - 2 of 66 committed
  cells are wrong, one of them the scale-invariant tenfold shrink.
- **Law on oracle digits:** 294/320 at 0.996 - so with *perfect* digits the law
  clears 0.99 precision at 92 % coverage. The entire gap is classifier digit
  accuracy (~0.73 on real cells).

**Verdict: the gate is not reachable with this pipeline at its current classifier,
and the annotated ceiling (37.7 % coverage, 0.970 precision) is itself below it.**
Reaching 0.60 coverage at 0.99 precision requires per-cell digit accuracy high
enough that the law commits 60 % with a unique closing triple - which the CTC row
recognizer (question 2) *plus* the real-data fix (question 4) might approach, but
no single engineering change gets there.

**What the app should do with it:** decision 7 already has the honest answer, and
it is the right one (`docs/EXTRACTION.md` decisions 7, and `PumpPhotoCapture`):
while the gate is off, the reader runs and its committed fields arrive as an
**alpha pre-fill with the notice** ("pump displays are read in alpha - check every
field"), typing stays the peer door, every field is editable (hard rules 13 and 15).
The gate governs only *framing* (alpha notice vs ordinary pre-fill), never existence.
The concrete recommendation is to **re-scope the gate, not the app**: a
precision-first gate of >= 0.99 at a coverage floor of ~0.35 (what the annotated
path can reach once the locator is fixed), with the 0.60 floor parked as a
documented later-version target that the CTC+data work would have to earn. Shipping
at 0.99/0.60 today is not on the table; shipping the reader as an honest alpha
head-start already is (and is what the code does).

## 7. The one thing

If the owner does exactly one thing next week: **build the learned locator/verifier
(a YOLO-nano-class detector on the 217 stills' window quads, plus the 2 766
tracked-frame boxes), and decouple the verifier's keep-signal from the classifier's
margin.** It is the only action whose training data already exists in the checkout
(no new capture, no new annotation), and it attacks the 6x gap the funnel measures.

Expected number it moves: live path **11 committed -> roughly 40-50, and 3/64 ->
12-15/64 photos every field right**, by closing the gap to the annotated ceiling
(66 / 18-64). It does *not* move the annotated ceiling, which is a classifier+data
problem for a later week.

If the owner insists on data instead of engineering: capture **Scheidt & Bachmann
VFD and Tokheim stills with their Live records kept** (the decision-5 shoot list is
still the right list), because those are the heads the synthetic renderer has no or
a wrong profile for and the tracked real cells under-sample. That moves the
annotated path a few cells (66 -> ~70-75 at 0.97), within the +-7 noise - a percent,
not a step.

## Ranked proposals (expected effect on the live path / cost)

| # | Proposal | Expected effect on live path | Cost |
|---|---|---|---|
| 1 | Learned locator (YOLO-nano on existing boxes) + verifier keep-signal decoupled from classifier margin | 11 -> ~40-50 committed, 3 -> 12-15/64 photos; stops the 11->4->2 retrain slide | ~1 week; box labels already in `windows.json` + tracked frames |
| 2 | Fix the verifier alone (re-fit margin per retrain, or accept on detector confidence + count; verify rows not cells) | returns live to 11 and prevents future regressions; prerequisite for #1 | hours |
| 3 | Per-fixture balancing of the real-glyph sampler | classifier +2-4 pts on hard heads; annotated 66 -> ~70 | hours |
| 4 | CTC row recognizer (drops slicer + dp bit) | annotated 66 -> ~80-90 at 0.97; removes the 12 % slicer loss | ~1-2 weeks, new model |
| 5 | Add Scheidt/Tokheim/night stills + profiles for Tatsuno/GVR-keypad/Pignone, raise VFD prior | annotated 66 -> ~70-75; live only via #1 | ~50 stills + profile work |
| 6 | 3-seed + bootstrap + per-head measurement | makes any of the above believable; moves nothing | days |

## What I could not verify

- **Head-type counts** (Wayne/Dresser ~90, Gilbarco ~45, GVR-keypad ~35, Tokheim ~20).
  There is no per-fixture head-type column in the checkout; `score.py:make_of` and
  the filename tokens are the only machine-readable make signal, and they are
  unreliable (station tokens like `circlek` interleave with head tokens). I took the
  brief's numbers as authoritative and confirmed only that the synthetic renderer
  has five profiles and that `expected.csv` spans 13 currencies (EUR 105, RUB 93,
  KZT 4, plus 10 currencies at 1-2 fixtures).
- **The exact live-path funnel numbers** (29/31, 25/31, 17/31, 15/31) are reproduced
  from `docs/TASKS.md` PU.24 and the diagnostic's print shape; I did not re-run
  `PUMP_LIVE_DIAG=1` to see them emit, because the diagnostic is a reading aid, not
  a committed check, and the corpus split is not something a review should perturb.
- **What a CTC row recognizer would actually reach** on the heldout split. I have
  bounded it from the law-on-oracle ceiling (294/320) and the current real-pixel
  path (66), but the 80-90 estimate is an extrapolation, not a measurement - no such
  model has been trained in this tree.
- **The detector's achievable IoU** on the glariest fixtures (`pump-021/022/023`,
  `pump-004`). A detector trained on annotated quads should track them, but those
  are the fixtures whose *slicer* already fails, so the locator win there is capped
  by the slicer's 12 % - the reason #1 and #4 are listed as separate, additive steps.
- Whether the verifier's `minimumMeanMargin = 1.0` was the *only* thing that moved
  live 11 -> 4 -> 2 across rounds 8/9; the report names it as the cause but the
  rounds changed two things at once (slicer export + classifier), so I treat it as
  the leading hypothesis, not a proven single cause.

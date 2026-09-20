# PU.32-REVIEW-STEP-CHANGE (qwen) - what would DRASTICALLY raise the pump reader's quality?

Read-only review, 2026-09-20. Every claim points at a file, a number or a fixture. Where I
re-measured instead of quoting, the run is named; where I estimate, it says so.

## Method, and the numbers I re-measured myself

I did not take the brief's funnel on faith. Three runs on this machine (Apple Silicon, macOS;
no source changed; the only file I wrote is this review):

1. `swift test --filter PumpReadingLawTests` (exit 0, 12 tests passed). The oracle-string law
   over the FULL corpus, fresh: **committed 526, correct 525, precision 0.9981, coverage
   0.8609 of 611 cells; the only wrong fixture is `pump-031`** (the discount display whose own
   arithmetic closes on 32.58 against the receipt's 32.50). Note the ratchet constants in
   `ios/Tests/TankbookCoreTests/PumpReadingLawTests.swift:16-17` are **stale**: floor 294 vs
   measured 526.
2. `swift test --filter 'PumpLivePathDiagnosticTests|PumpReaderPipelineTests'` with
   `PUMP_LIVE_DIAG=1`. Both pipeline tests **passed** before I killed the run at my own 25-minute
   shell timeout (the diagnostic suite had printed 38 of 64 stills):
   - annotated path (gateMirror): **committed 66, correct 64, precision 0.970, coverage 0.377 of
     175; photos every field right 18/64; 76.7 s** (~1.2 s/still).
   - live path (livePath): **committed 11, correct 11, precision 1.000, coverage 0.063 of 175;
     photos every field right 3/64; 979.7 s** (~15.3 s/still - with the diagnostic running
     concurrently, so treat as indicative, not exact; see Q1 on latency).
3. Parsed the diagnostic's per-still output for the 38 stills it reached (all 35 owner heldout
   stills + `pump-119/120/123`). Fresh funnel over the **35 owner heldout stills**:

| stage | fresh run (35 owner stills) | recorded PU.24 funnel (31-photo subset) |
|---|---|---|
| locator puts a candidate on a true row (>= 1) | **33 / 35** | 29 / 31 |
| verifier keeps a true row (>= 1) | **32 / 35** | 25 / 31 |
| two transaction rows verified | **20 / 35** | 17 / 31 |
| row assignment gives the right roles (>= 2) | **19 / 35** | 15 / 31 |
| live path commits (>= 1 cell) | **2 / 35** (pump-079, pump-080; the third committing photo of the 3/64 sits in the pump-125..217 tail my run never reached) | - |

The recorded funnel (in `docs/TASKS.md` PU.24 and in this brief) covers only the `pump-0xx`
owner subset; **the 29 third-party heldout stills - the hardest population (680-1536 px,
watermarks, night, fog, one-decimal Tokheim heads) - have never been funneled.** My run covered
three of them before the kill: 3/3 candidate hit, 2/3 two-rows-verified, 0/3 committed.

Fence note: I redirected the test log to `/tmp/pu32-diag.log` before remembering the brief says
no `/tmp`; extracted the numbers and deleted it. Nothing else outside this file was written.
`scripts/gate.sh` not run - a read-only review compiles nothing. The working tree's modified
`Spike/ReceiptSpike/fixtures/pump-live/video-labels.json` is a concurrent corpus run's; I read
it (234 usable labelled video frames: 120/39/4/71 over the four clips) and touched nothing.

## The one-line answer

The reader does not have one bottleneck, it has **two measured cliffs and a stale measuring
stick**, and the step change is a package, not a percent:

| tier | committed cells | coverage | precision | what it measures |
|---|---|---|---|---|
| law on oracle digit strings (full corpus, 611) | **526** | **0.861** | **0.998** | the ceiling if pixels were perfect |
| annotated windows + real pixels (heldout, 175) | **66** | **0.377** | **0.970** | cliff 1: per-cell read quality (2.3x down) |
| live path, photo in nothing else (heldout, 175) | **11** | **0.063** | **1.000** | cliff 2: locator + verifier + loose boxes (6x down) |

**Cliff 2 is the product number and it is owned by the locator/verifier pair, which is why the
one thing to build next week is a learned row detector on the box labels already in the
checkout (153 train stills + 1 906 tracked train frames + labelled video frames, ~8.5k boxes,
zero new capture) and a verifier whose keep-signal is the detector's confidence, not the
classifier's margin** - the margin coupling is what slid the live path 11 -> 4 -> 2 across
rounds 8/9 (`ml/pump-reader/REPORT.md`) while the classifier itself moved within +-7 cells.
**Cliff 1 is a data-sampling problem, not a data-volume problem**: the real-glyph set is 93 %
Live-frame near-duplicates of two head families (measured below), while the heldout split tests
26/64 stills of heads that contribute 0.6 % (Tokheim) and 0.3 % (Scheidt) of real training
cells and 0 % (Tatsuno). The 0.99/0.60 gate is NOT structurally blocked by the arithmetic -
the fresh oracle run proves the law can do 0.861 at 0.998 - it is blocked by pixels, and at
gate-scale coverage the precision half has ~1 cell of slack, which the `pump-031` discount
class consumes. More stills of the kinds the corpus already holds buys approximately nothing.

---

## 1. Architecture: is the pipeline right, or is its ceiling structural?

**The shape is right and the ceiling is not structural.** The evidence is the fresh oracle
number: given perfect digit strings, the existing law commits 86 % of cells at 0.998 precision
(`PumpReadingLawTests` run above). A pipeline whose decision layer can clear the gate's own
numbers is not architecturally capped; what is capped is the two hand-built stages that stand
between pixels and that decision layer:

- **Locate + verify** (Vision text boxes + classical projection + margin/aspect/count filters):
  owns cliff 2, the 6x. My funnel: 33/35 photos get a candidate on a true row, but only 20/35
  keep two transaction rows, and only 2/35 of those commit. Two failure populations, both
  measured: (a) 14 true rows LOST at the verifier - 8 because the slicer found < 3 cells on the
  loose box, 5 at margins 0.7-0.9 against the 1.0 threshold (`PumpReader.swift:68`), 1 on the
  aspect rule; (b) rows that survive but read worse than they would from a human quad - of 19
  photos with assignment right, only 2 committed, against 28 % (18/64) on the annotated path.
  The classifier is framing-sensitive by measurement, not theory: round 4 found a framing change
  alone moved digit accuracy by a third (`REPORT.md` -> "The shipped recipe"). Vision's boxes
  plus 0.1-height pads (`PumpVisionProposer.swift:29-31`) are not human quads (+-1 %), so the
  live path pays the framing tax on every window it even gets right.
- **Slice + classify per cell** (527-line classical slicer at 0.882 heldout count agreement,
  8-sigmoid CNN at 0.81-0.82 synthetic-val digit): owns cliff 1 together with the dp bit.

There is also a **latency wall nobody has measured on device**: the live path took ~15.3 s/photo
on this Mac (test harness, concurrent contention, so indicative only) versus ~1.2 s/photo for
the same read stage on annotated quads. The delta is the Vision `.accurate` recognition + text
rectangles on a 1600 px frame plus up to 48 candidates each warped, sliced and classified
(`PumpReader.swift:79`, `verdicts`). The capture budget is 3 s per attempt
(`docs/EXTRACTION.md` -> P4.12, latency). Even if device numbers come in 3x better than this
Mac, the propose-then-verify-everything architecture does not fit the budget; a detector that
returns ranked rows in one pass does.

**(a) Single detector+recognizer (CRNN/CTC over the whole row, no slicer).**
- Corpus needs: row strings only - `windows.json` `text` per window; the train export already
  holds ~8 550 warped train windows with strings (`PumpTrainSliceExportTests`), the videos add
  591 more (round 9), and the synthetic row renderer exists (`row.py`, `render --rows`).
  No per-cell boxes needed; CTC aligns. The comma becomes a token, which deletes the dp-bit
  problem (AUC 0.52 -> 0.548 -> 0.79 accuracy across rounds - still the weakest bit, and it is
  what keeps per-window near zero: a window needs EVERY digit AND its dp right).
- Device cost: a 3-4 conv + small BiLSTM (or pure-conv, ANE-friendlier) + CTC over a 96 px
  strip is ~0.5-2 MB fp16, single-digit ms per row on iPhone 12. One call per row replaces
  cells x 5-crop TTA calls.
- Plausible heldout reach (estimate, not measurement): it removes the 28/238 count-miscounting
  windows and the dp failures, so the annotated path plausibly goes 66 -> ~85-110 committed at
  >= 0.97; the live path does not move until the locator is fixed. Costs: the law's interface
  changes - it consumes ranked candidate STRINGS per field (a CTC beam provides them) instead of
  per-cell segment posteriors; `DigitRepair`'s segment-topology ordering (a dim `e` makes `9` a
  `4` candidate) is lost and must be re-expressed as token-level confusions learned from data;
  PU.11 F13's "cell count as the external scale pin" weakens to token count. Those are real
  design losses, payable only because the alternative keeps paying the dp tax.

**(b) Display-level detector feeding the existing cell classifier.**
- Corpus needs: window boxes. **They already exist, train-split only, decision-9-clean**:
  599 windows on 153 train stills (`windows.json` x `split.csv`), ~7.9k mapped window boxes on
  1 906 tracked train frames (`pump-live/frames/<stem>/windows.json`, written by `track.py`,
  e.g. live-4386: 69 kept frames x per-frame quads), plus the labelled video frames (234 in the
  working tree). Negatives: the 122 receipt/screenshot/fiscal fixtures. This is the only
  proposal whose entire training set is in the checkout today.
- Device cost: YOLO-nano class via Create ML ObjectDetector or ultralytics -> coremltools,
  ~1-6 MB, ~5-20 ms per frame on iPhone 12's ANE (device number unverified). Replaces the
  Vision+48-candidate loop, so it is also the latency fix.
- Plausible reach: closes most of cliff 2. If detector boxes reach human-quad tightness
  (IoU >= ~0.7 with the annotated quads) on >= 85 % of photos, live plausibly lands 40-55
  committed (annotated is 66; residual = box-quality tax), photos 3/64 -> ~12-16/64. Caveat
  below: at that coverage the live precision floor is exposed.

**(c) Keep the pipeline, fix the weakest stage.**
Cheapest increments, both measured above: decouple the verifier's keep-signal from the
classifier margin (hours; stops the 11->4->2 retrain slide and recovers the 5 rows lost at
margins 0.7-0.9), and PU.11 F3's candidate-grid slicer (classifier-scored segmentation
hypotheses, no new model; attacks the 12 % heldout / 24 % train miscount).

**The stage I would replace first: the locator+verifier pair, replaced together by (b)'s
detector with its own confidence as the keep-signal.** The funnel says so three ways: it owns
the largest cliff (6x vs 2.3x); it is the only stage whose failures are concentrated in
constants fitted to one classifier generation (margin 1.0 fitted to round 6 - `REPORT.md`
round 8 says it outright: "the live number is a verifier number, not a classifier number"); and
it is the stage the 3 s budget cannot afford to keep. One interaction the ranking must carry:
**raising live coverage from 11 to ~50 will expose live precision to the annotated path's
failure class** - the 2 errors in 66 are the `pump-106` consistent tenfold shrink (leading cell
lost in liters AND total; 5.1 x 70.31 = 358.58 closes). 11/11 = 1.000 today is a small-numbers
artifact; at ~50 committed, one such error is 0.98 and trips `livePrecisionFloor = 0.99`. The
detector row must ship with a scale guard (per-currency digit-count signatures, PU.14 §3's free
audit) or the owner rules the floor down with an enumerated-artefact clause (PU.14 §4.2).

## 2. The slicer: hand-built projection, learned, or CTC?

State: heldout count agreement **210/238 (0.882**, floor 0.85, `PumpReaderHarnessTests`);
train export **6 462/8 550 (0.756)** - a 24 % miscount on the material that feeds training,
which is why `realglyphs.py` skips miscounted windows whole and the real set inherits only the
slicer's clean output. The failure shapes are named (PU.11 F3 census on the older corpus):
faint Wayne LCD under-counts (`pump-021` 3/185 windows, `pump-022` 5/310 - round 6), Scheidt
VFD bloom over-counts, Gilbarco's comma-in-its-own-cell breaks pitch. These are optical and
structural, not tuning debt: the slicer has already absorbed Otsu, LCN, split-merge, short-count
retry, harmonic-vs-fundamental pitch and the pitch-to-body check, each measured
(`PumpGlyphSlicer.swift:1-33` header, PU.24 rounds). Further classical tuning is percents.

What the corpus gives for a learned segmenter today: **quads + row text, no per-cell boxes.**
The only per-cell boxes in existence are the production slicer's own (`ios/.build/pump-reader-out/`,
circular supervision, 88 % right on heldout). Synthetic rows DO carry free true boundaries
(`render --rows` writes a box per glyph), so a per-column ink/gap boundary classifier can be
trained entirely on renders - and then faces the same synthetic-to-real gap that took the cell
classifier nine rounds to half-close.

**Recommendation, in order:**
1. **F3 candidate grids now** (PU.11 proposed it; nothing implemented it): keep the projection
   as a hypothesis GENERATOR (pitch candidates: autocorrelation peak, half, double, width/n for
   n in count +-2; phase by valley energy; leading blanks 0-2 on ink evidence), score ~20 grids
   with the existing classifier's constrained log-likelihood, take the winner. ~200 inferences
   per window, trivial on device, no new model, no new labels. Its guardrail is measurable
   before trusting it: on the 210 count-correct heldout windows the true grid must win the
   contest at a rate you record; below ~85 % the proposal dies cheaply.
2. **CTC as the architecture decision, prototyped after the detector (Q1a)** - it deletes the
   stage instead of improving it, and it is the only option that also deletes the dp bit. Do not
   run 1 and 2 as competing investments: 1 is a week-scale patch that pays even if 2 wins later,
   because the candidate-grid scorer is also the CTC's fallback verifier.
3. **Not** a learned per-column classifier on slicer-derived labels: it cannot beat the count
   agreement its labels came from, by construction.

## 3. The locator / verifier: what I would build with the boxes already in hand

**Proposal: one learned row detector, single class `digit-row`, replacing both the proposer and
the verifier's judgment.** Roles stay with `PumpRowAssignment` (0.996 = 834/837 on clean
geometry, PU.30 - it is the strongest stage in the pipeline and should not be re-learned).

- **Training data (all in the checkout, all train-split):** 153 stills with 599 window quads;
  46 tracked Live records -> 1 906 frames with mapped quads (`track.py` output carries `_split`,
  and the extractor already asserts no heldout leaks - `realglyphs.py:79-80`; the detector
  trainer needs the same assertion); 4 videos' labelled frames (234 and growing in the working
  tree). Deduplicate frames (every k-th; they are 30 fps near-copies). Negatives: the 122
  receipt/screenshot/fiscal fixtures plus random crops of pump photos outside the display.
  Roughly 2 000 distinct images / ~8.5k boxes - small but workable for a nano detector with
  transfer learning, and the tracked frames are effectively free box augmentation.
- **Tooling:** Create ML ObjectDetector (zero training code, trains on this Mac, exports
  `.mlmodelc`) for the first cut; ultralytics YOLO11n -> coremltools if Create ML's recall on
  glare/rotated fixtures disappoints. 1-6 MB in the bundle vs today's 64 KB - acceptable, and
  the 500 KB target in `model.py:9` belongs to the cell classifier, not to a new stage; the
  owner should confirm that budget explicitly.
- **What it must reach for live to match annotated** (from my funnel, per-photo): candidate hit
  33/35 -> 35/35 including the rotated fixtures (`pump-019` rot 90 and `pump-023` rot 270 are
  today's only complete locator misses in the owner set - whether rotation or glare causes them
  is unverified; re-run `PUMP_LIVE_DIAG_ONLY=pump-019` to settle it); two-transaction-rows
  verified 20/35 (0.57) -> >= 0.85 of photos; box IoU vs the human quads >= ~0.7 so the warped
  strip matches the classifier's training framing (round 4's framing sensitivity is the
  measured reason this number matters); false rows per photo low enough that assignment's 0.996
  survives detector boxes (replay `PumpRowAssignmentTests` over detector output as the check).
- **The verifier becomes a sanity filter, not a judge:** keep cells in [3, 8]
  (`PumpReadingLaw.maxCells`), keep the 2.5 % height floor; DROP the classifier-margin gate
  (`minimumMeanMargin`) and the aspect-per-cell rule from the KEEP decision - detector
  confidence ranks and gates instead. The margin stays where it belongs: in the law's
  abstention arithmetic. This is the decoupling that ends the retrain slide. Keep the
  `PumpDisplayCapture` classification stage working by re-fitting ITS threshold
  (`classificationMinimumMargin = 1.5`, also a round-6-era constant) on detector confidence, and
  re-measure the 4-of-6 heldout recall floor - a detector should make it 6/6 (`pump-032` yields
  one verified row today, `pump-035` sits at 31 Vision text lines against the 30-line ceiling;
  a detector removes both failure modes because neither is about text lines any more).
- **Cost:** ~1 week (trainer script + assertion plumbing + export + Swift wrapper + the two
  ratchet replays). Expected effect: the largest single move available on the live path
  (11 -> ~40-55 committed, 3 -> ~12-16/64 photos), the latency fix, and immunity of the live
  number to classifier retrain drift.

## 4. Training data: the real share is fine; the real SAMPLE is two head families in Circle K lighting

Measured from the committed manifests (`ml/pump-reader/.out/real*/manifest.json`, rounds 6-9):

| fact | round 6 (25 085 cells) | round 9 (30 559 cells) |
|---|---|---|
| cells from Live FRAMES (near-duplicates) | **92.7 %** | 93 % |
| cells from stills | 2 149 (7 %), 152 stills, **median 14 cells/still** | same shape |
| fixtures holding 50 % of all cells | **14** | 15 |
| top-10 fixtures' share | 38 % | 37 % |
| Wayne/Dresser + Gilbarco share | ~88 % | **88.2 % (51.5 + 36.7)** |
| Tokheim / Scheidt / Tatsuno / GVR-keypad | - | **0.6 % / 0.3 % / 0 % / 4.6 %** |
| video cells | 0 | 2 131, from TWO clips (video-001 Wayne 1 128, video-004 GVR 923) |

The cause is structural, and it is why "more corpus" is the wrong prescription: frames exist
only where the owner shot Live Photos - **58 of the 66 live-paired stills are Gilbarco/Circle K,
7 are Wayne/Dresser** (`corpus.sqlite` media join; `tracking.csv`: 63 records tracked, 46 train,
2 766 frames kept) - and cells exist only where the slicer's count agrees, which excludes
exactly the faint/thin heads (Tokheim one-decimal reflections, Scheidt VFD). Meanwhile the
**heldout split tests 26/64 stills of those under-fed heads** (Tokheim 10, GVR 11, Scheidt 3,
Tatsuno 2). The corpus's third-party intake ALREADY holds the scenes people would go out and
shoot: ~25 Tokheim stills including night, fog, snow, dusk, blur, tilt (`pump-190..206`),
Scheidt reflections (`pump-087..093`), Tatsuno amber LED night (`pump-186/187`), Pignone
(`pump-182/188/210`), 13 currencies. **The 217 stills are not missing scenes; the training set
is missing their CELLS, because cells follow frames and frames follow one forecourt.**

Fixes, ranked by effect/cost:
1. **Rebalance the sampler (hours).** `RealGlyphs.batch` (`train.py:58-73`) draws uniformly over
   cells, so a 1 176-cell fixture (`pump-067`) outweighs a whole head family. Sample uniformly
   over STILL-FIRST strata (per fixture, per head family, cap per (fixture, frame) source),
   which turns 30k cells from ~15 stills' worth of diversity into ~150 stills' worth. Also
   downweight the two video clips' 2 131 near-duplicate cells.
2. **Hard-example mining on the TRAIN split's own misses (days, legal - heldout is frozen):**
   the 24 % of train windows the slicer miscounts and the train-split verifier losses are
   labelled hard examples nobody trains on. Feed their cells (with count-disagreement handled
   by row-level labels or skipped) into the mix.
3. **New synthetic profiles (days):** `profiles.py` has exactly five makes (gilbarco, wayne,
   dresser, scheidt, tokheim). No Tatsuno amber LED, no GVR keypad face, no Pignone, no Adast.
   The stills to calibrate aggregate shape statistics on exist (decision 3 allows aggregate
   calibration); the renderer just cannot draw them.
4. **Real-only fine-tune: last, if at all.** With ~15 stills' worth of effective diversity it
   overfits the two Circle K forecourts; the rounds-6-9 evidence (three recipes within 7 cells)
   says the current bottleneck is not the fine-tune schedule.
5. **Capture, but the RIGHT capture (a week, and it is the weakest lever per hour):** 15-20
   Live RECORDS on Tokheim / Scheidt / GVR / Tatsuno heads, plus decision-5's night +25 / rain
   +15 / KZT +10 as stills. One Live record is worth ~30 usable frames x ~12 cells ≈ 400 real
   cells of ONE head - 30x a still's 14 cells, and the only mechanism that fixes the 93 %-frames
   bias for the missing families. 200 more Circle K stills would add ~2 800 cells of diversity
   the set already has 88 % of.

Honest expectation: rebalancing + profiles move the annotated path a few cells (66 -> ~70-78 at
0.97) - inside or just outside the +-7 noise band until Q5's protocol exists. The capture that
would DOUBLE a heldout number does not exist under decision 9 at all (the measured set is frozen
at 64/175; new stills are train by rule) - see Q5's heldout-2 proposal.

## 5. Measurement: what the owner should refuse to believe

175 cells over 64 photos, and the photo is the unit that matters (the law commits all three
fields or nearly none - my funnel: 2 committing photos produced 6 of the first 38 stills' cells;
the completed livePath run: 11 cells, 3 fully-right photos). Minimum protocol before ANY number
is believed:

1. **Three seeds per recipe.** All four real-glyph retrains are seed 0 (verified in
   `runs/2026-09-20/train-r{6,7,8,9}-real-metrics.json`). Round 9 already concluded "a retrain
   needs 3 seeds before a number means anything"; it has not been done. Training is ~10-13 min
   per run on this machine (620-776 s wall) - three seeds is half an hour, not a project.
2. **Cluster bootstrap over the 64 PHOTOS** (cells within a photo are correlated by the law),
   10k resamples, 95 % CI on committed cells, precision and photos-all-right. Binomial feel:
   66/175 has se ~ 0.036, so +-13 cells is the noise band - rounds 6/7/8/9 (62-69) are ONE
   number, and the live slide 11 -> 4 -> 2 is significant only because the MECHANISM (margin
   threshold) is known, not because the counts are.
3. **Per-head and per-currency breakdown** of every headline: Wayne/Dresser, Gilbarco, GVR-keypad,
   Tokheim, Scheidt, Tatsuno, other x EUR 31 / RUB 28 / singleton currencies. `score.py` already
   computes per-make for the classifier; the pipeline tests print per-field only. A 66 that is
   60 Gilbarco + 6 everything-else is a different product fact than a spread 66.
4. **The funnel over all 64, sharded.** The recorded funnel covers 31 (my run: 38 before the
   kill); the 29 third-party stills - the hardest and most diverse population - have no funnel
   measurement at all. The live suite takes ~16 min per pass; shard by name prefix so a
   diagnostic run fits a coffee.
5. **Verifier/classification margin re-fit as a standing rule:** every retrain reports its margin
   distribution over TRAIN-split verified rows and re-fits (or consciously keeps) the 1.0 / 1.5
   thresholds, then re-runs the live floor. Round 8's slide was a silent threshold drift; make
   it a checklist item or every future floor is measuring a different system.
6. **Floors move only on 3-seed means with CIs**, never on single runs (the 66/0.96 floors were
   set from single seed-0 runs).
7. **Split shape: keep the frozen random 70/30; do NOT re-stratify it now.** Per-head
   stratification would shatter the per-head cells (Tokheim heldout ~28 cells) and reopen a
   frozen product decision. The right growth path is a **heldout-2**: an owner ruling that the
   NEXT intake (e.g. every 100 new stills) gets its own seeded 30 % draw, frozen the same way;
   report both splits separately and the union with per-split labels. Without it, the measured
   set stays at 175 cells forever and +-13-cell noise is permanent - which quietly makes the
   ratchet un-steppable: a true step change of +20 cells would be barely distinguishable.

## 6. The law and the ship gate: reachable, with one enumerated wound and no slack

The gate: precision >= 0.99 at coverage >= 0.60 (`PumpPhotoGate.swift:71-81`); its constants
today hold the RULES arm's full-corpus score (56/611 committed = 9 % coverage - the gate is off
on coverage for that arm regardless).

**What the arithmetic can and cannot do** (`PumpReadingLawTests`, PU.13 §4, PU.14):
- CAN: unique-close commit with beam + one-substitution repair + truncated-total derivation +
  preset tier. Fresh oracle measurement: **0.861 coverage at 0.998 precision** - so the 0.60
  floor is NOT blocked by the law's design. DeepSeek's review (the sibling file) quotes 294/320
  from PU.14 §2.6 - that is the stale constant over the OLD 114-fixture denominator; today's
  measured number is 526/611.
- CANNOT: see a swap (a x b = b x a - guarded by frozen roles, not arithmetic), see scale
  (liters x price = total is scale-invariant - guarded by decimal conventions, the seen-mark
  penalty and bands), or see the CONSISTENT shrink: `pump-106`, leading cell lost in liters AND
  total, 5.1 x 70.31 = 358.58 closes, and it is one of the annotated path's 2 wrong cells
  today. Partial structural kills exist: per-currency digit-count signatures (PU.14 §3: "EUR
  price is exactly 4 digits in 63/63" - free audit, unimplemented), Live-fusion (a leading cell
  faint in one frame is lit in another), and decision 6 (the receipt outranks the pump reading
  anyway - the shrink class only bites receipt-less fills).
- CANNOT ever: read a discount display honestly. `pump-031` closes on its own display value
  (32.58) against the receipt's 32.50; it is the oracle run's single wrong fixture. Heldout
  carries 6 `csvDisagrees` entries (`pump-031/041/140/190/208/209`), most "asserted as shown"
  and benign, but the discount class is unknowable from pixels.

**Is 0.99 at 0.60 reachable with this pipeline?** Coverage: needs 105/175 heldout cells ≈ ~40
of 64 photos fully committing (today: 18 annotated / 3 live; oracle shows ~55 photos are
law-committable). That is a 2.2x improvement of the READ stage at human-quad quality plus a
locator that delivers human-quad quality - detector + fusion + rebalanced data + (plausibly)
CTC. Not one row; not structurally impossible. Precision: at 105+ commits the 1 % budget is
~1 cell, and the discount class alone consumes it (526-commit oracle: exactly 1 wrong). So
**0.99 is reachable ONLY with PU.14 §4.2's enumerated-artefact clause** (named fixtures excluded
by owner ruling, test-enumerated) **plus a structural kill of the pump-106 shrink class** -
otherwise the honest ceiling is ~0.990 with zero slack, where the first new defect masquerades
as "another artefact".

**What gate IS reachable, and what the app does with it:** keep decision 7 exactly as shipped -
the reader runs, its committed fields pre-fill Confirm with the alpha notice, every field is
editable at offer time and afterwards (hard rule 13), typing stays the peer door (hard rule 15),
the receipt stays the truth (decision 6). The gate governs FRAMING only
(`PumpPhotoCapture.outcome`), so the product is not blocked while the numbers climb. For PU.6's
ship decision, rescope rather than relax: (i) per-arm denominators - the reader's honest
coverage denominator is the heldout 175 (or 611 full-corpus via the law oracle), not the rules
arm's constants; (ii) precision 0.99 with the enumerated-artefact list the owner signs; (iii)
coverage staged - alpha graduation at ~0.40 heldout with per-head reporting, the 0.60 floor kept
as the documented target the detector+fusion+data rounds must earn; (iv) the live precision
floor re-derived at whatever coverage the live path reaches (today's 0.99-on-11 is a formality,
and at ~50 commits it becomes the binding constraint - see Q1's interaction note).

## 7. The one thing

**Build the learned row detector and decouple the verifier (Q3's package, ~1 week, no new
capture, no new annotation - the boxes are in the checkout).** It is the only proposal that
moves the number the product actually runs:

- live path committed cells on the heldout split: **11 -> ~40-55** (annotated ceiling 66 minus
  box-quality residual), photos every field right **3/64 -> ~12-16/64**;
- it ends the retrain slide (margin no longer gates rows), so every later classifier round
  finally shows up in the live number instead of vanishing into a threshold;
- it removes the ~15 s/photo Vision+48-candidate loop (Mac harness measurement; device
  unverified), which the 3 s budget forbids anyway.

Ship it with the digit-count-signature guard (or an owner ruling on the live precision floor),
because at 40+ commits the `pump-106` class WILL appear in the live number.

If the owner insists the one thing must be capture: **15-20 Live records on Tokheim, Scheidt,
GVR-keypad and Tatsuno heads, night/rain included (decision-5's list), ~50 captures total** -
because frames, not stills, are the currency of real training cells (93 % measured) and those
four families have zero or near-zero frame coverage against 26/64 heldout stills. Expected
effect, honestly: annotated path 66 -> ~70-78 (inside the +-7-to-13 noise band until Q5's
protocol exists), live path unchanged without the detector. Capture is the right SECOND thing;
it is not the step.

## Ranked proposals (expected effect on the LIVE path / cost)

| # | Proposal | Expected live-path effect | Cost | Confidence |
|---|---|---|---|---|
| 1 | Learned row detector on existing boxes + verifier keep-signal decoupled from classifier margin (+ count-signature scale guard) | 11 -> ~40-55 cells; 3 -> ~12-16/64 photos; ends the retrain slide; fixes latency | ~1 week; training data already in checkout | medium-high (mechanism measured; the 40-55 band is an estimate) |
| 2 | Measurement protocol: 3 seeds, photo-bootstrap CIs, per-head tables, funnel over all 64, margin re-fit rule, heldout-2 proposal | moves nothing; makes #1, #3, #4 believable and the ratchet steppable | ~days, concurrent with anything | high (all gaps verified: single-seed rounds, 31-photo funnel, stale law floor 294 vs 526) |
| 3 | PU.19 first half: OFFLINE Live-fusion measurement on the 17 heldout records (median of 8 probabilities per cell across tracked frames), annotated path | annotated 66 -> ? (glare fixtures pump-014/041/025 are named failures fusion directly attacks); decides the device half on a number | days (Python, track.py output exists) | medium (mechanism licensed by decision 2; effect unmeasured) |
| 4 | Real-glyph sampler rebalance (still-first, per-head caps, video dedupe) + 4 new synthetic profiles (tatsuno, GVR, pignone, adast) | classifier on the 26/64 heldout stills of under-fed heads; annotated +4-12 cells; live only via #1 | hours-days | medium |
| 5 | F3 candidate-grid slicer (classifier-scored segmentation, guardrail measured first) | recovers part of the 12 %/24 % miscount class -> annotated +5-15 cells; live via #1 | ~1 week | medium (proposed in PU.11 with a kill criterion; never built) |
| 6 | CTC row recognizer (deletes slicer + dp bit; law consumes ranked strings) | annotated 66 -> ~85-110 (estimate); live still gated by #1 | 1-2 weeks + law interface rework | low-medium (no such model trained in this tree; bounded by oracle 526/611) |
| 7 | Capture week: Live records on missing head families + night/rain/KZT (decision-5 list, ~50) | feeds #4's pipeline; alone: a few annotated cells, no live move | a week of shooting + intake | high that it is necessary eventually, low that it is the step |
| 8 | 200 more stills of kinds the corpus already holds | ~nothing: 88 % of real cells are already Wayne+Gilbarco; new stills are train-split by decision 9 and add ~14 cells each | high | high (this is the measured anti-proposal) |

## What I could not verify

- **Any device (iPhone 12 / iOS 18) number.** All timings here are macOS test-harness numbers
  under concurrent-suite contention; the ~15.3 s/photo live figure is indicative of the
  architecture's cost, not a device measurement. Nothing in the checkout measures on-device
  latency of the reader; that gap should be closed before any ship claim either way.
- **Why `pump-019`/`pump-023` (the two rotated heldout fixtures) get zero candidate hits.** The
  diagnostic rotates the image upright before proposing (`PumpLivePathDiagnosticTests:35`,
  lossless transpose in `PumpPanelLocator.rotatedRGB`), so it is either the rotation path or
  genuine scene difficulty (pump-023 is a glare fixture); a one-photo
  `PUMP_LIVE_DIAG_ONLY=pump-019` re-run settles it and I did not spend the 16 minutes.
- **The tail of the funnel**: my diagnostic run was killed at 38/64 stills (my timeout, not a
  failure), so the third-party funnel (29 stills) has 3 photos of coverage from me and none
  from the record.
- **What a CTC recognizer or a trained detector would actually score** on the heldout split.
  Both ranges are extrapolations from the oracle (526/611), the annotated (66/175) and the
  framing-sensitivity measurement (round 4); no such model exists in this tree.
- **Whether the round 8/9 live slide is 100 % the margin threshold.** REPORT.md names it; the
  rounds changed the slicer export and the classifier together. The decoupling proposal is
  robust either way, but the causal share is unmeasured.
- **The exact heldout per-field commit split of the 66** (the gateMirror per-field lines scrolled
  out of my extraction before I deleted the log; the aggregate 66/64/0.970 is verified).

## Found and not fixed (with the row that owns it, or none)

1. **`PumpReadingLawTests.committedFloor = 294` is stale against the measured 526** (fresh run
   above; floors "move only upward" by their own comment). No open row owns ratchet-constant
   hygiene; PU.6 (ship decision, `[ ]`) is the natural home, or a one-line orchestrator fix.
2. **The recorded live funnel covers 31 of 64 heldout stills** (`docs/TASKS.md` PU.24: "31
   owner stills"); the 29 third-party heldout stills have no funnel measurement. PU.24 (`[~]`)
   owns the locator rounds and should own the full-64 funnel.
3. **`pump-019` (rotationCW 90) and `pump-023` (rotationCW 270) are total locator misses** -
   zero candidates on a true row, the only two in the owner heldout set (fresh run). PU.24
   (`[~]`) owns this; no row currently names rotation as a locator failure class.
4. **The live precision floor will bind at exactly the moment the live path improves**: at ~50
   commits, one `pump-106`-class shrink is 0.98 < `livePrecisionFloor = 0.99`
   (`PumpReaderPipelineTests.swift:36`). The scale guard (digit-count signatures, PU.14 §3) is
   unimplemented and no open row names it; PU.5 (`[ ]`, reader end-to-end) or PU.6 should adopt
   it, or the owner rules the floor with an artefact list (PU.14 §4.2).
5. **Two model-coupled margin constants gate three different things** (verifier keep at 1.0,
   classification at 1.5, both round-6-fitted; 13 of 89 verified rows in my run sit in
   [1.0, 1.5)). No row owns re-fitting them per retrain; round 9's "seed check first" note is
   the closest thing and it is a REPORT.md sentence, not a task.
6. **The law's oracle coverage (0.861) is higher than anything the docs currently quote**
   (PU.14 §2.6's 0.978-ceiling prose is from the 320-cell era; the brief's own table omits the
   oracle tier). `docs/EXTRACTION.md`'s pump section should carry the three-tier ladder when
   PU.6 rewrites it.
7. Working tree at review time: `video-labels.json` modified (+222 lines, 234 usable labelled
   frames vs the 196 the brief quotes) - concurrent corpus work, not touched, noted so the
   orchestrator does not read my numbers as the committed state.

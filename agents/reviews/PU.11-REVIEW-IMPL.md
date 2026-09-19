# PU.11-REVIEW-IMPL - the pump-reader implementation, reviewed for one goal: a better model

Read-only review, 2026-09-19. Scope: the slicer, the classifier, the framing contract between the
two halves, the scorer, and the decoding that PU.5 must build. The sibling review
`agents/briefs/PU.12-REVIEW-DATA.md` covers the training material (renderer fidelity, palettes,
augmentation, sampling); where a finding straddles both, it is flagged **[coord PU.12]** and I keep
the contract side. No code was changed. One file written: this one.

## Method, and the numbers I reproduced myself

Every measurement below was made in this session against the shipped checkpoint
(`ml/pump-reader/.out/train-r2-15k/segmentnet.pt`) and the committed slicer output
(`ios/.build/pump-reader-out/slices.json`), by running the existing harness/scorer or by inline
analysis that only loads and measures (no training, no repo writes beyond this file):

- `swift test --filter PumpReaderHarnessTests.slicerRatchet` - exit 0, 1 test, 107 s:
  count agreement **259/433 (0.598)**, dp agreement **1/422**, locator floors reported.
  Per-make count agreement as measured now: circlek 16/27 (0.59), dresser 68/102 (0.67),
  gilbarco 77/128 (0.60), gpn 3/3, kz 6/9, lukoil 8/10 (0.80), rn 4/6, **scheidt 12/30 (0.40)**,
  tokheim 14/21 (0.67), topaz 2/3, unknown 2/3, **wayne 47/91 (0.52)**.
  (The brief quotes "Scheidt 0.30, Lukoil 0.10, Wayne 0.53"; those do not reproduce against the
  current tree - they look pre-grid-anchor. Use the table above.)
- `.venv/bin/pytest -q` - exit 0, **21 passed**.
- The scorer's own math replayed inline over the 259 count-correct windows: per-glyph exact
  **0.3995 (467/1169)** - reproduces REPORT.md's 0.400.
- New measurements made for this review (all reproducible from the same two artifacts): the
  decoder ablation (F1), the dp AUC (F2), the strip-height ablation (F5), the aspect study (F8),
  the count-delta census (F6/F7), the confidence-coverage curve (F11), the dump-filename
  collision count (F4c). Exact recipes are in "Checks run" at the end.

The state of the reader in one paragraph: the classifier is near-perfect on synthetic
(per-digit 0.9726, dp bit 0.9822 - `runs/2026-09-19/metrics-r2-15k.json`) and reads 0.400 of real
glyphs exactly; **25.5 % of real cells decode to no digit at all**; the **dp bit is dead on real
cells (AUC 0.520 - a coin flip)** while 255 of the 259 count-correct windows contain a dp; the
slicer gets the glyph count wrong on **174/433** windows (129 under, 45 over); the locator is a
stub (median IoU 0.008); and the model's own confidence barely ranks its real-cell errors
(digit accuracy 0.763 at 30 % coverage vs 0.612 at 100 %), which is what the 0.99-precision ship
gate (`PumpPhotoGate.swift:71`) would have to run on. PU.10's conclusion - "the next gain is
render realism again, not training" - is half right: render realism is one bottleneck, but this
review found three others that no render change touches, and two of them are nearly free.

## Findings, ranked by expected gain per unit of work

### F1. Decode to valid segment patterns, not per-bit 0.5 thresholds - +25 glyph points, zero retraining

**Area 2/5 (classifier, decoding). Effort: hours. Expected gain: the largest single number move
available anywhere in this pipeline today.**

- Concerns: `ml/pump-reader/src/pump_reader/score.py:221-223` (`classify_cells` →
  `target_to_bits`), `ml/pump-reader/src/pump_reader/dataset.py:305-310` (`target_to_bits`'s
  `>= 0.5` per bit), `ml/pump-reader/src/pump_reader/train.py:59`, and the Swift snippet in
  `REPORT.md:314` that PU.5 would otherwise copy (`probs >= 0.5` per bit).
- Evidence: the 8 sigmoids are treated as independent coin flips, but only 12 of 256 bit patterns
  are glyphs (`glyph.py:26-40`). On real cells, **298/1169 reads (25.5 %) are `?` - patterns that
  match no digit** - and their Hamming distance (a-g) to the truth digit is **1 for 99, 2 for 59**
  (53 % within two bits). Re-decoding the SAME probabilities as `argmax over the 12 valid patterns
  of sum(log p_i for on-bits) + sum(log(1-p_i) for off-bits)` was measured on the 259
  count-correct windows: per-glyph **0.3995 → 0.6459**; windows with every digit right
  (dp aside) **1/259 → 76/259 (0.293)**.
- This is not a trick on top of a weak model; it is the decoding the design doc already implies -
  "the digit is a lookup over the segment pattern" (`docs/EXTRACTION.md:798-802`) - and the lookup
  must be over VALID patterns ranked by likelihood, never a per-bit threshold that can emit a
  pattern no display can show.
- Proposal: implement the constrained decode once, in Python (`score.py`) and later in the PU.5
  Swift decoder, as the only path from probabilities to digits. Keep the raw 8 probabilities as
  the field's provenance (they feed F2/F11/F13 and the repair ordering, F12). Optionally drop the
  `dp-only` pattern from the decode set until F2 is fixed - truth never contains a dp-only cell
  (`score.py:41-59` attaches every separator to its host) and the slicer never emits one.
- Measured by: the "held-out per-glyph" lines in `REPORT.md` (0.400 cc / 0.309 all move to
  ~0.65 / ~0.5 with no retrain); per-window stops being structurally ~0. No row owns this today -
  file under PU.5's decoder or a new row; it is also a prerequisite for F6's candidate scoring.

### F2. The dp is read by NOTHING today: the slicer's dp is dead (1/422), the classifier's dp bit is dead on real cells (AUC 0.520), and every window depends on it

**Area 1/2/3/5. Effort: the arithmetic half is F13 (free once the decoder exists); the optical
half is days. Expected gain: per-window accuracy is gated entirely by this - 255/259 count-correct
windows contain a dp, and exact per-window is 1/259 while digit-only per-window is 76/259.**

- Concerns: `PumpGlyphSlicer.swift:235-248` (bottom-run dp classification,
  `decimalPointTopRowFraction`), `glyph.py:221-233` (`_draw_dp`: the dot is drawn INSIDE the
  glyph box, bottom-right, inset by `MARGIN`), `dataset.py:246-270` (the slicer-framed crop
  inherits that placement), `score.py` dp scoring.
- Evidence:
  - Slicer: dp agreement **1/422** (harness run above; PU.8 already recorded that the column
    projection cannot see a dp inside the host glyph).
  - Classifier: on real cells the dp bit has **AUC 0.520** (n1=255, n0=914); mean probability
    0.137 when truth dp=1 vs 0.126 when dp=0. Per-class from the `cells-r2` dump filenames:
    `0dp` 2/30, `1dp` 8/84, `5dp` 0/19, `8dp` 0/19 - dp-carrying cells read exactly **19/244
    (7.8 %)**. Synthetic dp-bit accuracy on the same checkpoint: **0.9822**. The bit learned
    something - the wrong something.
  - The likely mechanism is placement and scale **[coord PU.12]**: training draws the dot at a
    fixed inset inside the glyph's own box; on real displays the dot sits in the inter-glyph gap
    or at the very right edge of the pitch cell (so the pitch-wide crop half-cuts it), it is a
    comma on 168/433 annotated windows, and after the 48-px strip warp it is 1-2 px. The model
    fires dp on a cue that real cells do not have and misses the cue they do have.
- Proposal, in the order the pipeline will actually use it:
  1. **Make arithmetic the PRIMARY dp source** (F13): with cell count fixed by the slicer and
     digits ranked by F1, the decimal placement is the one solution of `volume x price = total`;
     optical dp becomes a pruning hint, not a requirement. This is already the PU.5 design
     (`docs/TASKS.md` PU.5, `docs/EXTRACTION.md:803-806`) - the new fact is that it is not a
     fallback, it is currently the only working dp channel.
  2. **Strip-level gap-dot detector** in Swift (classical, ~30 lines): within the band's bottom
     20-25 %, sum ink in each inter-cell gap region and at each cell's right edge; a blob there is
     a dp on the left neighbour. Unlike the per-glyph column projection this looks where dots
     actually live, and unlike the classifier it does not need retraining. Measured against the
     same oracle the harness already uses (`PumpReaderTestSupport.dpCellIndex`,
     `PumpReaderTestSupport.swift:35-46`): the number that moves is dp agreement, floor 0.0 today.
  3. **[coord PU.12]** Re-render the training dp where real displays put it (gap-straddling,
     comma variants, sizes as a fraction of band height, partially clipped by the cell edge) and
     re-train; the number that moves is "dp bit (cc)" in REPORT.md's round-2 table - but report it
     as **dp accuracy conditional on truth dp=1** (0.078 today), not the unconditional 0.74, which
     hides a dead bit behind the 77 % of cells that have no dp.
- Also stop scoring the slicer's `hasDecimalPoint` as a deliverable if (2) replaces it; the seam
  is `GlyphCell.hasDecimalPoint` (`PumpGlyphSlicer.swift:35-39`).

### F3. The slicer must stop committing to one segmentation: emit candidate grids and let the classifier pick

**Area 1. Effort: about a week (Swift candidate generation + F1 scoring loop). Expected gain: the
0.598 count ratchet is the hard ceiling on everything downstream - a miscounted window is
unreadable - and 174/433 windows are miscounted today.**

- Concerns: `PumpGlyphSlicer.swift:102-136` (`slice` returns one answer), `:139-171` (single
  pitch from one autocorrelation peak), `:263-264` (single phase from a circular mean of run
  ENDS), `:280-282` (leading-blank heuristic), `:175-186` (short-count retry - the only place the
  code currently considers an alternative, and its criterion is weak, see F7).
- Evidence: count-delta census over all 433 windows (slicer cells minus annotated glyph count):
  **under 129** (-1: 50, -2: 41, -3: 17, -4: 17, -6: 4), **exact 259**, **over 45** (+1: 18, +2:
  8, tail to +80). The failure shapes differ by make: **wayne under-counts 38/91** (faint LCD ink
  never clears the run threshold), **scheidt over-counts 16/30** (VFD bloom puts glow runs in the
  gaps; its profile is also the only one with no LED-era siblings in the registry), **gilbarco is
  mixed (37 under / 14 over)**. One hypothesis I tested and REJECTED: dim zero-padding as the
  under-count cause - zero-padded-looking windows agree on count at 0.59 vs 0.60 for unpadded, so
  padded zeros are visible ink in this corpus.
- Is column projection the right primitive? As a **hypothesis generator, yes**; as the **decider,
  no**. The current design computes one (pitch, phase, anchor) triple from heuristics and never
  consults the only component that knows what a glyph looks like. The classifier is 64 KB; scoring
  ~20 candidate grids x ~10 cells is ~200 inferences, trivial on-device.
- Proposal (concrete, testable):
  1. Candidate generation: pitch in {autocorrelation peak, its double and half, `stripWidth / n`
     for n in [count-2, count+2]}; phase from a sub-pixel sweep that minimises profile ink at
     cell BOUNDARIES (boundaries are the inter-glyph valleys - this replaces the run-end circular
     mean, which is biased by dp dots sitting right of the glyph body and by split runs);
     leading-blank count in {0, 1, 2} gated on ink evidence only.
  2. Candidate scoring: sum over cells of the F1 constrained log-likelihood (blank included as a
     pattern, so a candidate grid that lands a cell on a gap pays for it), normalised per cell.
  3. Guard rail, because F11 shows per-cell confidence is over-confident: grid-vs-grid comparison
     is RELATIVE evidence on the same pixels, which is a much easier task than absolute
     calibration - but validate before trusting: on the 259 count-correct windows the true grid
     must win the likelihood contest at a measured rate (report it; if it is below ~85 % the
     scorer cannot drive selection and the whole proposal dies cheaply).
  4. The answer to "learned cell-boundary head vs template matching vs classifier-confidence
     selection": start with (1)-(3) - it needs no new model and no new training data. A learned
     1-D boundary head over the LCN'd column profile is the natural NEXT step and its training
     data is free once F9 exists (synthetic row in, slicer profile out, true boundaries known);
     template matching per make is dominated by (1)-(3) because the make is unknown at inference.
- Measured by: `countAgreementFloor` ratchet (`PumpReaderHarnessTests.swift:34`, 0.59 today,
  target 0.80 per PU.4's original brief) and, once PU.5 lands, field coverage. Note F6's caveat:
  count agreement is itself a proxy - the product needs the right digit string, and padding /
  blank decisions belong to the decoder.
- PU.8's four seams - which are load-bearing, which are noise? **Nobody knows: they were only
  ever ablated all-on vs all-off (259 vs 187, `PumpReaderHarnessTests.swift:63-74`).** Every flag
  already exists (`PumpGlyphSlicer.swift:43-76`); run the 2^4 (or one-at-a-time) table once and
  record it in REPORT.md. My structural read, to be falsified by that table: Otsu
  (`adaptiveThreshold`) and LCN carry the faint-wayne/gilbarco under-counts; `splitMerge` is
  double-edged - it fixes glare splits but can also MERGE two thin faint glyphs into one run
  (combined width <= 1.1 pitch, `:319-333`), a plausible under-count contributor on wayne;
  `shortCountRetry` is the most suspect (F7).

### F4. The scorer does not measure what the gate needs, and has two live defects

**Area 4. Effort: days. Expected gain: no direct accuracy, but PU.5/PU.6 cannot be steered or
shipped without it - today the gate's own quantities (committed-field precision, coverage,
confident-wrong) are computed nowhere for the trained reader.**

- Concerns: `ml/pump-reader/src/pump_reader/score.py`.
- (a) **Prefix-zip defect**: `score.py:299-311` increments `window_total` and then zips truth
  against predictions - `zip` truncates. In all-windows mode a count-wrong window whose aligned
  PREFIX reads clean scores `all_correct = True` and its missing tail silently leaves
  `glyph_total`. At PU.3's 0.12 accuracy this never fired (per-window 0.000); at today's 0.31 it
  is a matter of time, and it flatters exactly the windows the slicer broke. Fix: require
  `len(pred) == len(truth)` for a window to count as scored-correct, and report count-wrong
  windows as a separate bucket, not as glyph accuracy.
- (b) **Dump collision defect**: dump filenames are `<fixture>-<field>-<i>-<truth>-<read>.png`
  (`score.py:328-335`) with no window index; **75 windows share a (fixture, field) pair** (four
  `board` windows on `pump-009`, etc.), so later windows overwrite earlier dumps. Evidence: the
  `cells-r2` dir holds 1139 files where the same run scored 1169 cells. Every filename-based
  analysis (including the per-class dp numbers in F2, which are therefore lower bounds) loses
  ~30 cells. Fix: add the window index to the filename.
- (c) **Wrong unit for the gate**: per-window "every glyph AND its dp" is a good DIAGNOSTIC and a
  bad gate proxy. The ship gate is precision >= 0.99 on **committed** numeric fields with coverage
  >= 0.60 over the 320-cell denominator (`PumpPhotoGate.swift:39-81`), and "committed" implies an
  abstention the scorer cannot express: it scores every window as if committed, and skips the 23
  unreadable windows (`score.py:277-278`) instead of counting them as forced abstentions in
  coverage. What a "committed field" should mean here: the PU.5 decoder emits a non-nil value for
  liters/unitPrice/total (after row assignment, decimal recovery and the uniqueness rule); the
  scorer then reports the three gate numbers plus the confident-wrong list by name
  (`pump-004`, `pump-009`, `pump-013`, `pump-015` are the standing traps, `docs/TASKS.md` PU.5).
  Keep the existing per-glyph/per-window numbers as diagnostics beneath them, and keep scoring
  board windows separately - they train row assignment but are not transaction fields
  (`pump-021/022/023` show a grade board INSTEAD of a transaction price,
  `PumpPhotoGate.swift:55-58`).
  A precision-coverage frontier (commit a field only when its decoder posterior clears t; sweep t)
  is the single most decision-relevant chart this scorer can print - F11 shows the current model
  cannot bend that curve, which is itself the finding that should drive retraining priorities.
- (d) **Committed artifacts**: `runs/2026-09-19/held-out-r2-cc.json` holds aggregates only - the
  `by_name` truth/read table stays in stdout and the cell dumps live in gitignored `.out/`. A
  review (or PU.6's ship decision) should not depend on uncommitted state: commit `by_name` (it
  contains no image, only strings the annotations already hold) and the confusion counts.
- Measured by: none of these move an accuracy number; they make every other finding's number
  trustworthy. PU.6 ("the ship decision") is the row that needs (c); (a)/(b)/(d) have no owner -
  file them.

### F5. The three halves of the pipeline do not agree on the strip's resolution: harness 96 px, scorer 48 px, training ~40 px - and 96 px scores +2 points today

**Area 3. Effort: hours. Expected gain: +0.02 per-glyph measured, and it removes a silent
train/serve skew before PU.5 freezes the on-device path.**

- Concerns: `PumpReaderHarnessTests.swift:269` (`warpToStrip(..., stripHeight: 96)` - the strip
  the slicer's grid and `slices.json` rects are computed on), `score.py:116-117` (`sh = CELL_H` =
  48 - the strip the cells are actually cropped from), `dataset.py:250-270` (training rows render
  a ~40-px ink band resized to 32x48).
- Evidence: same checkpoint, same cell rects, only the warp height changed - per-glyph exact
  **0.3995 (48 px) / 0.4200 (96 px) / 0.4175 (144 px)**. The scorer throws away 2 points of the
  slicer's own operating resolution, and the future on-device path will pick some third height.
- The deeper point: the cell rects in `slices.json` are NORMALISED over the 96-px strip
  (`PumpReaderHarnessTests.swift:243-252`), then re-materialised at 48 px - a quantisation and
  resampling round-trip through a resolution the grid was never computed at. Small windows get
  upscaled, large ones downscaled, differently in each half.
- Proposal: declare ONE contract strip height (96, where the slicer demonstrably works), use it in
  the harness, in `score.py`, in the training-cell generator (F9), and in PU.5's device path. Add
  a golden-vector test: one committed strip PNG + its `slices.json` entry, asserting the Swift and
  Python warps agree within a pixel tolerance on cell corners.
- Measured by: "held-out per-glyph" (+0.02 immediately); the golden test is the ratchet that keeps
  the halves from drifting again - drift here already cost a third of the number once
  (`REPORT.md:216-241`, "The shipped recipe").

### F6. Leading-blank emission is pure loss on this corpus - delete it or demand ink evidence (+14 windows, one-line-scale change)

**Area 1. Effort: hours. Expected gain: +14 count agreements (0.598 → 0.630) immediately.**

- Concerns: `PumpGlyphSlicer.swift:273-300` (`leadingBlanks`: a whole cell's width of strip
  margin, within a quarter pitch, becomes a blank glyph cell).
- Evidence: the annotations contain **zero leading spaces in all 433 windows** (zero-padding is
  annotated as real `0`s, e.g. `pump-009` "00040,00"), yet the slicer emitted **490 blank cells**,
  462 of them in count-wrong windows; **14 over-count windows' extra cells are ALL leading
  blanks**. The oracle (`PumpReaderTestSupport.glyphCount`, `:29-31`) counts spaces as cells, so
  the code is built for a display convention this corpus does not contain.
- Caveat before deleting: this is "tuning to the oracle" only if the oracle is wrong. It is not -
  a blank cell with no ink is indistinguishable from strip margin at the slicer's level, and the
  right place for a padding/blank hypothesis is the decoder (F13), which can propose a leading
  `0` or a dropped cell when arithmetic demands it. If some makes genuinely render leading blanks
  as dim unlit cells, no ink-based slicer can ever see them, and the decoder MUST own padding -
  another reason F13 is the load-bearing piece.
- Measured by: the count ratchet (259 → 273 expected); the per-make table (gilbarco over-counts
  drop).

### F7. The short-count retry fires on nearly every window and picks winners by a criterion that punishes faint glyphs

**Area 1. Effort: hours to disable/replace. Expected gain: folds into F3; on its own, removes a
systematic bias against exactly the faint wayne/gilbarco windows that under-count.**

- Concerns: `PumpGlyphSlicer.swift:175-186` (`retried`), `:305-317` (`inkMassUniformity` =
  mean/(mean+std) of run ink masses).
- Evidence, structural: the retry fires when `pass.count < grid` where `grid = round(width /
  pitch)` - width INCLUDES both strip margins, so `grid` exceeds the glyph count on essentially
  every window and the "second pass at half threshold" is really "always run both passes". The
  tie-break then prefers whichever pass has more UNIFORM run masses - but a correctly-recovered
  faint glyph has less ink mass than its bold neighbours, so the criterion systematically prefers
  the pass that missed it, and a half-threshold pass mops up glare/bloom runs (scheidt's 16
  over-counts are consistent with this).
- Proposal: until F3's likelihood scoring exists, make the retry what its name says - fire only
  when the count is implausibly short against a band-height-derived digit-count prior - and drop
  or invert the uniformity criterion (a recovered-faint pass should not lose for being
  non-uniform). Under F3 the retry disappears entirely: it is a two-candidate special case of
  candidate-grid search.
- Measured by: the per-seam ablation table F3 asks for (this seam's row), then the count ratchet.

### F8. The training cell and the real cell are not the same shape: 26.7 % aspect overlap, systematic horizontal squish

**Area 3 [coord PU.12]. Effort: days (renderer-side change + one 650-s retrain). Expected gain:
unknown but precedent says large - a framing-only change moved per-glyph by a third once
(0.170 → 0.105, `REPORT.md:227-241`) and PU.9's framing fix doubled it (0.105 → 0.215).**

- Concerns: `dataset.py:256-270` (`render_slicer_cell`: crop is `pitch_px x band_h` with
  `pitch_px = pitch x CELL_W = 1.15-1.55 x 32 = 37-50 px`, band ~40 px, so crop aspect
  **0.92-1.24**), vs the real cells the slicer emits (pitch x bandHeight on the 96-px strip).
- Evidence: measured pixel aspect (w/h) of all 2127 real cells from `slices.json` + the annotated
  quads: **median 0.68, p25 0.45, p75 0.97, p5 0.27, p95 1.30**. Only **26.7 %** of real cells
  fall inside the training band 0.92-1.24; 1448 cells are narrower than anything the model has
  ever seen. Root cause: the renderer applies the profile's pitch multiplier to `CELL_W` (32, the
  glyph canvas WITH margins) while a real display's pitch is ~1.2-1.5 x the glyph BODY (~0.5-0.6
  of band height) - the same ratio, applied to different bases, ~1.6x apart. Every real glyph
  arrives horizontally squished relative to training.
- Second seam in the same crop: the BAND. Swift's band is rows above `0.15 x max(rowSum)`
  (`PumpGlyphSlicer.swift:146-152`) - it includes glare and halo rows; the training mirror
  (`dataset.py:206-223`) uses the exact lit-pixel extent at the on/ground midpoint. Real cells
  therefore carry background rows the training cells never do, and the glyph occupies a smaller
  vertical fraction of the cell.
- Proposal: the cheap version is to sample the training crop aspect from the measured real
  distribution and match the band definition; the right version is F9 (stop imitating the slicer,
  run it). **[coord PU.12]** owns the render-side pixels; the aspect/band NUMBERS above are the
  contract side and belong to a shared golden test.
- Measured by: "held-out per-glyph (cc)" in REPORT.md; also re-run the aspect overlap stat as a
  contract check (target ~100 %).

### F9. Make the Swift slicer itself produce the training cells - the imitation has already drifted twice

**Area 3. Effort: ~a week (a harness mode + CI plumbing + one retrain). Expected gain: every seam
in F5/F8 and six more become equal-by-construction instead of equal-by-luck; this is the only fix
that STAYS fixed.**

- Concerns: the whole contract. The Swift slicer cuts real cells (`PumpReaderHarnessTests` writes
  `slices.json`); `dataset.py:render_slicer_cell` IMITATES the geometry analytically. Full list of
  places they can (and measurably do) disagree:
  1. strip height 96 vs 48 vs ~40 (F5, measured: 2 points);
  2. crop aspect 0.92-1.24 vs median 0.68 (F8, measured: 26.7 % overlap);
  3. band definition: 0.15-of-row-max vs exact lit extent (F8);
  4. luma: `0.299/0.587/0.114` (`PumpQuadWarp.swift:29`) vs plain RGB mean (`dataset.py:215`) -
     different band trims for coloured displays;
  5. resampling/aliasing: Swift's warp is a hand-rolled bilinear POINT sampler from
     full-resolution pixels (`PumpQuadWarp.swift:225-248`) - no antialiasing while decimating a
     ~12-MP photo to a 96-px strip; PIL's `transform(BILINEAR)` (`score.py:126-128`) also does
     not antialias; the training renderer never aliases at all. Three different resamplers, one
     contract, no test comparing any pair;
  6. colour management: ImageIO/CGContext DeviceRGB decode (`PumpQuadWarp.swift:63-70, 206-223`)
     vs PIL/pillow-heif raw values (`score.py:177-180`) - P3 HEICs can land in different RGB
     spaces in the two halves;
  7. out-of-quad fill: black in both warps (`PumpQuadWarp.swift:228-230`, `score.py` `fillcolor=0`)
     while the augmentation warp clamps to the edge on purpose (`augment.py:77-79` - "a real warp
     of a display window never has a black corner"); with +-1 % annotation error, inference cells
     can carry black wedges training cells never do;
  8. dp placement inside-glyph vs in-gap (F2);
  9. grid phase: run-end circular mean vs the training `lead ~ U(0.2, 0.8) x slack` guess
     (`dataset.py:261-263`);
  10. cell rect quantisation: float grid at 96 px → normalised → re-rounded at 48 px (F5).
- Proposal: PU.9's own brief already offered this option ("or by reading `slices.json`-style rects
  the Swift harness writes for synthetic rows") and the imitation was built instead. Invert it:
  render synthetic rows in Python → a Swift harness mode slices them exactly as it slices real
  strips → emits rects → Python crops the cells from the same PNGs with the SAME resampler
  `score.py` uses at the SAME strip height. Training then consumes the slicer's real behaviour
  including its bugs (which is the point: the model learns to read what the slicer actually
  hands over, and a slicer fix automatically changes the training distribution). A golden-vector
  test pins both sides; PU.9's analytic mirror survives only as a fast pre-render path if needed.
- Measured by: "held-out per-glyph (cc)" after a same-recipe retrain (PU.9's precedent: framing
  alone doubled it); the seam list above shrinks to zero entries with a test per seam.

### F10. Training spends 16 % of its label mass on two classes the real scorer never contains, while the real distribution's heavy cells are under-served

**Area 2/3 [coord PU.12]. Effort: hours (prior constants) + retrain. Expected gain: modest but
free; mostly it stops the dp-only class from competing with the dp BIT (F2).**

- Concerns: `dataset.py:65-66` (`BLANK_PRIOR 0.08`, `DP_ONLY_PRIOR 0.08`), `dataset.py:138-146`.
- Evidence: annotated truth has 0 spaces in 433 windows; `parse_cells` never emits dp-only except
  in an unreachable-in-practice branch (`score.py:41-59`); the slicer's blank cells occur only in
  count-wrong windows, which cc-scoring excludes. Meanwhile `0` is 19 % of real cells (218/1139
  in the dump) and dp-carrying cells 21 % (244/1139). The 12-class render draws blank/dp-only
  uniformly-ish; the real cell distribution is digit-heavy, `0`-heavy, dp-heavy.
- Proposal: set BLANK_PRIOR ~0.02 (keep a floor - the decoder may feed margin cells),
  DP_ONLY_PRIOR 0 unless F2's re-render makes dp-only cells a real slicer output; re-weight dp=1
  among digit samples toward the real ~21 %. **[coord PU.12 #3]** owns the full sampling-distribution
  comparison; this finding is the two classes that are provably dead weight against the oracle.
- Measured by: per-class dp accuracy (F2's conditional number) and `0` recall in REPORT.md's
  per-segment table.

### F11. The model is confidently wrong on real cells: its likelihood margin barely ranks errors, so NO abstention policy on the current outputs can reach the 0.99 gate

**Area 2/4. Effort: the measurement is free (done); the fix is F12 + retraining. Expected gain:
this is the finding that decides whether PU.5 can ship at all - precision 0.99 on committed fields
requires an abstention signal that ranks.**

- Concerns: `model.py:27-46` (3 conv blocks → GAP → 8 logits), `train.py:114`
  (`BCEWithLogitsLoss`), and the future PU.5 commit rule.
- Evidence: sorting the 1169 count-correct real cells by the F1 decode's log-likelihood margin
  (best minus second-best digit): digit accuracy is **0.763 at 30 % coverage, 0.777 at 50 %,
  0.714 at 70 %, 0.674 at 80 %, 0.640 at 90 %, 0.612 at 100 %** - a nearly flat curve with a
  median margin of 4.0 nats. The model assigns near-probability-1 to wrong digits on real cells:
  the same failure class as Vision's confidence-1.00 `9`-as-`4` on `pump-004`, which is the reason
  this reader exists (`docs/EXTRACTION.md:785-790`). Cause: BCE on synthetic data saturates the
  logits (synthetic val loss 0.013), and nothing in training ever showed the model a real-domain
  cell, so OOD inputs land in confident regions.
- Proposals, in order:
  1. **TTA-disagreement as the ranking signal** (cheap, no retrain): classify each cell at
     +-1-2 px horizontal/vertical offsets and average; the SPREAD across crops is a domain-robust
     uncertainty (a misframed or faint glyph wobbles, a clean one does not). Measure the same
     coverage curve with TTA-spread as the ranker; if it bends where the margin does not, PU.5's
     commit rule ranks on it. Cost on-device: 5 forward passes of a 64-KB model per cell - trivial.
  2. **Multi-task digit head** (F12) with softmax CE - softmax over mutually exclusive classes is
     structurally better calibrated for ranking than independent saturated sigmoids.
  3. Label smoothing / logit-norm during training so the synthetic-easy cells stop at ~0.9 instead
     of ~1.0 - keeps margins in a discriminative range. One-line ablation.
  4. An ensemble of 2-3 seeds (each ~64 KB; the 500-KB budget allows 7) - disagreement between
     seeds is another real-domain uncertainty source; measure the coverage curve per option and
     ship the cheapest one that bends.
- Measured by: the precision-coverage frontier F4(c) asks the scorer to print; the gate question
  is literally "does any t give precision >= 0.99 at coverage >= 0.60" - today the answer is no,
  and this finding is why "train a better model" without a calibration story cannot ship PU.5.

### F12. Keep the 8 sigmoids (design law) but add a multi-task digit head, and give the segments spatial evidence instead of GAP

**Area 2. Effort: ~2 days per ablation (train 650 s + score). Expected gain: fewer `?`-class joint
inconsistencies, a calibrated ranking head for F11, and per-segment evidence that survives
position jitter.**

- Concerns: `model.py:43-46` (`x.mean(dim=(2,3))` - global average pooling destroys WHERE each
  segment fired, which is the entire seven-segment signal), `model.py:41` (`Linear(64, 8)`).
- Is 8 independent sigmoids the right head? As the ONLY head, no: the bits are decoded jointly
  (F1) but trained marginally, and 25.5 % of real cells land on joint patterns no display can
  show. As the INTERFACE, yes - it is the design law (`docs/EXTRACTION.md:798-802`) and what makes
  repair composition work (F13).
- Proposals (all keep the 8-sigmoid output contract; the model is ~100 k params against a ~125 k
  budget, `model.py:9`, so there is room):
  1. **Add an 11-class softmax head** (10 digits + blank; dp stays its own sigmoid) sharing the
     backbone, trained with CE alongside BCE. Decode = product of experts: softmax head x pattern
     likelihood over the 8 bits. This enforces whole-glyph consistency (a `9` with uncertain `e`
     gets `4` mass from the softmax, not a `?`), and the softmax is the natural calibrated ranker
     for F11. Export both outputs (FLOAT32 please - `REPORT.md:333-335` already flags the
     FLOAT16 downcast; posteriors that drive a 0.99 gate deserve the precision).
  2. **Replace GAP+Linear with 8 segment heatmaps**: a 1x1 conv to 8 channels at the 4x6 feature
     resolution; each segment's logit = max-pool within its canonical region (the regions are
     known geometry, `glyph.py:155-179`). Segment decisions become spatially inspectable (which
     blob fired for `g`), tolerate the +-jitter the slicer's phase produces, and the dp gets its
     own corner region matched to where real dots sit (F2). Same parameter order of magnitude.
  3. Grayscale input ablation: the digit is carried by geometry; colour is a palette/domain-shift
     liability (ICC seams in F9, six LCD families in training vs real white balance). One 650-s
     run answers it. If grayscale matches synthetic and beats RGB on real, adopt it (export
     contract change: `export.py:61-67`).
  4. Larger input ablation (40x64 or 48x64): F5 shows real cells carry detail 32x48 does not
     preserve (96-px strip scored +2 points); first conv grows ~1.5x, still far under budget.
  - Per-segment attention: not worth its complexity given (2) achieves the spatial prior for free
    with known geometry - attention would have to relearn what `glyph.py` already states.
- Measured by: per-glyph cc under F1 decoding (0.646 is the bar to beat), `?`-rate (25.5 % today),
  F11's coverage curve, per-segment table in REPORT.md (b 0.785 is the weakest today).

### F13. The PU.5 decoder sketch: cell count is the external pin the cloud model never had - arithmetic decimal recovery fixes the pump-009 class BY CONSTRUCTION

**Area 5. Effort: this is PU.5 itself; the sketch below is what the classifier must output for it
to work.**

- Concerns: PU.5 (`docs/TASKS.md:965`), `PumpExtractor.swift:354` (`solve` - the uniqueness rule
  already exists and is trap-tested), `DigitRepair.swift:61-69` (the fixed confusion table PU.5
  replaces).
- What the classifier must output per cell (contract for PU.5): the 8 raw probabilities; the F1
  ranked list of (digit | blank, log-posterior) over valid patterns - top-3 suffices; a dp
  probability with the F2 caveat that until the re-render lands it carries no information (AUC
  0.52) and must be treated as a hint, never a constraint; and the F11 uncertainty rank
  (TTA-spread or head margin) per cell.
- Decode pipeline:
  1. **Row assignment**: windows arrive as separate strips already; assign total/volume/price by
     layout (display order in the annotation is the oracle's convention; on-device it comes from
     the locator's window geometry) plus the price band (`FuelPriceBand` exists) and the volume
     range - the same priors `PumpExtractor.solve` uses.
  2. **Field candidates**: beam over per-cell top-k (k <= 3), pruned by band/range. Crucially, the
     field's DIGIT COUNT is the cell count - fixed by the slicer, not guessed.
  3. **Decimal recovery**: for each field candidate string, enumerate decimal placements
     consistent with the field type (volume 2 decimals, price up to 3, total 2; KZT fixtures show
     comma-zero conventions - `parse_cells` already treats `,` and `.` alike). Search
     `volume x price = total` at the exact cent (`solve`'s ground 1, `PumpExtractor.swift:366-375`):
     **unique solution → commit; two or more → nil, never a guess.** The pump-009 failure
     (`40.00 / 50.95 / 2038.00` read as `400.0 / 50.95 / 20380.0`) shifted TWO fields together
     because the cross-check is scale-invariant - but the trained reader knows each field's digit
     count from its cells. A shift that preserves the product requires changing digit counts,
     which the cells forbid. The factor-of-ten class dies at the architecture, not at a check.
     Optical dp (when F2 lands) prunes placements before the search; arithmetic remains the
     authority because dp is the bit with the worst real-domain record.
  4. **Repair**: replace the fixed 7-pair table with per-cell posterior ordering - for each cell
     in each candidate field, alternatives are the digits within Hamming <= 2 of the observed
     pattern, ranked by pattern posterior; accept only when EXACTLY ONE single-cell substitution
     closes the arithmetic (keep `DigitRepair`'s uniqueness law, `:98-110` - the two-candidate
     refusal is the half that keeps this from inventing digits). Justification from real data:
     the measured confusion mass includes pairs the fixed table lacks (`4↔1`: 6, `0↔7`: 7,
     `8↔2`: 4 in the cells-r2 dump) and the fixed pairs are a subset of the learned ones.
  5. **Commit vs suggest**: a field commits (counts toward gate coverage) only on a unique
     arithmetic solution with every cell's uncertainty above the F11-calibrated threshold;
     everything else flows to `FuelExtraction` as nil-or-suggestion per hard rule 13, with
     `digitRepair` provenance as today.
- Measured by: the F4(c) gate-mirror numbers - precision/coverage/confident-wrong on the 320-cell
  denominator; the four named traps (`pump-004/009/013/015`) at zero confident-wrong.

### F14. The locator (median IoU 0.008) blocks any end-to-end claim, and polishing classical CV is the wrong investment

**Area 1-adjacent (it feeds the slicer). Effort: the proposal is days, not weeks. Expected gain:
without it PU.5 scores on oracle quads only and PU.6 cannot make a ship decision about the real
product.**

- Concerns: `PumpPanelLocator.swift:19-93` (contrast mask + row bands; its own comment says
  "deliberately not polished"), harness floors at 0.0 (`PumpReaderHarnessTests.swift:36`,
  `:137-160`).
- The corpus already proved the classical approach does not transfer: best IoU 0.61 on exactly one
  clean straight-on fixture (`pump-078`), median 0.008.
- Options in cost order:
  1. **Vision as a region PROPOSER only**: `VNRecognizeTextRequest` boxes (not strings) over the
     photo; every box becomes a candidate window for warp→slice→classify, and the reader's own
     likelihood (F1/F11) decides which candidates are displays. This keeps the design law intact -
     OCR proposes, the segment reader disposes; P4.12 showed Vision FINDS pump numbers even where
     it misreads them. Measured against the existing oracle exactly as `locatorCorpusMedianIoU`
     does today.
  2. **User-tapped crop** as the rule-15 peer path: two taps to frame the display always works,
     needs no model, and converts locator IoU from a ship blocker into a convenience metric. This
     is a product decision (question Q6 below).
  3. A learned detector last: it needs real backgrounds, and the held-out corpus cannot train
     them - the only honest training set is synthetic panels composited onto photos we do not
     have. Do not start here.
- No open row owns the locator past PU.4's partial; PU.6 should file from the measurement.

## Direct answers to the review's five questions

1. **The slicer.** Column projection stays, as a hypothesis generator (F3). The four PU.8 seams:
   none is individually measured - run the per-seam ablation (flags exist, table missing); my
   structural read: Otsu + LCN load-bearing for the faint under-counts (wayne 38, gilbarco 37),
   splitMerge double-edged (fixes glare splits, can merge thin faint pairs), shortCountRetry
   actively harmful as wired (F7: fires nearly always, criterion punishes faint recovery). The
   single highest-value change is candidate grids scored by classifier likelihood (F3), then
   leading-blank deletion (F6), then phase-by-valley-energy and harmonic-consistent pitch
   (F3.1, kills the half/double-pitch locks visible in scheidt's over-counts and the +80-cell
   tail).
2. **The classifier.** Keep 8 sigmoids as the interface; add an 11-class softmax head (product of
   experts decode) and replace GAP with per-segment heatmap pooling over canonical regions (F12).
   BCE + 0.5 thresholding is the WRONG decoder - measured: constrained pattern decoding is worth
   +25 glyph points with zero retraining (F1) - and BCE saturation plus synthetic-only training
   makes the raw margin useless for abstention (F11, the flat coverage curve), which the
   arithmetic cross-check cannot substitute for because the cross-check needs RANKED candidates
   to search. Grayscale and larger input are cheap ablations with real upside (F5, F12.3-4);
   attention is not worth it against known geometry.
3. **The framing contract.** Ten enumerated disagreement points, three of them measured (strip
   height: 2 points; crop aspect: 26.7 % overlap; band definition) - F5, F8, F9. The durable fix
   is to delete the imitation: Swift slices synthetic rows, Python crops what Swift sliced, one
   strip height, one resampler, golden vectors per seam (F9).
4. **The scorer.** Per-window-everything is a diagnostic, not the gate unit; "committed field" =
   the PU.5 decoder emitted non-nil for a transaction numeric cell (F4c). Fix the prefix-zip and
   dump-collision defects (F4a/b), count the 23 unreadable windows as abstentions, print the
   precision-coverage frontier and the confident-wrong list, commit `by_name` (F4d).
5. **The decoding.** Sketched in F13: ranked per-cell candidates → fixed digit count per field →
   decimal placement as the unique `volume x price = total` solution (reusing `solve`'s uniqueness
   law) → posterior-ordered repair replacing the fixed table → commit only on uniqueness plus a
   calibrated threshold. Cell count as the external scale pin kills the pump-009 factor-of-ten
   class by construction.

## What I would need to know or have (ranked)

1. **Video or burst capture at inference (Q: does the J4 capture flow allow N frames?).** The
   flat confidence curve (F11) is the single biggest threat to the 0.99 gate, and temporal
   median over 3-5 frames attacks it from the data side: glare and reflections move, digits do
   not; sub-pixel jitter averages away aliasing (F9 seam 5); dp dots survive frame averaging
   better than single-shot 48-px warps. If burst is available, every uncertainty story in this
   review gets easier, and TTA (F11.1) becomes free (crops from different frames instead of
   synthetic offsets).
2. **Glyph-level annotations for ~30 fixtures (cell rects + segment bits + dp flags), as a
   DEVELOPMENT set separate from `windows.json`.** Today every slicer change is scored by count
   agreement against window strings - a proxy that conflates pitch, phase, band and ink failures
   and cannot tell F3's candidate search where it went wrong. There is no cell-rect ground truth
   anywhere, so the per-seam ablation F3 asks for still measures outcomes, not mechanisms. This
   does not violate the held-out law if it stays measurement-only (like `windows.json` itself);
   a second annotator for the same 30 would also give an annotation-error floor, which nobody has
   measured (the +-1 % quad precision is stated, the string precision is assumed).
3. **A display-glass make column per fixture.** The per-make table's tokens are station brands,
   not glass: `circlek`, `lukoil`, `gpn`, `rn`, `topaz`, `kz` are fuel brands; `adast` appears in
   a filename (`pump-006-kz-adast-92-kzt`) but not in `PROFILES`; the renderer's five profiles
   cannot be checked against makes nobody recorded. Scheidt's unique over-count signature (F3)
   and wayne's under-count signature are only actionable if we know what glass they are. Cheap:
   one column in `expected.csv` or `windows.json`'s `_about`, filled from the photos' visible
   branding.
4. **The capture geometry the product will actually produce.** Full pump or display close-up?
   Distance/angle distribution? This decides F14: a close-up display shot makes Vision region
   proposals nearly free; a full-pump shot at 3 m makes the locator the hardest problem in the
   pipeline and argues for the user-tapped crop (Q6). The corpus's own shooting conditions are
   the training distribution's ceiling.
5. **Night / reflection-heavy samples per make, and the phone's raw pipeline.** Wayne's 38
   under-counts: is that faint glass in daylight or night shots with collapsed contrast? And are
   the fixture JPEGs/HEICs sharpened (unsharp halos interact with Otsu, LCN and 1-2-px dp dots)?
   If the app can capture with reduced sharpening or raw-ish frames, both the slicer and the dp
   detector gain signal no render can simulate; if not, **[coord PU.12]** should add sharpening
   halos to augmentation.
6. **A product decision: is a two-tap display crop an acceptable v1 locator?** (Hard rule 15 says
   manual is a peer path; a tap-to-frame crop is honest, always works, and unblocks PU.5/PU.6
   from the 0.008-IoU stub.) If yes, F14.1 (Vision proposer) becomes an enhancement, not a
   blocker; if no, the locator needs its own row before PU.5 can score end-to-end.
7. **Per-make field-width conventions.** Are transaction fields fixed-width zero-padded per make
   (Gilbarco RU heads show `00040,00`)? If the digit count per field is a make-level constant,
   the decoder (F13) gains a prior that catches slicer count errors arithmetically - and F6's
   padding discussion gets a definitive answer. The measurement I could make says padded zeros
   are visible ink (padded and unpadded windows agree on count equally, 0.59 vs 0.60), but only a
   make column (Q3) turns that into a usable convention.
8. **Rulings on the three declared corpus exceptions** (`pump-031` CSV-vs-display 32.50/32.58,
   `pump-072` loyalty price not on the board, `pump-067` glare-illegible total) as gate
   denominators: PU.6's precision math needs to know whether these count as committed-wrong,
   abstentions, or excluded - the scorer today silently includes them.

## Checks run (observed exit codes and counts)

| check | exit | observed |
|---|---|---|
| `swift test --filter PumpReaderHarnessTests.slicerRatchet` | 0 | 1 test, 107.1 s; count 259/433 (0.598), dp 1/422, per-make table as quoted |
| `.venv/bin/pytest -q` (ml/pump-reader) | 0 | 21 passed |
| inline replay of `score.py` math on the shipped checkpoint + committed `slices.json` | 0 | per-glyph cc 0.3995 (467/1169) - reproduces REPORT.md's 0.400 |
| inline F1 decode ablation | 0 | nearest-pattern per-glyph 0.6459; digit-only windows 76/259 vs exact 1/259 |
| inline dp AUC | 0 | AUC 0.520 (n1=255, n0=914); mean prob 0.137 vs 0.126 |
| inline strip-height ablation | 0 | 48 px 0.3995 / 96 px 0.4200 / 144 px 0.4175 |
| inline aspect census over `slices.json` + `windows.json` quads | 0 | 2127 cells; median w/h 0.68; 26.7 % inside the training band 0.92-1.24 |
| inline count-delta census | 0 | under 129 / exact 259 / over 45; 490 blank cells; 14 over-windows all-leading-blank; 0 leading spaces in truth |
| inline margin coverage curve | 0 | 0.763@30 % → 0.612@100 %; median margin 4.0 nats |
| inline padding correlation | 0 | padded exact 0.59 vs unpadded 0.60 (dim-padding hypothesis rejected) |

The inline analyses load the committed checkpoint and the committed slicer output and write
nothing; recipes are the code paths named in each finding (`score.py` functions, `slices.json`,
`windows.json`, `.out/cells-r2` filenames). The harness re-run regenerated
`ios/.build/pump-reader-out/` exactly as any harness run does (deterministic slicer, same code;
count agreement unchanged at 259/433). No fixture, gate, or Corpus file was touched. No training
was run.

## Found and not fixed (this review writes no code)

| finding | owner |
|---|---|
| F1 constrained decode | none - file under PU.5's decoder or a new row |
| F2 dp dead end-to-end | PU.5 (arithmetic), PU.12 (render placement); the strip-level gap detector has NO row - file |
| F3 candidate-grid slicer + per-seam ablation table | none - PU.8 closed; file (PU.6 files from measurement per its own text) |
| F4a prefix-zip, F4b dump collision, F4d uncommitted `by_name` | none - file against `score.py` |
| F4c gate-mirror field scoring | PU.6 needs it; file |
| F5 strip-height contract + golden vectors | none - file with F9 |
| F6 leading-blank emission | none - file (one-line scale) |
| F7 retry trigger + uniformity criterion | folds into F3's row |
| F8/F9/F10 framing contract, Swift-side cell generation, dead class priors | **[coord PU.12]** items 1/3/4 own the render side; the Swift harness mode and golden tests have no row - file |
| F11 calibration/abstention | none - file; PU.5 cannot hit its gate without it |
| F12 head/architecture ablations | none - file; PU.10's "not training" verdict covers step count, not head structure |
| F14 locator | none past PU.4's partial - PU.6 files from measurement; Q6 is a product decision |
| Sibling-defect note | the black out-of-quad fill (`PumpQuadWarp.swift:228-230`, `score.py` `fillcolor=0`) contradicts the augmentation's own clamp-to-edge rule (`augment.py:77-79`): same seam (warp fill), two decisions - fold into F9's contract row rather than fixing one half |

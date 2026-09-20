# PU.9 - train on the slicer's own framing

`dataset.py` gains a second cell renderer, `framing="slicer"` (the new default):
it draws a short row of 1-2 digit neighbours either side of the target, then
cuts the cell the way `PumpGlyphSlicer` hands it over - horizontally the
target's own tight box (one glyph wide), vertically the whole row's ink band
(top of the highest lit pixel to the bottom of the lowest, no vertical margin),
with x/y jitter, resized to 32x48 with the same `BILINEAR` resampling `score.py`
uses. `framing="glyph"` keeps the lone-glyph renderer with its crop jitter, so
the ablation can re-run it (`train.py --framing`). `SegmentNet` is untouched,
so the before/after isolates the data framing.

## Training

`python -m pump_reader.train --steps 6000 --seed 0 --out .out/train-pu9-slicer`

- Wall time **248.3 s**. Final validation: **per-segment 0.9837**, per-digit
  0.8894 (up from the shipped recipe's 0.965 / 0.781 - the tight, full-height
  cells are easier to read than the margin-carrying lone glyphs).
- Committed metrics: `runs/2026-09-19/metrics-pu9.json`.

## Export

64 KB `.mlpackage` to `ios/App/Resources/PumpSegments.mlpackage` (same size as
PU.3/PU.7).

## Held-out score

Scored with `--boxes ../../ios/.build/pump-reader-out/slices.json` (433 all
windows, then the 259 count-correct subset). The before is the shipped recipe
on the same anchored grid (REPORT.md below, "The shipped recipe").

| model | all 433 per-glyph | count-correct (259) per-glyph | dp bit (cc) |
|---|---|---|---|
| before (shipped) | 0.0910 | 0.1052 | 0.7331 |
| after (PU.9 slicer framing) | **0.1774** | **0.2147** | 0.7425 |

**Training on the slicer's own framing more than doubles held-out per-glyph
accuracy** (0.105 -> 0.215 count-correct, 0.091 -> 0.177 all). This confirms
the PU.8 finding: the classifier was not weak, it was being fed cells it had
never seen. The dp bit reads at 0.7425 on the count-correct windows (0.7345 all),
essentially unchanged from the shipped 0.7331.

## Tests

20 passed (18 existing + `test_framing.py`). New: a slicer-framed `8` has lit
pixels within 2 px of both canvas edges (oracle: the band trim) and a `1`'s lit
columns land in the right half (oracle: the segment geometry b/c), each 300
samples at >= 95 %. Named mutation: replacing the ink-band y-crop with the full
row height sends `test_slicer_framing_8_touches_top_and_bottom` red (300/300).

## Found and not fixed

- **`pump-004` still reads wrong.** The framing win is broad (dp unchanged,
  d/g still the weakest segments at ~0.59/0.58 on count-correct) but the
  per-fixture misses are not re-examined here; the next row should look at the
  remaining wrong cells on the anchored grid, not the aggregate.

---

# PU.7 - make the renders look like the corpus, then retrain

Four render changes close the four gaps the PU.4 cell sheet showed, then a
6000-step retrain of `SegmentNet` (same recipe as PU.3) and re-scoring against
PU.4's slices. `SegmentNet` is untouched, so the before/after isolates the data.

## Changes

| gap | file | change |
|---|---|---|
| 1 bolder segments | `profiles.py` | gilbarco `segment_ratio` (6.5, 8.5) -> (3.5, 6.0); dresser stays 8.0-10.0 as the thin profile |
| 2 neighbour spill | `dataset.py` | `SPILL_PROB` 0.4; `render_cell` draws a neighbour on each side (advance `CELL_W - (MARGIN + 2)`) and crops the centre cell via `render_row_of_labels` |
| 3 faint / low-contrast | `augment.py` | `apply_contrast_collapse` (15% of samples to 10-25% of the original on/ground difference) + `apply_reflection` (broad soft blob) |
| 4 italic slant | `profiles.py` | gilbarco/wayne `slant_deg` -> (6.0, 12.0); `_hseg`/`_vseg` already had chamfered ends, no change |

## Training

`python -m pump_reader.train --steps 6000 --seed 0 --out .out/train-2026-09-19-pu7b`

- Wall time **234.5 s**. Final validation: **per-segment 0.9259**, per-digit
  0.6298 (down from PU.3's 0.9689 / 0.8062 - the harder data is harder to fit).
- Committed metrics: `runs/2026-09-19/metrics-pu7.json` (kept alongside PU.3's
  `metrics.json`; a second run on the same date must not clobber it).

## Export

64 KB `.mlpackage` to `ios/App/Resources/PumpSegments.mlpackage`, same size as
PU.3's.

## Held-out score

Scored with `--boxes ../../ios/.build/pump-reader-out/slices.json` (all windows,
then the count-correct subset with the new `--only-count-correct` flag). The
concurrent PU.4 agent regenerated `slices.json` mid-run, so the count-correct
subset is now **245** windows, not PU.4's 173; the before is re-measured on the
same regenerated file.

| model | all windows (433) per-glyph | count-correct (245) per-glyph |
|---|---|---|
| before (PU.3) | 0.1012 | 0.1278 |
| after (PU.7, all four gaps) | 0.0688 | 0.0864 |

**The four changes together moved held-out down, not up.** An ablation isolates
why (6000 steps, count-correct subset, same slices):

| config | count-correct per-glyph |
|---|---|
| bold only | 0.1737 |
| bold + slant | 0.1701 |
| slant only | 0.1530 |
| all four | 0.0864 |

Bold and slant each improve held-out (0.128 -> ~0.17); neighbour spill and
contrast collapse - both real on the corpus, where 74% of count-correct cells
carry margin ink - drag it back down to 0.086. The spill/contrast code and tests
are in place, but they do not currently help, and the synthetic >= 0.95 gate is
only met without them (bold+slant 0.964 vs all-four 0.926).

## Tests

18 passed. New: `test_dataset_spill.py` (spill puts neighbour ink in the left
margin at `SPILL_PROB`; centre label unchanged) and `test_contrast.py` (collapse
lands <= 25% of original contrast). Named mutation: `SPILL_PROB -> 0` sends
`test_dataset_spill` red.

## Found and not fixed

- **Spill and contrast collapse hurt held-out.** Implemented and tested per the
  brief, but the before/after is a regression and the ablation says bold + slant
  alone reach 0.170. This contradicts the brief's diagnosis (gaps 2 and 3) and
  needs a product-owner decision before the final config is picked.
- **`slices.json` is a moving target.** The concurrent PU.4 agent regenerated it
  mid-run (173 -> 245 count-correct windows), so the brief's "0.175 on 173"
  reference no longer reproduces and the before had to be re-measured.
- **`score.py` printed `missing fixture _about`** to stdout for the `_about`
  metadata key (it is not a fixture); fixed by skipping that key.

---

# PU.3 - the segment classifier

Training, export and held-out scoring of `SegmentNet`, a small CNN that reads a
32x48 pump-display glyph and returns 8 sigmoid probabilities (segments a-g plus
the decimal point). The digit is a lookup over the thresholded bits, never a
stored class, so a `9` whose segment `e` is uncertain is a `4` *candidate*, not a
confident wrong digit (`docs/EXTRACTION.md` -> "The pump reader").

## Files

| File | What |
|---|---|
| `src/pump_reader/dataset.py` | `SyntheticDataset`: on-the-fly PU.1 renders, technology sampled independently of make (LCD .6 / LED .3 / VFD .1), blank/dp-only floors, crop jitter |
| `src/pump_reader/model.py` | `SegmentNet`: 3 conv blocks (16/32/64, BN, ReLU, 2x2 pool) -> GAP -> 8 logits |
| `src/pump_reader/train.py` | `python -m pump_reader.train --steps N --seed S --out DIR`; AdamW + cosine, logs per-segment/per-digit every 200 steps |
| `src/pump_reader/export.py` | `python -m pump_reader.export`; coremltools ML Program, sigmoid in the graph |
| `src/pump_reader/score.py` | `python -m pump_reader.score`; the one place the corpus is touched, measurement only |
| `tests/test_dataset.py` | 1000 samples: every make + technology, class floor, tensor bounds/shape |
| `tests/test_model.py` | forward shape (4,8), params < 130k |
| `tests/test_train_smoke.py` | `--smoke` writes checkpoint + metrics, final loss < initial |
| `tests/test_export_roundtrip.py` | torch vs Core ML on an `8` render, within 1e-3 |
| `tests/test_score_slicer.py` | slice cell count == glyph count, centres inside PU.1 boxes |

## Training

`python -m pump_reader.train --steps 6000 --seed 0 --out .out/train-2026-09-19`

- **Wall time: 264.3 s** on this machine (Apple Silicon, CPU only).
- Final validation (5 000 held-out synthetic samples, seed offset `1_000_000`):
  - **per-segment accuracy: 0.9689**
  - **per-digit accuracy (all 8 bits right): 0.8062**
  - per bit: a .9854, b .9422, c .9734, d .9918, e .9714, f .9788, g .9876, **dp .9204**

The committed metrics are `ml/pump-reader/runs/2026-09-19/metrics.json` (metrics
only; the checkpoint lives in `.out/`, which is gitignored).

## Export

`python -m pump_reader.export --checkpoint .out/train-2026-09-19/segmentnet.pt --out ios/App/Resources/PumpSegments.mlpackage`

- **Size: 64 KB** (48 KB weights), well under the 500 KB target.
- Input `glyph`: image, 32x48 RGB, scale 1/255 (so Core ML feeds the `[0,1]`
  floats the model was trained on).
- Output `segments`: multiArray **shape `[1, 8]`, dtype FLOAT16** (Core ML's ML
  Program downcasts the output; roundtrip still agrees with torch within 1e-3).
  Order **a b c d e f g dp**, each in `[0,1]`.
- Metadata: `author = "Tankbook"`, `short_description` names the segment order,
  `version = f096132d` (git short sha).

## Held-out score

Run by the orchestrator on 2026-09-19 once PU.2's `windows.json` landed (114
fixtures, 433 non-empty windows scored, 23 unreadable windows skipped):

```
per-segment mean 0.596   per-glyph 0.123   per-window 0.000
per-segment: a 0.485  b 0.636  c 0.656  d 0.465  e 0.700  f 0.533  g 0.541  dp 0.751
```

`runs/2026-09-19/held-out-score.json` holds the full table; `held-out-cells.png`
shows what the scorer fed the model for six fixtures, and it is the diagnosis:
**the naive equal-width slicer, not the classifier, is what this number
measures.** The annotated quads carry a margin, a leading blank cell is not the
same width as a digit cell, and on Gilbarco heads the comma sits in its own
narrow cell - so most cells straddle two glyphs. Where a cell happens to land on
one glyph (`0>0`, `8>8`, `9>9`, `3>3`, `4>4`, `6>6` on the sheet) the model
reads it right. This is exactly PU.4's job: a column-projection slicer that
finds the real glyph pitch. The per-glyph number above is the **before**; PU.4
re-runs this scorer with its slicer and records the after under the same row.

Two things the sheet says about the renders themselves, for PU.6: real LCD
glyphs are noticeably **bolder** (thicker segments relative to the cell) than
the `gilbarco` profile draws, and real cells carry the neighbouring glyph's
edge at both sides - the crop jitter should include horizontal spill from a
neighbour, not only a shift of the glyph itself.

### The shipped recipe (orchestrator, 2026-09-19, after PU.7 and PU.8)

The ablation above decided the recipe: **bold + slant on, neighbour spill and
contrast collapse off** (`train.py --spill-prob 0 --contrast-prob 0`, the
defaults; `runs/2026-09-19/metrics-pu7-final.json`, synthetic validation
per-segment 0.965 / per-digit 0.781). Exported to `PumpSegments.mlpackage`.

Scored on PU.8's slices, first with PU.8's grid (245 count-correct windows),
then after the grid was anchored on the first occupied cell (259 count-correct,
`held-out-cells-final.png`):

| slices | model | all 433 per-glyph | count-correct per-glyph |
|---|---|---|---|
| PU.8 grid (245 cc) | PU.3 | 0.1012 | 0.1278 |
| PU.8 grid (245 cc) | shipped | 0.1253 | **0.1701** |
| anchored grid (259 cc) | PU.3 | 0.0830 | 0.0975 |
| anchored grid (259 cc) | shipped | 0.0910 | 0.1052 |
| anchored grid (259 cc) | PU.9 slicer framing | **0.1774** | **0.2147** |

The anchored grid is right by inspection (the sheet) and wins 14 windows on
count, yet the classifier reads it WORSE - a framing change alone moves the
number by a third. That is the finding for the next row: the model is
sensitive to how a cell is framed (the slicer's cells are full-height and
tight on the pitch; PU.1's renders carry a margin), and the dataset has to be
built from the slicer's own framing. `pump-004`, `pump-009`, `pump-013`,
`pump-015` all still read wrong.

### Round 2 (orchestrator, 2026-09-19): the training material reviewed against the real cells

`runs/2026-09-19/train-sheet-before.png` is 96 samples of what the model was
actually trained on; `held-out-cells-final.png` is what it is asked to read.
Side by side, four defects, none of them a modelling question:

1. **The LCD ghost could be lighter than the ground.** Ghost, ground and ink were
   sampled from independent colour ranges, so an off segment often drew as a
   bright outline. A real ghost is a faint step from the ground toward the ink.
   Now derived from the sampled pair (`profiles.resolve`), `test_lcd_ghost.py`.
2. **The cell was one glyph wide, not one pitch wide.** PU.9 cut the target's
   tight box, so every training glyph ran edge to edge; a real slicer cell has
   the pitch's slack around the glyph and the neighbours' edges reaching in.
3. **One LCD palette** (pale mint) against a corpus of grey-blue, dark olive,
   yellow-green, white-blue and amber LCDs; and a technology prior of 40 % LED +
   VFD for a corpus that is nearly all LCD. Six palette families, prior 85/10/5.
4. **Augmentation far heavier than the corpus**: blur up to σ 1.5, a 2–6 px
   black bar on 30 % of samples, perspective with black corners. Tamed; the
   warp now clamps to the edge.

Same `SegmentNet`, same recipe otherwise:

| model | all 433 per-glyph | count-correct (259) per-glyph | dp bit (cc) |
|---|---|---|---|
| PU.9 | 0.177 | 0.215 | 0.74 |
| round 2, 6 000 steps | 0.293 | 0.387 | 0.75 |
| round 2, 15 000 steps / 120 k samples (**shipped**) | 0.309 | **0.400** | 0.74 |

Per-segment on count-correct cells: a 0.85 b 0.79 c 0.81 d 0.83 e 0.88 f 0.83
g 0.86. Doubling the steps bought 1.3 points, so the reader is limited by what
the renders still do not show, not by training. `held-out-cells-r2.png`: the
clean cells read right; what is left is the faint Wayne LCD (`pump-062`), the
washed-out `pump-004` (`3008` → `???8`), and the dp landing on the wrong
neighbour. Per-window is still ~0 because a window needs every glyph AND its
dp right.

### Round 3 (orchestrator, 2026-09-19): the decoder, from PU.11-REVIEW-IMPL F1

The scorer turned 8 sigmoids into a glyph by thresholding each bit at 0.5, so
117 of its 128 possible a-g outputs were patterns no display shows - a quarter
of all real reads were `?`. `decode_constrained` picks the most likely VALID
pattern (log-likelihood over the ten digits; blank is the slicer's call, not the
classifier's) and reports the margin to the runner-up. Same model, same slices:

| decoder | per-glyph (a-g + dp) | digit only (a-g) | windows with every digit right |
|---|---|---|---|
| per-bit threshold | 0.400 | 0.532 | 0.209 |
| constrained, blank allowed | 0.456 | 0.613 | 0.282 |
| constrained, digits only (**shipped**) | 0.477 | **0.666** | **0.321** |

(count-correct windows; all 433: digit only 0.411 → 0.539.) The dp bit is
unchanged and is what keeps per-window near zero - PU.11 F2: the dp bit has
AUC 0.52 on real cells, and PU.12 finding 3 says why (a dot in a corner where
real displays draw a comma below the baseline between cells).

### The headline is transaction fields only (product owner, 2026-09-19)

`score.py --fields` defaults to `total,liters,unitPrice`; the board is out of the gate. Same
model and decoder as round 3, 320 transaction windows (192 count-correct):

| | per-glyph | digit only | windows, every digit right |
|---|---|---|---|
| all 320 | 0.429 | 0.569 | 0.266 |
| count-correct 192 | 0.523 | **0.698** | **0.370** |

### Round 4 (PU.17 + PU.18): the comma drawn where displays draw it, cells calibrated on aggregate statistics, one strip resolution

`glyph.py` draws the decimal mark as a **comma** - a dot below the digit baseline
in the gap after the glyph, with a short tail whose rightmost ink crosses into the
next cell's left edge - using the dead `dp_offset_frac` plus a new vertical offset
(`dp_vertical_frac`, 0.05-0.15 x glyph height); LED heads keep the plain corner dot.
The row's ink band therefore includes the comma, so a dp-carrying cell has its digit
in the top ~85 %. The dp bit stays on the host glyph; a cell cut from the NEXT
position carries the tail at its left edge with dp = 0.

`calibrate.py` measures the corpus's aggregate geometry over transaction windows
only (`src/pump_reader/calibration.json`): cell aspect (pitch/band, p50 **0.875**),
the right-aligned phase, digit frequency, leading-zero runs, and dp presence rate
(0.206 overall, comma 52 % of decimal marks). `render_slicer_cell` samples its crop
aspect from those quantiles (band inflated, one-sided, never below the ink) and
right-aligns the crop to the segment ink, and the dataset samples dp at the
calibrated rate instead of 50/50. The Python renderer now draws on the 96-px strip
and downsampling the cell to 32x48 exactly as `score.py` (which now warps at 96 px
too, PU.11 F5). Same `SegmentNet`, same 15 000-step / 120 k-sample recipe, spill 0,
contrast 0:

| | per-glyph | digit only | windows, every digit right |
|---|---|---|---|
| all 320 | **0.451** | **0.585** | 0.263 |
| count-correct 192 | **0.558** | **0.717** | **0.370** |

dp bit on count-correct cells: accuracy **0.793** (was 0.74), AUC **0.548** (was
0.52, PU.11 F2). The comma re-render moves the dp bit - the number that keeps
per-window near zero - the most, though `pump-009`'s comma still reads wrong
(`050,95` -> `05095`) and `pump-004` stays washed out. Committed metrics:
`runs/2026-09-19/metrics-pu1718.json`.

### Round 4 (orchestrator, 2026-09-19): the end solution validated

Three changes on top of PU.17/18, each measured:

- **Contrast collapse re-ablated under the calibrated framing** - it HELPS now
  (digit-only 0.717 → 0.753 on the 192 count-correct transaction windows), the
  reversal PU.12 predicted; on by default in `train.py`.
- **The slicer keeps interior blank cells**: the anchored grid collapsed an
  empty grid position between two digits (a wide gap, a separator in its own
  cell) and shifted every later cell onto the wrong glyph. Corpus count
  agreement **259 → 273 of 433 (0.63)**; ratchet raised. The synthetic slicer
  test now scores all perspective-free rendered rows (12/14) instead of one.
- **`PumpSegmentsModel.swift`**: the Core ML wrapper and the constrained
  decoder in Swift, validated by `PumpSegmentsModelTests` - the exported model
  driven through a `CVPixelBuffer` reads 246/247 Python-rendered cells right
  and agrees with the Python model on 100 % of them.

Final numbers, transaction fields, the shipped model on the final slicer's
cells (the count-correct set grew to 205 windows, so the per-window number is
not comparable with round 3's 192):

| | per-glyph | digit only | windows, every digit right | dp bit |
|---|---|---|---|---|
| all 320 | 0.455 | **0.591** | 0.206 | 0.755 |
| count-correct 205 | 0.565 | **0.732** | 0.302 | 0.780 |

The day in one line, digit-only on count-correct windows: 0.123 (PU.3) →
0.215 (PU.9) → 0.400 (PU.10) → 0.666 (PU.16) → 0.698 (transaction only) →
0.717 (PU.17/18) → **0.753 / 0.732** (round 4, on 192 / 205 windows).

### Round 4b (orchestrator, 2026-09-19): the oracle's second pass acted on

`agents/reviews/PU.13-REVIEW-ANNOTATIONS.md` measured every window. Acted on, each checked by
eye: `pump-003` total re-typed `20886.25` → `20886.3` (the display rounds; declared as
`csvDisagrees`); `pump-026` price `1924` → `1,924` (the comma is there); `pump-009` board
`072,80` → `072,88`. Not acted on: `pump-061`'s board quads sit on the digits in the overlay,
`pump-087` shows no lit leading zero. **The consumers, not the oracle, mishandled rotation**:
the Swift harness never applied `rotationCW` and the scorer rotated the image with a wrong
point map, so the five rotated fixtures' 23 windows were warped as vertical slivers and charged
to the model as errors. Both now roll the quad's corners into reading order and warp from
those (`PumpQuadWarp.readingOrder`, `score.reading_order`) - no image rotation - and the strips
proved three of the five were annotated 270 where 90 is right; corrected. Count agreement
**273 → 282 of 433 (0.65)**.

Final, transaction fields, shipped model:

| | per-glyph | digit only | windows, every digit right | dp bit |
|---|---|---|---|---|
| all 320 | 0.469 | **0.609** | 0.213 | 0.763 |
| count-correct 214 | 0.561 | **0.728** | 0.299 | 0.779 |

### Round 5 (orchestrator, 2026-09-19): the abstention frontier, and the law on real cells

`score.py --frontier`-style output is now in every score: cells sorted by the constrained
decoder's margin, digit accuracy per coverage decile, and the largest coverage that still
holds 0.99 / 0.95. On the count-correct transaction cells the curve is NOT flat any more
(PU.11 F11 measured it flat on an older model):

| model | digit only | 0.99 holds to | 0.95 holds to |
|---|---|---|---|
| round 4b, plain | 0.728 | 13 % | 34 % |
| round 4b, five-crop TTA | 0.753 | 15 % | 45 % |
| label smoothing 0.05, plain | 0.740 | 10 % | 40 % |
| label smoothing 0.05 + TTA (**shipped**) | **0.762** | **25 %** | **54 %** |

TTA (`--tta`, the centre crop and four shifted by 6 %) and label smoothing (`train.py
--label-smoothing 0.05`, now the default) are both on. Neighbour spill stays off.

**The law on real cells** (`PumpReaderPipelineTests`, the gate-mirror: warp → slice → TTA →
classify → `PumpReadingLaw`, annotated windows, scored on `expected.csv` like the rules arm):
committed **39**, correct 37, **precision 0.949**, coverage 0.122 of 320; **12 of 114 photos
with every field right**. Before the law the same cells read 68/320 windows and 3/114 photos
fully right; the law trades coverage for precision, which is what the gate buys. The wrong
photo is `pump-106`: liters and total each lost a leading cell in the slicer and 5.1 × 70.31
= 358.58 multiplies out - the consistent tenfold shrink the arithmetic cannot see.

### Round 6 (orchestrator, 2026-09-20): real glyphs from the train split - PU.31, decision 9

The corpus was split 70/30 by the product owner (decision 9, `pump/split.csv`, 64 heldout
stills frozen). The train part - 148 stills and the 46 Live records paired to them, 1 906 frames
carrying their still's quads through `pump_reader.track` - was exported by the production
slicer (`PumpTrainSliceExportTests`, 8 527 windows, the slicer's cell count agreeing with the
label on 5 677) and cut into **25 085 labelled real cells** (`pump_reader.realglyphs`; a window
the slicer miscounts is skipped whole). `train.py --real .out/real --real-frac 0.3` mixes 38 of
every 128 batch cells from that set with brightness / contrast / polarity / shift jitter; the
recipe is otherwise the shipped one (15 000 steps, 120 000 renders, label smoothing 0.05,
contrast collapse 0.15, slicer framing).

Measured where the model has seen nothing - the heldout split, annotated windows, the law on
top, `PumpReaderPipelineTests`:

| classifier | committed | correct | precision | coverage of 175 | photos every field right |
|---|---|---|---|---|---|
| round 5, synthetic only (shipped 2026-09-19) | 18 | 17 | 0.944 | 0.103 | 4 / 64 |
| **round 6, + 30 % real glyphs (shipped)** | **44** | **42** | **0.955** | **0.251** | **12 / 64** |

Coverage x2.4 at higher precision. The synthetic validation set reads lower (digit 0.813 vs
0.846) because the batches now carry real cells the validator never sees; it is not the
measurement. The live path (locator -> reader, no annotation) stays at 0 committed on the
heldout split: the row assignment and the verifier are what block it (PU.24, PU.30), not the
classifier. Floors moved: `committedFloor` 39 -> 44 (now a heldout number), `precisionFloor`
0.94 -> 0.95.

Acceptance by the slicer, which is the other half of this round's story: six train fixtures
under glare gave the extractor almost nothing (`pump-021` 3/185 windows, `pump-022` 5/310) -
the frames are there, the slicer cannot count them, and that is the slicer round's material.

### Round 7 (orchestrator, 2026-09-20): the same recipe on the fixed slicer's export

After the slicer learned to prefer the fundamental pitch (PU.4 round, same day) the train export
was redone: 8 550 windows, 5 801 agreeing (5 677 before), 25 349 real cells. Same recipe as
round 6. On the heldout split, both models scored through the fixed slicer:

| classifier | committed | correct | precision | photos every field right |
|---|---|---|---|---|
| round 6 (shipped) | 52 | 50 | 0.962 | 14 / 64 |
| round 7 | 48 | 47 | 0.979 | 13 / 64 |

A trade inside the noise of 175 cells: four fewer commits, one fewer wrong. Round 6 stays in
the bundle because it clears the floors it set (52 / 0.96) and round 7 would move the committed
floor down; the checkpoint and metrics are kept in `runs/2026-09-20/` for the next round to
start from. The live path reads 4 / 4 with either.

### Round 8 (orchestrator, 2026-09-20): the recipe on the body-checked slicer's export

Same recipe again after the slicer's pitch-to-body check: 6 462 of 8 550 windows agree, 28 428
real cells. Heldout, both models through the same (body-checked) slicer:

| classifier | annotated: committed / correct / precision | photos | live: committed / correct |
|---|---|---|---|
| round 6 (shipped) | 66 / 64 / 0.970 | 18 / 64 | **11 / 11** |
| round 8 | 69 / 67 / 0.971 | 17 / 64 | 4 / 4 |

Annotated is a wash; the live path - what the phone runs - drops from 11 to 4, because the
verifier's margin threshold (1.0) was tuned against round 6's margins and round 8 sits
differently around it. Round 6 stays shipped. The lesson for the next round: the verifier's
margin and the classifier are one system, and a retrain needs the verifier re-measured with it.

### Round 9 (orchestrator, 2026-09-20): the first video labels

The product owner labelled 120 frames of `video-001` in the annotator (the arithmetic pass had
closed 76 more across the other clips): 591 video windows, 567 count-agreeing, on top of round
8's export - 30 559 real cells. Same recipe. Heldout:

| classifier | annotated: committed / correct / precision | photos | live |
|---|---|---|---|
| round 6 (shipped) | 66 / 64 / 0.970 | 18 / 64 | 11 / 11 |
| round 8 | 69 / 67 / 0.971 | 17 / 64 | 4 / 4 |
| round 9 | 62 / 60 / 0.968 | 15 / 64 | 2 / 2 |

No gain, and the live path keeps sliding with every retrain since round 6. Two readings, both
to be tested rather than assumed: (a) the seed-0 runs differ by more than the data does - three
recipes within 7 cells on 175 is inside run-to-run noise, and a retrain needs 3 seeds before a
number means anything; (b) the verifier margin threshold is fitted to round 6, and each new
model's margin distribution sits differently against it - the live number is a verifier number,
not a classifier number. Round 6 stays shipped; the next round runs the seed check first.

### The row detector (PU.33, 2026-09-20)

PU.32's two reviews (`agents/reviews/PU.32-REVIEW-STEP-CHANGE-*.md`) named the same step:
a learned locator on the boxes the corpus already holds, and a verifier that stops using the
classifier's margin. Built the same day:

- `pump_reader.detdata`: 153 train stills, every 5th tracked frame of the 46 train records, the
  labelled video frames, 91 receipt/screenshot/fiscal negatives - 692 images, 2 455 boxes of one
  class `digit-row`; the 64 heldout stills in their own folder, and the builder asserts no
  heldout still or record reaches the train set.
- `detector/train.swift`: Create ML `MLObjectDetector`, 3 000 iterations, 59 min on this Mac,
  a 31 MB model (already half-precision; the 8-bit quantiser trips on its anchor constants).
- `detector/measure.swift` on the heldout stills at confidence 0.3: rows found on 59/64 photos,
  every row on 49/64, recall 0.86 at IoU 0.5 and 0.72 at 0.7, median IoU 0.80, 0.7 false rows a
  photo. The misses are the heads it never saw (both Tatsuno amber LED, a Topaz overlay) and two
  Tokheim stills.
- Wired as the locator's first source with the verifier keeping a detected row on count and
  size: **live path 11 → 22 committed, all correct, 3 → 5 photos, 15 s → 2.4 s a photo**;
  annotated path unchanged at 66. The funnel over all 64: candidate on a true row 61, verified
  60, two rows 50, roles right 45, committing 9 - the loss is now the read stage, which the
  diagnostic prints per row (33/40 counted right, 23/40 exact; PU.34).
- `PumpBoxRefiner` (tighten a detected box to its ink band before slicing) measured 22 → 21 and
  is parked behind `PumpReader.refineDetectedBoxes`.

### The read stage behind the detector (PU.34, 2026-09-20)

With the rows located, the loss is the read. The diagnostic's READ lines
(`PumpLivePathDiagnosticTests`, `PUMP_LIVE_DIAG=1`) print, for every detected row the assigner
named right, the annotation's string and the string the slicer + classifier read. The before run
(64 heldout stills): on the photos with the transaction roles right (45 of 64), 117 rows print;
66 read exactly, 15 are one cell wrong, 4 two, 3 three, 1 five, and 28 are miscounted (count
differs from the annotation). The READ strings are unchanged by this row's fixes, so this table
is both the before and the after. The two hypotheses the row carried were checked at their line
and one was refuted.

**A. The miscounted rows are not mostly dropped leading zeros - and the ones that are do not
matter.** Classified by value:

| class | rows | examples |
|---|---|---|
| value-preserving (only leading zeros lost) | 3 | `0025,51 → 2551` (25.51), `0044,85 → 4485` (44.85), `00011,00 → 1100` (11.00) |
| value-changing (a real digit lost or a split glyph) | 25 | `0049,08 → 908`, `0067,05 → 706`, `70.70 → 111111` |

The three value-preserving reads are numerically right, and each is blocked by a *different*
field on its own photo (`pump-028` total `908`, `pump-095` price `111`, `pump-170` total `188`),
so no law change recovers them. The leading-blank logic the row named is already doing its job:
on `pump-095`'s total the slicer emits cells `0,1` blank and `2–5` occupied, so `4485` is 44.85
with the currency's two decimals. `PumpReader.read` drops blank cells before the law, so a
leading blank can never change the digits the law sees - a slicer "leading-blank recovery" is a
no-op for the read by construction. The 25 value-changing rows are split glyphs (two runs merged
into a phantom cell) and grids collapsed onto a subset of the glyphs; the largest group is the
leading glyph cut by a detector box a few percent narrower than the row (`0077,56` read
`707756`: cell 0 is a 25 px sliver of a 66 px `0`, classified `7`). That cut is the detector's,
not the slicer's, and expanding the crop in the reader measured **22 → 17** with precision
0.71 (it pulls in the neighbouring row), so it was reverted.

**B. The one-cell-wrong rows.** For each, which of the four cases holds (wrong cell in the
total / truth digit outside the beam / the confusion table lacks the pair / another row also
wrong). `pair` is whether the read→truth digit change is in the seven-segment table
(`DigitRepair`).

| photo | field | truth | read | pair | other fields | case |
|---|---|---|---|---|---|---|
| pump-030 | total | 3695,76 | 569576 | no (5→3) | exact | already repaired (main tier) |
| pump-055 | total | 108.68 | 10808 | no (0→6) | exact | 2+3 (0 outside beam, pair absent) |
| pump-056 | total | 72.00 | 3200 | no (3→7) | exact | 2+3 (7 outside beam, pair absent) |
| pump-061 | liters | 33.84 | 1384 | no (1→3) | exact | 4 (discount: no board price closes) |
| pump-065 | total | 3765,7 | 37697 | no (9→5) | exact | 3 (5↔9 is single-segment and absent; already derived) |
| pump-076 | liters | 0077,56 | 707756 | no (7→0) | total also wrong | 2+4 |
| pump-076 | total | 0150,00 | 715000 | no (7→0) | liters also wrong | 2+4 |
| pump-091 | total | 1427.0 | 74270 | yes (7→1) | liters and price also wrong | 4 |
| pump-091 | liters | 20.00 | 3000 | no (3→2) | total and price also wrong | 4 |
| pump-091 | unitPrice | 71.35 | 7138 | no (8→5) | total and liters also wrong | 4 |
| pump-104 | liters | 0026,50 | 002850 | yes (8→6) | total and price also wrong | 4 |
| pump-167 | liters | 0042,77 | 704277 | no (7→0) | total also wrong | 2+4 |
| pump-170 | unitPrice | 050,99 | 75099 | no (7→0) | liters and total also wrong | 2+4 |
| pump-175 | liters | 00042,53 | 7004253 | no (7→0) | total also wrong | 2+4 |
| pump-201 | liters | 24,97 | 2491 | yes (7→1) | exact, but the price window is a 0.37-IoU fragment | window, not the table |

Reading: no one-cell row is a case the *repair tier* can fix on its own. Where the pair is in
the table (`pump-091`, `104`, `201`), a second field is also wrong or the price window barely
exists; where only the total is wrong (`pump-055`, `056`), the correct digit is outside the beam
and the pair (0↔6, 3↔7) is not a seven-segment neighbour. The missing single-segment pair is
5↔9, and it is in `DigitRepair`'s table's domain, but that file is outside this row's write set;
`pump-065` (the only row it would touch) already commits via the truncated-total tier.

**What was built, measured separately.** Three law changes in `PumpReadingLaw`, each on the
heldout split:

1. **The repair tier now tries the total too** (the row's case 1). A wrong total cell is as
   likely as a wrong volume or price, and the arithmetic still has to close to the cent. Measured
   alone: live **22 → 22**, annotated **66 → 66** - no heldout row has its only error in the
   total with the true digit a confusion partner, so the capability is a correctness gain with a
   unit test (`totalCellRepairs`) rather than a corpus number.
2. **An exact close beats a slack-only close** (found while measuring 1, not named by the row).
   `closingSlack` is 0.011 so a head that floors its product still closes, but the slack also let
   a beam neighbour one cent away masquerade as a close and abstain a field. `commit` now drops a
   slack-only competitor that reaches the *same* total (an operand is a cent off; the exact
   operand is the read) while a competitor with a *different* total still abstains (the display's
   total itself is ambiguous). Measured alone: live **22 → 23**, annotated **66 → 67**, precision
   unchanged.
3. The oracle strings stay at **526 committed / 0.998 precision** and the fragility pass at
   **0.059** (≤ 0.10), so neither change widens the beam or the tolerance.

| tier | before | after |
|---|---|---|
| oracle strings | 526 / 0.998 | 526 / 0.998 |
| annotated windows | 66 committed, 0.970, 18/64 photos | **67**, 0.970, 19/64 |
| live (detector) | 22 committed, 1.000, 5/64 photos | **23**, 1.000, 6/64 |

The READ strings are **identical before and after**: the gain is the law committing a field it
already read, not a better read. The per-head live table (`PumpReaderPipelineTests`) is now
printed: `gilbarco 11/11`, `tokheim 6/6`, `wayne 5/5`, `tatsuno 1/1`, `other` none committed.

## Named mutation: drop the dp bit

In `dataset.py`, the target's dp bit was dropped (7 bits, dp slot padded with a
constant 0) for training only; validation keeps the true dp. `test_export_roundtrip`
stays green (it is a roundtrip and does not depend on training labels). The
trained model's per-digit accuracy collapses on every dp-carrying class:

| model | dp accuracy | per-digit (dp=0 classes) | per-digit (dp=1 classes) |
|---|---|---|---|
| normal, 2000 steps | 0.8898 | 0.8318 | **0.8000** |
| mutated, 2000 steps | **0.485 (chance)** | 0.7414 | **0.0000** |

`--smoke` reproduces the "at chance" read directly from `metrics.json`: the
mutated smoke reports `final_val_per_bit_accuracy.dp = 0.4941`; the unmutated
smoke reports `0.5117` (both ~chance at 20 steps - 20 steps is too short for the
normal model to learn dp, which is why the 2000-step contrast above is the
load-bearing number). The dp bit is load-bearing: without it in the training
target, the reader cannot see the decimal point at all.

## Swift snippet (for PU.4)

```swift
import CoreML

// Load once; do not reload per cell.
let url = Bundle.main.url(forResource: "PumpSegments", withExtension: "mlpackage")!
let model = try MLModel(contentsOf: url)

// `buffer` is a CVPixelBuffer (32 wide x 48 tall) of the sliced glyph cell.
let input = try MLDictionaryFeatureProvider(dictionary: [
    "glyph": MLFeatureValue(pixelBuffer: buffer)
])
let output = try model.prediction(from: input)
let probs = output.featureValue(for: "segments")!.multiArrayValue!  // [1, 8], FLOAT16
// Order a b c d e f g dp; each in [0,1].
let on = (0..<8).map { probs[[0, $0] as [NSNumber]].doubleValue >= 0.5 }
```

## Checks (exit code)

| check | exit | note |
|---|---|---|
| `.venv/bin/pytest -q` | 0 | **14 passed** (PU.1's 9 + 5 new) |
| `train --steps 6000` | 0 | 264.3 s; metrics committed to `runs/2026-09-19/` |
| `export` | 0 | 64 KB `.mlpackage` under `ios/App/Resources/` |
| `score` (synthetic fake) | 0 | `windows.json` absent; 10 fake fixtures |
| `scripts/gate.sh` | not run | nothing compiled changed (Python + a resource dir only) |

## Found and not fixed

- **coremltools 9.0 warns** "Torch 2.14.0 has not been tested ... 2.7.0 is the
  most recent tested". It did not refuse, and the roundtrip agrees within 1e-3,
  so torch is left unpinned per "pin nothing beyond a lower bound". If an
  on-device surprise appears later, pin `torch==2.7.0`.
- **Output is FLOAT16**, Core ML's default downcast for ML Program. Fine for a
  0.5 threshold and for posterior ordering; if PU.4 wants FLOAT32 posteriors,
  declare `ct.TensorType(name="segments", dtype=np.float32)` at export.
- **Coordinate convention assumption.** `score.py` reads the quad as *normalized*
  `[0,1]` over the EXIF-oriented image (per the brief). If the orchestrator's
  `windows.json` lands pixel-space quads, the scorer must be told - no row owns
  this yet, it is a seam between PU.2's annotation and this scorer.
- **VFD/LED-amber clean-data misses** on the synthetic fake (above). Not acted on
  without the real corpus.

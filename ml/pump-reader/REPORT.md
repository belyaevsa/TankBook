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

### The decimal mark (PU.34b, 2026-09-21)

PU.34's first slice fixed the law; the mark it needs was still invisible to the slicer. The
ratchet said it plainly: **count agreement 209/238, dp agreement 9/237** - the slicer places the
mark on the right cell on 9 of the 237 heldout windows that carry one. The classifier's own dp
bit is weak on the running-display videos (independently measured here: 6/69 on video-002,
0/9 on video-003, 1/57 on video-004), so the mark was simply lost.

**The cause, confirmed at the line.** A decimal mark is a tenth of a digit stroke's column mass,
so it never clears the Otsu run threshold the digits are cut with - the dot's column profile
peaked at 2.2 against a threshold of 3.0 on video-002's total, and the Gilbarco comma at 2.8
against 3.7 (H1). The old bottom-only classifier (`decimalPointTopRowFraction`) could only
reclassify a run that already existed, so it never saw either. The comma also sits at the
digits' baseline and can hang below it (video-004: rows 81-92 against `bandBottom` 86), so the
old band would have cut it (H2). **H3 was refuted**: the false mark on video-003's total
(`1.4541`) is the *classifier's* cell-0 bit, not a slicer run - the slicer placed no mark on
that clip before the fix and places the true one on cell 2 after it.

**What was built.** A mark-specific second look in `PumpGlyphSlicer` (an extension,
`markRuns`/`isMarkBlob`/`inkBlob`): the lower half of the band, extended 25 % below it, is
summed at **half** the run threshold, and only the columns strictly between two digit runs are
searched. A blob must stand at least one column clear of both strokes (a single column at a
stroke's edge is anti-aliasing), be 2 px to 0.4 pitch wide and at most 0.35 band height tall.
It attaches to the cell on its left, exactly as the existing `decimalCells` do. The short-count
retry now keeps a mark-bearing pass over a mark-less one **when the two agree on the count**, so
the half threshold's digit fragments cannot hide the gap the mark sits in.

**Measured (heldout stills and the four named video windows).**

| check | before | after |
|---|---|---|
| `PU.4 slicer` count agreement | 209/238 | **209/238** (held) |
| `PU.4 slicer` dp agreement | 9/237 | **128/237** (0.540) |
| annotated (`PumpReaderPipelineTests`) | 67 committed, 0.970, 19/64 | **73**, 0.986, 22/64 |
| live (detector) | 23 committed, 1.000, 6/64 | **25**, 1.000, 7/64 |
| law oracle strings | 577 / 0.998 | 577 / 0.998 |
| law fragility | 0.051 | 0.051 |

The named windows, slicer mark index (truth -> before -> after): video-002 `081.jpg` total
`2331.65` (3 -> none -> 3) and liters `31.67` (1 -> none -> 1); video-003 `001.jpg` total
`145.41` (2 -> none -> 2) and liters `70.62` (1 -> none -> 1); video-004 `001.jpg` total
`2955.04` (3 -> none -> 3), liters `29.58` (1 -> none -> 1) and unitPrice `99.9` (1 -> none ->
1). The diagnostic (`PumpMarkDiagnosticTests`, `PUMP_MARK_DIAG=1`), every tenth owner-labelled
frame, slicer recall/precision: video-002 **41/69 (0.59), precision 1.00** (was 0/69);
video-003 **6/9 (0.67), precision 1.00** (was 0/9); video-004 **53/57 (0.93), precision 1.00**
(was 1/57). The remaining misses are the fainter `unitPrice` rows of video-002, where the dot is
1-2 px at the strip resolution.

**Named mutation: raise the mark threshold to the digit-run threshold**
(`markThresholdFraction` 0.5 -> 1.0). The two synthetic mark tests go red; reverted, both green
(verbatim in the task record). The hanging-comma case is the one that isolates the mark pass:
the digit-run threshold cannot see the blob at all.

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

### Round 10 (orchestrator, 2026-09-21): the 3-seed protocol on the mark-aware slicer's export

The first round run the way round 9 asked: three seeds, the same recipe (`train.py --steps 15000
--real .out/real-r10 --real-frac 0.3`), real cells cut from the stills' train export plus every
labelled running-display frame (owner and arithmetic labels, all clips), through the slicer with
PU.34b's mark detection. Scored on the heldout split with `PUMP_MODEL=` against the shipped round 6,
both through the same slicer and law (`ce09fd74`):

| model | annotated: committed / correct / precision / photos | live: committed / correct / precision / photos |
|---|---|---|
| round 6 (shipped) | 79 / 78 / 0.987 / 22 | **29 / 29 / 1.000 / 8** |
| round 10 seed 0 | 79 / 76 / 0.962 / 21 | 35 / 32 / 0.914 / 10 |
| round 10 seed 1 | 79 / 76 / 0.962 / 21 | 35 / 34 / 0.971 / 10 |
| round 10 seed 2 | 80 / 79 / 0.988 / 23 | 33 / 32 / 0.970 / 9 |

Two things the protocol settles. **The retrain buys coverage and pays in precision**: every seed
commits 4-6 more live cells and gets 1-3 of them wrong, and the live floor is precision 0.99 - a
wrong number costs more than a missing one (hard rule 13), so none of the three ships. **Seeds differ
by more than recipes did**: seed 0 and seed 1 read the same cells on the annotated path and differ by
two wrong cells on the live path (0.914 vs 0.971); a single-seed comparison at this size is noise,
which is what round 9 suspected. Round 6 stays in the bundle. What moved the heldout today was the
slicer (dp 9 → 128 of 237) and the law, not the classifier; the next classifier round needs a
different lever - the sampler rebalance across heads (93 % of real cells come from 15 fixtures) and
the mark bit trained on the slicer's own marks - not more of the same cells.

The detector, retrained on the same day's corpus (926 images: 176 train stills, 400 Live frames, 249
video frames including the hand-placed anchors, 101 negatives; 3 126 boxes): recall@0.5 0.861 → 0.870,
median IoU 0.796 → 0.779, false rows 42 → 44, photos with every row 49 → 47. Noise; not shipped. The
locator's next lever is geometric (PU.35: a margin on detected boxes before slicing, a stacked-row
rescue below the confidence cut, keypad negatives), not more frames.

### The locator's geometry (PU.35, 2026-09-21)

Started as a flash dispatch that swept the three parts behind environment switches for 1 h 40 min
and was stopped at the owner's pause; finished by the orchestrator from its sweep. The sweep's
finding is the useful part: the margin idea is mostly wrong.

| margin (× row height) | rescue | keypad | live cells / photos |
|---|---|---|---|
| 0 / 0 (HEAD) | off | off | 29 / 8 |
| 0.5 sideways, 0.15 vertical | off | off | **3** / 1 |
| 0.5 sideways, 0 | off | off | 6 (4 right) / 1 |
| 0.2 / 0.15 | off | off | 15 / 4 |
| 0.2 / 0 | off | off | 29 / 9 |
| 0.1 / 0 | off | off | 29 / 9 |
| 0.1 / 0 | on | on | 29 / 9 - and pump-209 loses its only row (60 → 59 verified) |
| **0.1 / 0, kept only when the count holds** | **on** | **on** | **37 / 11**; funnel 61 → 60 → 52 → 45 → 14 |

The slicer's band and pitch come from what is inside the box, so panel, bezel and a neighbour's
ink poison the read faster than a clipped edge digit costs it. The rule that ships slices a
detected row both ways and keeps the widened slice only when it found at least as many cells.
The keypad test is geometry alone (cell aspect < 0.75, off the widest row's span, no sibling
sharing the span) - the sweep's version was gated on the classifier's margin, which decision 10
forbids; on geometry alone it drops pump-224's keys and no true row. `PumpBoxRefiner` (the
opposite bet, tightening; 22 → 21) is deleted. Live floor 29 → 37.

### The operator's corrections as the next round's input (2026-09-21)

The annotator now writes a corrections ledger (tools/pump-annotate/README.md);
`ml/pump-reader/CORRECTIONS.md` is the standing procedure for reading it at the start of every
round - which section indicts which tool, why the corrected frames are diagnosis and never the
yardstick, how a classifier round weights them, how a slicer round turns them into synthetic
tests, and the tracker's IoU histogram as its first ratchet.

## PU.36b - the Python trainers on the database (2026-09-21)

The corpus is SQLite-first (PU.36a); this row moves every Python reader and writer off the text
files and onto `scripts/corpus_db.py`, adds the two sampler levers `CORRECTIONS.md` section 3
asks for, and removes the last file-to-database direction (`track.py`'s `windows.json`).

**What moved, and the query each now runs.**

| module | read | write |
|---|---|---|
| `track.py` | `paired_records()` (media join fixtures), `entry(still)` (entries + windows + live_anchors), `video(stem)` (videos + video_windows + video_anchors) | `save_tracked(record, tracked)` -> `frames` / `frame_windows`, one transaction, then `dump` of that record's file |
| `frames.py` | `video(stem).firstFrame/lastFrame` (`videos`) | `movie.json` (a derived artefact, still a file) |
| `detdata.py` | stills (`fixtures.split='train'` + `entries` + `windows`), records (`frames` + `frame_windows`), videos (`frames.verified` + `labels`), heldout (`fixtures.split`) | Create ML folders (unchanged) |
| `realglyphs.py` | `db_windows(con)`: stills (entries + windows), frames (frames + frame_windows), videos (labels); `hard_keys(con)` (corrections) | cells + manifest (unchanged shape, `weight` per cell) |
| `score.py` | `entries(con)` when `--windows` is omitted | - |
| `calibrate.py` | `entries(con)` when `--windows` is omitted | calibration.json (unchanged) |
| `corrections-report.py` | `corrections(con)`, `tracked(record)` for the make | - |

`corpus_db.py` gained read helpers (`entry`, `entries`, `video`, `video_stems`, `tracked`,
`tracked_records`, `split`, `heldout_names`, `labels`, `corrections`, `paired_records`) and one
writer, `save_tracked`; `_load_frames_file` now delegates to the same `_write_frames`, so the
import path and the tracker's path produce the same rows. `import_frames` stays for a folder
tracked before this row.

**Counts reproduced from the database, options off.** `detdata`: 206 train stills, 64 heldout,
963 tracked frames, 397 video frames, 104 negatives, 5829 boxes - identical to the file-based
builder on the same corpus. `realglyphs`: **40 755 cells** from 9 481 of 12 110 windows, and the
per-fixture dict is **identical to `.out/real-r10/manifest.json`** (191 fixtures, 0 diffs). The
brief's 926 images / 3 126 boxes is the pre-batch-6 figure: batch 6 (`pump-242..273`) landed 50
minutes before the brief and added 30 stills and their tracked frames. The label distribution
does move (e.g. `1` 6332 -> 6037) because the label text now comes from the database, where the
operator's comma/digit corrections are current, not from the older export.

**Sampler levers.** `--cap-fixture 0.02 --hard-weight 4` on the full export, before -> after:

| | cells | gilbarco | wayne | dresser | top source share |
|---|---|---|---|---|---|
| before | 40 755 | 15 506 | 11 695 | 9 453 | 0.0895 (`video-004`) |
| after | 22 351 | 10 098 | 4 767 | 4 775 | 0.0200 (every capped source) |

Water-filling finds the largest per-source count whose kept pool still satisfies the cap, so the
smallest number of cells is dropped; the cap is applied after the weight, so a weighted hard frame
cannot become the new skew. `--hard-weight` is a no-op on the current ledger - all 22 text
corrections are `proposedBy = operator`, none `reader` - and the unit test covers it with a
synthetic reader row.

**Round trip.** `pump_reader.track --only live-5860` (53 frames, 0 dropped) writes the record
through `save_tracked` and dumps `frames/live-5860/windows.json`; `scripts/corpus_db.py check`
exits 0, so the file matches the database byte for byte. The new `corpus_db_test` also round-trips
a record in a temp corpus and shows a moved quad changes the dump (the non-vacuous half).

**Named mutation.** `expand_hard`'s `n = weight if c["hard"] else 1` changed to `n = weight`:

```
        assert len(a) == 30 and all(c["weight"] == 3 for c in a)
>       assert len(b) == 2 and all(c["weight"] == 1 for c in b), "the weight leaked onto an uncorrected frame"
E       AssertionError: the weight leaked onto an uncorrected frame
E       assert (6 == 2)
1 failed
```

Reverted, the same test is `1 passed`.

**Checks.** `pytest` 43 passed (`ml/pump-reader/tests` 33 + `scripts/corpus_db_test.py` 10);
`detdata` and `realglyphs` exit 0 with the counts above; `track --only live-5860` then
`corpus_db.py check` exit 0. No iOS gate: nothing under `ios/` changed.

**Found and not fixed.**

- `tools/pump-annotate/server.py` still calls `corpus_db.import_frames(name)` after a retrack. It
  is now a redundant re-import of the file `track.py` just dumped, and idempotent, but the call
  site belongs to `tools/pump-annotate/` (outside this row's write set); PU.36c removes it.
- The still filter matches a renamed fixture by its stable `pump-NNN` token, because
  `pump-241` was renamed after the train export was cut and an exact-name match would drop its
  only count-agreeing window. A general rename policy is not this row's.

### PU.19 (orchestrator, 2026-09-21): Live Photo per-cell fusion over frames

Does fusing the classifier's per-cell probabilities across a record's frames read more cells right
than the still alone? Measured on the 17 heldout records with tracked frames (860 frames;
`PumpReaderPipelineTests` `liveFusion`), same law and tolerance as the still path:

| read | committed | correct | precision | photos fully right | time |
|---|---|---|---|---|---|
| still alone | 23 | 22 | 0.957 | 6/17 | 21 s |
| fused, all frames | 24 | 23 | 0.958 | 7/17 | 945 s |
| fused, every 5th frame | 24 | 23 | 0.958 | 7/17 | 213 s |
| fused, every 5th frame, pixels | 21 | 20 | 0.952 | 6/17 | 205 s |

**Fusion does not help on this corpus.** The one cell it adds is pump-079's total (`nil` -> 135.86,
correct); nothing else moves. +1 committed / +1 correct is inside the ±2-cell seed noise round 10
measured, and it costs 45x the still read for the all-frames pass (945 s vs 21 s in the test's Debug
build – ~1.1 s a frame, nearly all of it the slicer run on each frame's own strip). Every-5th reads
the same 24/23 as all frames, so a fraction of the frames carries the whole signal. The still path
is unchanged: 79 / 0.987 on the 64 heldout stills.

Fusing the warped cell **pixels** and classifying once is worse, not better: on the same every-5th
frames it commits 21 and gets 20 right where the probability median commits 24 and gets 23. The
probability median is the one to keep if this row is ever revisited.

The 17 records cover 16 distinct stills – `live-6283` and `live-6285` are two records of pump-116
(the Live record and the 4K movie) – so "photos" counts records, not stills.

**What PU.5 would need to wire it live.** The still path here takes the hand quads; the live path
has neither. Fusion needs, per frame: the detector's rows on that frame (the still's boxes cannot
be reused – the camera moves, the records' README says the window quad moves every frame), the
still's row matched to each frame's row across frames, and a cell-count agreement check before a
frame is fused. Only then does the median run. That is the detector-per-frame plus row-matching
work the row already names, and one cell on 17 records does not earn it yet.

## PU.37 - the slicer's count (2026-09-21)

The read stage's largest loss after PU.34b was the count: 29 of 238 heldout windows got the wrong
number of cells, and a miscounted window never reaches the law. The harness now prints every
miscount (`PumpReaderHarnessTests.slicerRatchet`), so the table below is the before, measured with
the strips the same run writes to `ios/.build/pump-reader-out/`.

### The 29, by failure class

| class | windows | still / field (expected -> got) |
|---|---|---|
| **dim or lost glyph** (runs under the one global Otsu, or washed out by glare) | 12 | 014 total 7.01 3->2, 014 board 1.774 4->3, 028 liters 0025,51 6->5, 035 total 82.01 4->3, 038 total 77.45 4->2, 062 total 39.55 4->3, 070 total 0067,05 6->3, 070 liters 0034,94 6->5, 083 total 1437,2 5->4, 092 total 1915.5 5->4, 092 liters 30.00 4->3, 139 total 103.88 5->3 |
| **pitch harmonic** (autocorrelation on 0.35-0.42 or 1.09-1.20 of the band height) | 6 | 035 liters 44.96 4->5, 038 liters 44.03 4->8, 050 liters 0010,54 6->11, 056 board 1.944 4->7, 083 liters 21,00 4->3, 175 total 08038,17 7->3 |
| **over-merge** (split-merge fused two real glyphs) | 4 | 061 total 62.40 4->3, 062 board 1.834 4->3, 095 unitPrice 1,944 4->3, 208 total 4816,61 6->5 |
| **mark over-fire** (`classify` reclassified a fragmented digit's lower stroke as a mark) | 3 | 076 total 0150,00 6->4, 096 total 1426,00 6->5, 142 total 1600.11 6->5 |
| **split over-count** (a glyph split into runs the merge did not rejoin) | 2 | 050 total 0020,33 6->7, 165 liters 78,41 4->5 |
| **snap / blank** (right runs, one spurious grid cell) | 2 | 041 board 1.814 4->5, 055 board 1.884 4->5 |

### What shipped, and what did not

**Shipped: the split-merge body guard** (`splitMergeBodyGuard`). A split glyph's two fragments are
both narrower than a glyph body; two adjacent glyphs where one is a `1` can also sit closer than
`splitMergeGapFraction` and together fit one cell, and the old rule fused them. The guard refuses a
merge whose right fragment is already a full body (`bodyMinimumFraction` of the band height). It
fixes 062 board and 095 unitPrice, and does not touch a real split (both halves sub-body).

| check | before | after |
|---|---|---|
| `PU.4 slicer` count agreement | 209/238 | **211/238** (floor 0.85 -> 0.88) |
| `PU.4 slicer` dp agreement | 128/237 | **128/237** (held) |
| annotated (`PumpReaderPipelineTests`) | 79 / 0.987 / 22 photos | **80 / 0.988 / 22** |
| live (detector) | 37 / 1.000 | **37 / 1.000** (held) |
| law oracle strings | 648 / 0.998 | 648 / 0.998 |
| law fragility | 0.071 | 0.071 |

**Measured and not shipped**, each because it fails a floor the brief names:

- **The local threshold (lever 1): 218/238 count, but dp 126/237 and annotated 77.** Leveling the
  column profile by its own local background before Otsu (a dim glyph measured against the
  background beside it, as the vertical LCN already does) recovers the dim-glyph class, but it
  changes the digit segmentation, which moves the mark's cell index on 26 windows: 22 dp gains,
  26 losses, and the annotated read loses 3 committed cells. A count bought with a wrong digit is
  the trade the brief forbids.
- **The leading-blank tolerance (lever 3): 211/238 count, but annotated 76.** Raising the
  quarter-cell tolerance to the nearest cell adds the dim leading zero's cell, but extending the
  grid also moves every later cell's rect (the occupied cells' left edge is `firstCellStart`, which
  the tolerance shifts), and three annotated rows commit a different digit.
- **The decimal size check: 210/238 count, dp 126/237.** Rejecting a bottom-only run that is wider
  or taller than a mark fixes 076, but it re-admits the fragments as digits and loses two marks.
- **A pitch-band sanity rule** (double a pitch under half the band height) cannot separate the
  wrong windows from the correct narrow-pitch ones: `pump-140` unitPrice is correct at 0.41 of the
  band height while `pump-035` liters is wrong at 0.41. No geometric threshold divides them.

**Named mutation.** Remove the guard's `!rightIsBody` branch from `splitMerge`:
`PumpGlyphSlicerTests.splitMergeBodyGuardKeepsTwoGlyphs` goes red (`guarded.count == 2` -> got 1)
and the ratchet's count falls 211 -> 209. Restored, the test is green and the count is 211.

**Found and not fixed.** The dim-glyph class (12 windows) needs a threshold that is local without
moving the grid or the mark; the pitch class (6) needs a discriminator between a subharmonic and a
genuinely narrow display; the mark over-fire (3) needs a mark rule that does not also reject a real
comma under a digit. Each is its own row; this round's write set could not carry them past the
annotated floor. The two synthetic tests live in `PumpGlyphSlicerTests`; the miscount table is the
ratchet's own print.

## PU.42 - the dim-glyph class of the slicer's count (2026-09-22)

PU.37's largest heldout class was the dim or lost glyph: 12 of the 29 miscounts, a glyph whose
strokes fall under the one global Otsu threshold the digits are cut with, so the pass leaves its
grid cell empty and the count comes up short. PU.37 tried a local-profile threshold and rejected it
- count 218/238 but two marks and three annotated cells lost. This round recovers the cell without
moving the threshold or the grid.

### The twelve, by what the profile shows at the lost glyph

| still / field (expected -> got) | class | profile at the lost cell |
|---|---|---|
| 014 total 7.01 3->2 | H1 dim trailing `1` | peak 2.49 against thr 2.44; low run 118-168, full extent |
| 014 board 1.774 4->3 | H1 clipped at the crop edge | the `1` sits at x5-6, its cell mostly off-strip (visible 11 of 60 px) |
| 028 liters 0025,51 6->5 | H1 dim leading `0` | peak 3.01 against thr 3.26; low runs 10-43 and 68-102 |
| 035 total 82.01 4->3 | H1 dim trailing `1` | low run 226-227 under a 2.44 threshold |
| 038 total 77.45 4->2 | H2 glare | the reflection washes the top half; the runs survive only below the band's midline |
| 062 total 39.55 4->3 | H1 dim trailing `5` | peak ~3.0 against thr 2.97; low run 196-229 |
| 070 total 0067,05 6->3 | H1 dim + over-merge | the leading `00` fused into one run 3-48; the trailing `0`,`5` dim (peaks 3.0, 2.9 against thr 3.59) |
| 070 liters 0034,94 6->5 | H1 dim trailing `4` | peak 4.15 against thr 3.48; low run 330-369 |
| 083 total 1437,2 5->4 | H1 dim leading `1` | peak 3.84 against thr 3.91; low run 12-26 |
| 092 total 1915.5 5->4 | H1 dim trailing `5` | peak 2.37 against thr 2.63; low run 259-290 |
| 092 liters 30.00 4->3 | H1 dim trailing `0` | peak 3.55 against thr 2.71; low run 222-252 |
| 139 total 103.88 5->3 | H1 dim leading `1`,`0` | low runs 17-21 (bottom-only, top at 0.53 band) and 251-291 |

H1 is the class: **10 of 12**. H2 (glare washing a run) is one, and one is an H1 glyph clipped at
the crop edge. **H3 is refuted**: the half-threshold `shortCountRetry` already ran; it did not catch
these because it recounts the whole strip and its uniformity check rejects a pass that adds cells at
the edges, not because the signal was missing.

### What was built

`PumpGlyphSlicer+DimGlyphs.swift`: after the main pass has fixed the grid, a second look at
`dimGlyphThresholdFraction` (0.5) of the run threshold finds runs the Otsu split missed. A run is
accepted as a dim glyph only when it snaps to an **empty** grid cell (the main pass's occupied set),
that cell overlaps the strip by at least `dimGlyphMinimumCellWidthFraction` (0.35) of a pitch, the
run does not begin inside an occupied cell (a bright digit's lower-threshold spill), the cell's own
column-profile peak stands `dimGlyphContrastFraction` (0.25) of the bright cells' median peak, and
the cell carries ink from the top of the band at a lower ink threshold (a mark lives in the lower
band). The recovered cells widen the grid at either end, so a dim leading or trailing glyph is
counted. Two guards keep the recovery off rows it cannot help: the pitch must be a sane fraction of
the band height (0.45-1.05, excluding harmonic and subharmonic rows) and the cell must not be a
sliver at the frame edge. A recovered cell is struck from the decimal set, so a fragment the main
pass called a mark does not leave a mark on a digit.

The synthetic tests are in `PumpGlyphSlicerTests`: a dim leading glyph at a third of the bright
digits' contrast is counted (and is not, with the recovery off); a genuinely blank leading position
stays blank; a glyph split by a washed-out middle column is one run; the body guard's two glyphs
stay two.

### Measured

| check | before | after |
|---|---|---|
| `PU.4 slicer` count agreement | 223/251 | **236/251** (floor 0.88 -> 0.94) |
| `PU.4 slicer` dp agreement | 129/250 | **131/250** (0.524) |
| annotated (`PumpReaderPipelineTests`) | 83 / 0.988 / 23 photos | **106 / 0.962 / 28** |
| live (detector) | 39 / 1.000 / 11 photos | **43 / 1.000 / 13** |

Per-make count agreement (before -> after): circlek 7/9 -> 9/9, dresser 23/30 -> 24/30, gilbarco
81/89 -> 83/89, scheidt 7/9 -> 9/9, tatsuno 6/6, tokheim 27/30 -> 29/30, topaz 3/3, unknown 3/3,
wayne 66/72 -> 70/72.

Ten of the twelve are fixed; the two that are not are 038 (H2 glare, the top of the band gone) and
014 board (the `1` clipped by the crop). One false positive is introduced on a board row (041 board
`1.844` 4->5): the recovery finds a 3 px run at the strip's right edge whose cell is a full pitch
wide, so the width and pitch guards do not reject it. Board rows are not read by the reader; it
costs one count window.

### The annotated precision

The annotated path's coverage rises 83 -> 106 committed cells and 23 -> 28 photos, but precision
falls 0.988 -> 0.962 (still above the 0.96 floor). The three new wrong commits are 014 liters
(3.82 want 3.92), 083 liters (2.1 want 21.0) and 083 total (143.72 want 1437.2). All three are
law-arbitration effects: the recovered leading `1` makes 083's total directly readable, the slicer
finds no comma on that row, and the classifier's dp bit places it one cell early, so a value the
law previously derived correctly is now read wrong. The count fix is right (the `1` is on the
display); the dp placement that the recovery exposes is a classifier/mark defect, not this rule's.
The dp agreement itself rises (129 -> 131). This is the trade the brief names: reported, and the
annotated floor holds.

### Named mutation

Raise `dimGlyphContrastFraction` 0.25 -> 1.0 (a dim glyph must be as strong as a bright one - the
recovery can then never fire):

```
◇ Test "a dim leading glyph at a third of the bright digits' contrast is counted" started.
✘ Test "a dim leading glyph at a third of the bright digits' contrast is counted" recorded an issue at PumpGlyphSlicerTests.swift:204:9: Expectation failed: cells.filter { !$0.isBlank }.count == 4
↳ the dim leading glyph must be counted, got 3 digits
↳ cells.filter { !$0.isBlank }.count == 4 → false
↳   cells.filter { !$0.isBlank }.count → 3
✘ Test "a dim leading glyph at a third of the bright digits' contrast is counted" failed after 0.050 seconds with 1 issue.
✘ Suite "PU.4 pump glyph slicer" failed after 0.051 seconds with 1 issue.
✘ Test run with 1 test in 1 suite failed after 0.051 seconds with 1 issue.
```

and the ratchet's count falls **236 -> 224** (dp 129). Restored to 0.25, the test is
`✔ ... passed` and the count is 236.

### Checks (exit code)

| check | exit | note |
|---|---|---|
| `swift build` | 0 | |
| `swiftlint lint` (repo root) | 0 | 0 serious; `type_body_length` fixed by moving the primitives to `PumpGlyphSlicer+Primitives.swift` |
| `swift test` | 1 | 2230 tests, one failure: **RV.277** (expense category/total) - not the slicer, pre-existing in this tree |
| app-target `xcodebuild` Debug build | 0 | |
| app-target unit bundle `-only-testing:TankbookTests` | 0 | **Executed 299 tests, 0 failures** |
| `scripts/check-screenshot-manifest.sh` | 1 | pre-existing: `PU.29-confirm-pump-alpha` has no capture line; no UI in this row |

The package `swift test` red is RV.277's expense fixtures, which touch no pump code; the slicer's own
suites (harness, slicer, pipeline) all pass in that same run. `scripts/gate.sh` stops at `swift test`,
so the app-target bundle was run in its own invocation, as the two-bundle rule requires.

### Found and not fixed

- **041 board's false positive** (4 -> 5): a 3 px edge run whose snapped cell is a full pitch wide.
  A run-width floor would reject it but also the true 139 leading `1` (4 px, bottom-only); the
  discriminator is not geometric at this resolution. The count row is the owner.
- **038 (H2) and 014 board (clipped)**: neither is recoverable by a run that snaps to an empty
  cell - 038's top half is gone and 014's `1` is mostly outside the warp. H2 needs a rule that
  joins a washed column to its glyph; the row is the owner.
- **The 083 dp placement** above: the law commits a directly-read total whose comma the slicer did
  not find. The classifier's dp bit on a zero-padded total is the seam; PU.34b's mark row owns it.
- **The live path recovers far more cells than the harness dim class** (the amber LED rows,
  board rows), most without changing a committed value. The pitch and width guards cut the
  harmful ones; a future round could measure how many of the rest are real.

## PU.38 - classification from the detector alone (2026-09-21)

Every capture, attach and re-attach decided "is this a display" only after the whole verifier had
warped, sliced and classified every candidate row - 0.8-3.5 s a photo in the gate build and 28 s on
the fallback path, against the 3 s device budget (P4.12) that receipts pay too. The decision is now
the detector's rows alone: two rescued rows that pass the size rules (`minimumRowHeightFraction`,
widest ≥ 0.18 of the frame) and stack (share an x-span), both at ≥ 0.3 or one at ≥ 0.5 with the
other rescued, under the Vision text-line ceiling (`textLines ≤ 30`). No warping, slicing or
classifier enters it; the verifier runs only to read an accepted frame. When the detector finds
fewer than two such rows, the old Vision + classical verifier runs as before, capped at
`slowPathBudget` (1.5 s); a frame that exhausts the cap is not a display. `capture.classify` gains
`path=fast|slow`.

### Heldout six, before and after (`PumpDisplayCaptureTests`, Debug build)

| still | after path | decision ms | classify+read ms | after | before (slow) | before ms |
|---|---|---|---|---|---|---|
| pump-032 | fast | 469 | 3718 | display | display | 2326 |
| pump-035 | slow | 2349 | 2357 | not (31 lines) | not | 4085 |
| pump-042 | fast | 421 | 4758 | **display** | **not** | 4023 |
| pump-038 | fast | 435 | 4532 | display | display | 3338 |
| pump-092 | fast | 16 | 3679 | display | display | 2638 |
| pump-062 | fast | 432 | 5029 | display | display | 3349 |

Totals: **5/6 pumps (5 fast), 0/8 receipts leaked**; before 4/6 (pump-042 was missed at the
classification margin, and the fast path rescues it). Pump decision median **435 ms** vs before
median **3349 ms** (7.7x, Debug); the 8 receipts all take the slow path and are not displays.

### Release build (the shipped one)

The Debug decision is dominated by the shared text-line count's Swift downscale (~337 ms of the
~440 ms); in Release the downscale is 4 ms, so the decision is the detector pass plus Vision:
**13-73 ms**, under 100 ms on the 12 MP stills. `classify`+read is 112-164 ms on a fast pump
(the read still runs); receipts 102-1630 ms, all refused.

### What the budget costs

With the cap at 1.5 s vs 60 s, no verdict changes on the six heldout pumps or the eight receipts:
the fast path decides the five, pump-035 is refused by the text-line ceiling, and every receipt is
refused by it too. The cap only bounds the fallback (pump-190: a 5.5 s uncapped verify, and not a
display either way).

### Named mutations

1. **Drop the stack guard** (`PumpReader.sharesSpan && PumpReader.stacks` in `fastVerdict`):
   `PumpDisplayCaptureTests.fastSideBySideRowsAbstain` goes red
   (`Expectation failed: !PumpDisplayCapture.fastVerdict(rows: rows, textLines: 8)`).
2. **Set `slowPathBudget` to 0**: `PumpDisplayCaptureTests.slowPathBudgetRefuses` goes red
   (`Expectation failed: PumpDisplayCapture.slowPathBudget > 0`). The test's accept/refuse
   assertions inject their budgets (30 s and 0) so they never assert wall clock; the constant
   guard is what the mutation trips.

Restored, both are green.

### Floors

`PumpReaderPipelineTests`: annotated **80 / 0.988**, live **37 / 1.000** - untouched (the read path
did not change). `PumpDisplayCaptureTests`: 5/6 pumps, 0/8 receipts.

**Found and not fixed.** `PumpPanelLocator.downscaleRGB`'s per-pixel Swift loop is the same slow
downscale the classification pays in a Debug build; Release makes it 4 ms, so it is left for the
locator's own round. The `classify`'s slow-path cap starts before `PumpPanelLocator.locate`, whose
Vision pass cannot be interrupted - a fallback frame can overshoot the cap by one locate, but the
verifier's own loop is bounded per candidate.

### The hand quads' own noise (live-6333, 2026-09-21)

Leave-one-pin-out on the 22 frames the owner pinned in live-6333's tail: registered against
the still, the tracked quad meets the hand quad at IoU 0.75; against the nearest pin (the
tracker's actual choice - inliers favour the neighbour) 0.77; chained from the previous frame
0.79; a local template refinement adds nothing. The residuals explain why none of it moves:
between ADJACENT frames the hand quads differ by up to a quarter of the row height at the top
edge (the total 175 px tall on 074, 219 on 075), with opposite signs on the two frames - the
noise is in the pins, and the owner's own re-adjustments of one frame agree at 0.91-0.99. The
detector's median IoU (0.80) is that noise, learned.

Tried and dropped: a pixel snap of the quad's top and bottom to the ink band (the slicer's
LCN band, thresholds 0.15-0.65 of the row maximum) - on exactly these glare-tail frames the
band runs to the strip's edge, so the snap leaves the noisy quads alone and only tightens the
clean ones. What ships instead is a rule in the annotator: on a frame a corner drag is a move
("keep shape", on by default), so the still defines every window's shape and a frame only
says where it went. The consistency is then structural, not estimated.


### Round 11 (orchestrator, 2026-09-22): the training material fixed first

Round 10 asked for a different lever: the sampler rebalance across heads and the mark bit trained
on the slicer's own marks. This round implements the four fixes the contact sheets named, each
measured, and runs round 10's 3-seed protocol on the result. **Nothing ships: no candidate clears
the live committed floor (37), so round 6 stays in the bundle.** The valuable output is which fix
helped and which hurt, and the centred filter's own bias (below).

The export used is `ios/.build/pump-reader-out/train/` as it stood (2026-09-21, before the reader's
read phase and batch 7), per the brief's "do not re-run the Swift export unless it is missing". So
the corpus growth the brief lists (the 26 clips the reader labelled, the hand-pinned frames) is in
the database but has no strips and cannot reach the pool; the pool reproduces the round-10 export's
windows with the current labels. Raw pool: **40 220 cells from 9 336 of 12 110 windows**, 191 train
fixtures, 396 glitch-labelled frames (a frame whose `total` differs from both neighbours in its
run).

#### The four changes

| step | what | file |
|---|---|---|
| 1 | `--centred 0.25`: keep a cell only when its column-ink centroid is within ±25 % of the cell width from the centre; ink is the deviation from the crop's median in the slicer's polarity direction | `realglyphs.py` |
| 2 | `--dp-crop gap\|none\|off`: `gap` widens the crop right by 0.4 × pitch; `none` clears every dp bit and `train.py --dp-crop none` drops the dp term from the loss; `off` is the original framing | `realglyphs.py`, `train.py` |
| 3 | LCD-heavy priors (lcd 0.80 / led 0.15 / vfd 0.05), a grey-panel palette whose contrast draws from the real pool's quantiles, contrast collapse 0.5 | `dataset.py`, `train.py` |
| 4 | `--cap-fixture 0.02 --hard-weight 4` on the full pool | `realglyphs.py` |

#### The real pool's contrast (step 3's measurement)

Measured on the round-10 real cells (`realglyphs` output, 40 755 cells): ink-vs-panel luminance
contrast **p10 28, p25 37, p50 52, p75 91, p90 121**; **94.4 % dark-on-light**. The old synthetic
LCD ranges sat at 80-165, far above the median. `dataset.py` now draws a grey panel (luminance
70-215) and its contrast from those quantiles, on 75 % of LCD samples; the named hue families keep
the other 25 %. The synthetic sheet is `runs/2026-09-22/synth-cells-r11.png`, beside the real
`runs/2026-09-22/real-cells-centred.png`.

#### The centred filter drops 4 439 cells, and most of them are `1`s

`--centred 0.25` dropped **4 439 of 40 220 cells (11.0 %)**: `1` 2 760 of 3 420 (**80.7 %**),
`3` 686 of 1 426 (48.1 %), `7` 401 of 1 444 (27.8 %), `0` 176 (4.5 %), `8` 156 (7.2 %), `9` 107
(3.0 %), `5` 65, `2` 42, `4` 41, `6` 5. Top fixtures by drops: `video-002` 528, `pump-024` 274,
`video-001` 223, `pump-115` 188, `pump-067` 183.

The cause is not misalignment. The slicer right-aligns every cell on the ink's right edge (PU.18:
all pitch slack sits on the left), so the column-ink centroid sits right of centre for **every**
class: measured medians `0` 0.58, `1` 0.74, `2` 0.58, `3` 0.70, `4` 0.66, `5` 0.61, `6` 0.57,
`7` 0.66, `8` 0.61, `9` 0.66. A centre-0.5 test calls a correctly placed `1` "off-centre" and
drops it. **The filter as specified is biased against the narrow right-aligned glyphs, `1` most of
all**, which is the fuel reader's most common digit. That is the finding for the next row: the
filter should compare each cell's centroid to the row's own median centroid (relative phase), not
to the geometric centre.

#### The dp crop: `gap` wins the brief's A/B, then loses the ship measure

Scored on the heldout slices with `score.py --only-count-correct` (185 windows), the brief's two
options:

| variant | dp bit | dp AUC | digit only | per-glyph |
|---|---|---|---|---|
| `--dp-crop gap` | **0.7572** | 0.5511 | 0.8872 | 0.6835 |
| `--dp-crop none` | 0.2163 | 0.4571 | 0.8918 | 0.1864 |

`gap` wins by the number the brief names. But `none` does not behave as "the slicer owns the mark":
`PumpReader` still uses the classifier's dp bit on every row the slicer did not mark
(`markProbability`), and an untrained 8th output is not silent - it fires, per-glyph 0.186 against
digit-only 0.892. `none` is unsafe for that reason alone.

The pipeline then separates the crops: on the same control pool and profile, swapping `off` for
`gap` costs the annotated tier **97 -> 64 committed** and the live tier **36 -> 21**. The widened
crop compresses the digit into the left 71 % of the frame, a framing the reader's own crop (the
slicer's cell rect, no gap) never reproduces, so the digit read itself degrades. **The brief's step
2 is a regression in both of its options; the original `off` framing is the best of the three.**

#### The pool and the seed table

Pool after `--cap-fixture 0.02 --hard-weight 4 --centred 0.25 --dp-crop gap`: **19 800 cells**,
every source at or under the 2 % cap (`wayne` 4 217, `gilbarco` 9 031, `dresser` 4 228, `unknown`
812, `topaz` 365, `adast` 299; top fixture `pump-115` 4.1 %). The control (no centred, `off`) is
22 003 cells. Trained with round 10's recipe (`--steps 15000 --real <pool> --real-frac 0.3`),
exported, and scored with `PUMP_MODEL=` on the 68 heldout stills / 186 cells (floors: annotated 79
/ 0.96, live 37 / 0.99):

| model | annotated: committed / correct / precision / photos | live: committed / correct / precision / photos |
|---|---|---|
| round 6 (shipped) | 83 / 82 / 0.988 / 23 | 39 / 39 / 1.000 / 11 |
| control (pool only: cap+hard, `off`, old profile) | 95 / 92 / 0.968 / 24 | 29 / 29 / 1.000 / 6 |
| + step 3 (new profile) | **97** / 93 / 0.959 / 25 | **36** / 35 / 0.972 / 8 |
| + step 2 (`gap` dp crop) | 64 / 59 / 0.922 / 16 | 21 / 21 / 1.000 / 5 |
| full (steps 1-3), seed 0 | 81 / 78 / 0.963 / 23 | 19 / 19 / 1.000 / 4 |
| full, seed 1 | 79 / 75 / 0.949 / 17 | 30 / 29 / 0.967 / 7 |
| full, seed 2 | 74 / 71 / 0.959 / 20 | 21 / 21 / 1.000 / 4 |

Read as a decomposition (single seed for the middle rows, so ±2 cells on annotated):

- **Step 3 helped**: the new synthetic profile moved the control 95 -> 97 annotated and 29 -> 36
  live, the only candidate near the live floor (36 of 37), though at live precision 0.972 (< 0.99).
- **Step 2 hurt, badly**: `off` -> `gap` on the same pool/profile cost 33 annotated and 15 live
  cells.
- **Step 1 helped the annotated tier**: adding the centred filter to the `gap` pool moved 64 -> 74
  to 81 annotated across the seeds, and the live tier is seed-noisy (19-30).
- **The pool itself (cap + hard-weight) is the largest single mover**: 83 -> 95 annotated, but it
  pays on the live path (39 -> 29), the same verifier-margin slide rounds 8 and 9 measured. The
  live floor 37 is not cleared by any candidate, so **round 6 stays**.

#### Tests

`ml/pump-reader/.venv/bin/pytest -q ml/pump-reader/tests` -> **42 passed** (33 before + 9 new:
`test_realglyphs_centred.py` 5, `test_dp_crop.py` 3, `test_dataset.py` 1).
New: the centred filter keeps a centred cell, drops one whose ink is in the outer quarter, keeps a
no-ink cell (nothing to judge), and `ink_centroid` is `None` without ink and follows the
light-on-dark polarity; `--dp-crop gap` puts the mark at the crop's right edge while `off` stops
short, `none` clears every dp bit and `off` keeps it; the technology priors sum to one and LCD
dominates.

**Named mutation** (compare the centroid against the cell's LEFT edge instead of its centre):
`abs(centroid - 0.5)` -> `abs(centroid - 0.0)` in the filter. Verbatim:

```
    def test_centred_filter_keeps_a_centred_cell(tmp_path: Path) -> None:
        db, manifest = _corpus(tmp_path, lambda d: d.rectangle([18, 2, 22, 18], fill="black"))
        m = _run(tmp_path, db, manifest, "--centred", "0.25")
>       assert m["centred_dropped_total"] == 0, "a centred cell must be kept"
E       AssertionError: a centred cell must be kept
E       assert 1 == 0

tests/test_realglyphs_centred.py:72: AssertionError
----------------------------- Captured stdout call -----------------------------
0 real glyphs from 1/1 windows (1 train fixtures); labels {}
  centred 0.25: dropped 1 cells by class {'1': 1}
```

Reverted, `tests/test_realglyphs_centred.py` -> **5 passed**.

#### Checks

| check | exit | note |
|---|---|---|
| `pytest -q tests` | 0 | 42 passed |
| `realglyphs` x4 (gap, none, control, gap-nocentre) | 0 | pools above; no Swift export re-run |
| `train` x7 | 0 | 963-1037 s each; checkpoints in `.out/`, metrics in `runs/2026-09-22/metrics/` |
| `export` x5 | 0 | candidate `.mlpackage`s in `.out/` |
| `PUMP_MODEL=` score x7 | 0 | table above |
| `score.py` dp A/B | 0 | 185 windows |
| `scripts/gate.sh` | not run | nothing under `ios/` changed (no seed shipped) |

#### Found and not fixed

- **The export predates the corpus growth the brief names.** `ios/.build/pump-reader-out/train/`
  was cut 2026-09-21, before the reader's read phase (2026-09-22 00:25) and batch 7; the brief's
  "do not re-run the export" left the new labels' windows with no strips. The re-export is
  `PumpTrainSliceExportTests` (PU.36b's row) and is the first thing round 12 needs.
- **The centred filter is biased against `1`s** (80.7 % dropped) because the slicer right-aligns
  the ink; a row-relative phase check is the fix. Owned by the next classifier round.
- **`--dp-crop gap` distorts the digit** (the widened crop is what the reader never feeds at
  inference); both of the brief's dp options lose to `off`. Owned by the next classifier round.
- **The live path slides on every retrain** (39 shipped, 19-36 here) because the verifier's margin
  threshold is fitted to round 6 - the same open seam rounds 8, 9 and 10 recorded; no row owns the
  verifier's margin yet.
- **The pipeline numbers were measured with PU.42's uncommitted slicer changes in the tree** (the
  dim-glyph recovery, `PumpGlyphSlicer.swift` + `PumpGlyphSlicer+DimGlyphs.swift`, running beside
  this round). The shipped model still read the committed 83 / 39 on that slicer, so every row of
  the table is on one slicer and the comparison holds, but the absolute numbers are not the
  committed slicer's. Re-score after PU.42 lands.

## PU.47 - the verifier on slicer geometry, never the classifier (2026-09-22)

The live number slid on every retrain (round 11: 39 shipped, 19-36 across the
seed table) because `PumpReader.verdicts` kept a Vision proposal on the
classifier's mean decode margin (`minimumMeanMargin`) - a threshold fitted to
round 6's margin distribution - and because `verify`'s duplicate suppression
ranked by `meanMargin * cells * height`. Detected rows already bypassed the
margin (PU.33/PU.35); a fallback frame's proposals did not. This round replaces
the keep decision with a pure geometry verdict, `PumpRowGeometry`, and removes
the margin from the rank.

### What was built

`PumpRowGeometry.verdict(cells:stripWidth:stripHeight:)` reads only the
slicer's `[GlyphCell]` (blanks included) and the strip size and returns a
verdict with named reasons. `verify` keeps a candidate - detected or proposed -
on `geometry.kept && shaped && !keypad`; `meanMargin` is still computed and
carried in `Verdict` for the diagnostic, and no branch reads it. `isKeypadRow`
stays a separate check: a keypad's cells can look like a display row, and what
singles it out is its place off the display's span (the candidate set), which a
per-strip function cannot see.

The rules:

1. cell count in `[minimumVerifiedCells, PumpReadingLaw.maxCells]` = `[3, 8]`
   (existed);
2. **pitch**: the cell aspect (pitch / band height) in `[0.3, 1.25]`;
3. **ink band**: the band height as a fraction of the strip in `[0.35, 1.0]`;
4. **decimal mark**: the mark's implied fraction digits (`count - 1 - markIndex`)
   at most 3, the law's maximum placement;
5. **blank layout**: the longest interior blank run at most 1 (a leading run of
   unlit cells is allowed; an interior run is a keypad or spaced text).

The brief's literal pitch rule - "coefficient of variation of the non-blank
cell widths" - is identically zero: `PumpGlyphSlicer` snaps every cell to one
pitch, so the widths are equal by construction and no bound on their CoV can
discriminate. The measured, discriminating pitch property is the pitch-to-band
ratio, which is what rule 2 uses. The dp rule is about the mark's *position*,
not its host cell: a mark on cell 0 is legitimate ("1,789", 81 train positives),
so only a mark implying more than three decimals is rejected.

### Bounds (train split only; decision 9)

Positives: the train stills' annotated windows through the current slicer.
Negatives: the Vision proposals on the same stills that overlap no annotated
window at IoU 0.3. 250 stills, **954 positives, 4899 negatives**. The heldout
split was not read while choosing.

| rule | positives p5 / p50 / p95 | negatives p5 / p50 / p95 | kept positives | kept negatives |
|---|---|---|---|---|
| cell count `[3, 8]` | 2 / 4 / 6 | 1 / 4 / 12 | 0.919 | 0.566 |
| pitch `[0.3, 1.25]` | 0.50 / 0.69 / 1.18 | 0.54 / 1.00 / 1.52 | 0.954 | 0.639 |
| ink band `[0.35, 1.0]` | 0.70 / 0.88 / 1.00 | 0.51 / 0.78 / 1.00 | 0.980 | 0.989 |
| dp implied <= 3 | 1 / 2 / 3 | -1 / 2 / 12 | 0.990 | 0.947 |
| blank run <= 1 | 0 / 0 / 1 | 0 / 0 / 1 | 0.980 | 0.953 |
| all five | - | - | 0.890 | 0.357 |

No single rule separates the sets: a Vision character row is as tall and as
wide as a display row (the ink-band and blank-layout rules each keep 95-99 % of
the proposals on their own). The conjunction keeps 89 % of true rows and 36 %
of the proposals; the proposals that survive are read and then refused by the
law unless the arithmetic closes, which is why the live precision holds.

### Tests

`PumpRowGeometryTests` (L1, 4 tests, real stills):

- **pitch**: positive pump-032's total (pitch/band 0.69); negative pump-215's
  keypad - the black 4x4 key grid at the still's right, no annotation window
  covers it, so the quad is hand-written over the "1 2 3" row (x 0.680-0.795,
  y 0.555-0.590), whose keys are square (1.36).
- **dp position**: positive pump-001's liters (`67.00`, mark on cell 1 of 4);
  negative pump-045's total (`0029,31`, the slicer puts the mark on cell 0 of 6,
  implying five decimals).
- **blank layout**: positive pump-215's total; negative pump-263's CLOSED sum
  window (interior blank runs of 88, 3 and 41).
- **ink band**: positive pump-032's total (band 0.84 of the strip); negative
  pump-263's CLOSED (band 0.021). The CLOSED window's occupied count is 5 (its
  173-cell slice is 168 blanks), so the blank-layout and ink-band tests assert
  the named reason, not only `!kept`.

**Named mutation 1 - remove the pitch rule** (comment its `if`):

```
✘ Test "a display's pitch-to-band is kept; a keypad's square keys are not" recorded an issue at PumpRowGeometryTests.swift:95:9: Expectation failed: !keypad.kept
↳     keypad → Verdict(kept: true, reasons: [])
↳       reasons → []
✘ Test "a display's pitch-to-band is kept; a keypad's square keys are not" recorded an issue at PumpRowGeometryTests.swift:96:9: Expectation failed: keypad.reasons.contains(.pitch)
↳ keypad.reasons.contains(.pitch) → false
↳   keypad.reasons → []
✘ Test "a display's pitch-to-band is kept; a keypad's square keys are not" failed after 1.335 seconds with 2 issues.
✘ Suite "PU.47 row geometry" failed after 1.335 seconds with 2 issues.
✘ Test run with 1 test in 1 suite failed after 1.335 seconds with 2 issues.
```

restored:

```
✔ Test "a display's pitch-to-band is kept; a keypad's square keys are not" passed after 1.311 seconds.
✔ Suite "PU.47 row geometry" passed after 1.311 seconds.
✔ Test run with 1 test in 1 suite passed after 1.311 seconds.
```

**Named mutation 2 - remove the blank-layout rule**:

```
✘ Test "a display's leading blank run is kept; an interior run is not" recorded an issue at PumpRowGeometryTests.swift:127:9: Expectation failed: closed.reasons.contains(.blankLayout)
↳ closed.reasons.contains(.blankLayout) → false
↳   closed.reasons → [TankbookCore.PumpRowGeometry.Reason.inkBand]
✘ Test "a display's leading blank run is kept; an interior run is not" failed after 1.280 seconds with 1 issue.
✘ Suite "PU.47 row geometry" failed after 1.280 seconds with 1 issue.
✘ Test run with 1 test in 1 suite failed after 1.280 seconds with 1 issue.
```

restored:

```
✔ Test "a display's leading blank run is kept; an interior run is not" passed after 1.228 seconds.
✔ Suite "PU.47 row geometry" passed after 1.228 seconds.
✔ Test run with 1 test in 1 suite passed after 1.228 seconds.
```

### The decoupling, measured

Heldout live path (`PumpReaderPipelineTests.livePath`), round 6 and the
round-11 `+step 3` candidate (`ml/pump-reader/.out/train-r11-step3-s0`), through
the new verifier:

| model | annotated: committed / correct / precision / photos | live: committed / correct / precision / photos | verifier kept rows |
|---|---|---|---|
| round 6 (shipped) | 104 / 103 / 0.990 / 30 | 43 / 43 / 1.000 / 14 | 216 |
| round 11 +step 3 | 96 / 95 / 0.990 / 27 | 35 / 35 / 1.000 / 9 | 216 |

The verifier's kept rows are **identical (216)** for both models - it is
model-free by construction, and `PumpReaderPipelineTests.decoupling`
(`PUMP_DECOUPLE=1`) asserts it row by row. **The brief's claim that the two live
numbers are within 3 cells is not met: they are 8 apart (43 vs 35).** The margin
gate was one coupling and it is gone, but the live *committed* number is not a
verifier number: the kept rows are the same, and the difference is the read
stage - the classifier's decode decides which cells the law commits, and a
retrain moves that. The brief says to say so and stop; that is the finding. The
floor is unchanged: round 6 holds at **43 / 1.000**.

### Checks

| check | exit | note |
|---|---|---|
| `swift build` | 0 | |
| `swiftlint lint ios/Tests/.../PumpRowGeometryTests.swift` | 0 | 0 violations (the two new/edited files are clean) |
| `swiftlint lint ios Spike tools agents ml scripts` | 2 | 1 serious, pre-existing: `CorpusPairTests.swift:59`, a 219-char line from corpus batch 8 - not this row |
| `swiftlint lint` (repo root) | 132 | crashes on the untracked, gitignored `build/` DerivedData (GRDB sources); `**/.build` excludes the dotted dirs but not `build/` |
| `swift test --filter "PumpRowGeometryTests\|PumpReaderPipelineTests\|PumpReaderHarnessTests\|PumpReadingLawTests"` | 1 | 28 tests in 4 suites, 1 issue: `PumpReadingLawTests`' pump-300, a corpus-batch-8 fixture |
| `scripts/gate.sh` | 132 | stops at the lint step (the `build/` crash above); the remaining steps were run in their own invocations |
| app-target `xcodebuild` Debug build | 0 | |
| app-target unit bundle `-only-testing:TankbookTests` | 0 | **299 tests, 0 failures** |
| `swift test` (whole package) | 1 | 2239 tests, 98 issues - all pre-existing/corpus: `PaddleOCRTests`/`CorpusABTests` (the 47 unswept batch-9 fixtures), `PumpReadingLawTests` (pump-300), `PumpRowAssignmentTests` (pump-309), `CaptureOrientationTests` (RV.49), `RV.277` |

The pump suites themselves pass: `PU.47 row geometry`, `PU.4 pump reader
harness` (count 237/251, dp 133/250) and `PU.22 pump reader on real cells` (104
/ 0.990 annotated, 43 / 1.000 live) are all green in the full run.

The pipeline suites carry no macOS-runtime gate in this tree (only
`VisionMeasuredRuntime` suites do, and the pump pipeline is not one), so they
ran on this macOS 27 without a bypass; the brief's "skip on macOS != 26" did not
apply.

### Found and not fixed

- **`PumpDisplayCapture.displayRows` still reads the margin**
  (`window.detected || window.meanMargin >= classificationMinimumMargin`,
  `PumpDisplayCapture.swift:236`). That is the display/not-a-display decision,
  not the reader's keep decision, and it is outside this row's write set; it is
  the next place a retrain can move a live decision. No row owns it yet.
- **The geometry gate is more permissive than the margin gate** (36 % of the
  proposals vs the margin's much smaller set). The heldout live precision stays
  1.000 and the floor holds at 43, but the FPR is the number to watch if a
  future retrain's read is worse.
- **The live number still slides with the classifier through the read**, as the
  decoupling table shows. Removing the verifier's margin was necessary but not
  sufficient for a retrain-stable live number; a read-stage stability measure
  (or a heldout read floor that is not tied to one model) is the next lever. No
  row owns it yet.
- **`swiftlint lint` from the repo root crashes (exit 132) on the untracked,
  gitignored `build/` DerivedData**, whose vendored GRDB Swift the root lint
  scans (`**/.build` excludes the dotted build dirs but not `build/`). The
  working lint is `swiftlint lint ios Spike tools agents ml scripts`, which is
  exit 2 only for the pre-existing `CorpusPairTests.swift:59`. Both are outside
  this row's write set; the `build` exclusion is a one-line `.swiftlint.yml`
  fix, and no row owns it.

### PU.48 - retrain the row detector on this week's records (2026-09-22)

**Nothing ships.** The retrained detector passes the (c) gate on the current corpus, but the
live floor falls from 43 to 28 cells at precision 0.964, so the shipped PU.33 model stays in the
bundle: `ios/App/Resources/DigitRows.mlmodel` is byte-identical (`b560fef2…`) and
`PumpReaderPipelineTests`' floor comment is untouched.

**The premise holds.** PU.33 trained on **153 train stills** (2026-09-20). The old export's
`counts.json` (a later re-export, never trained) read 206/64/963/397/104/5 829. Today's export
reads **249 train stills / 68 heldout / 1 247 Live frames / 819 video frames / 116 negatives /
9 152 boxes** - batches 6-9 (`pump-242`..`318`, the 60 tracked records and the 16 clips) are
only in today's set, so the shipped detector never saw this week's heads.

**A concurrent corpus commit landed mid-task.** The first export (13:04) read 248 train stills /
8 893 boxes; the owner's annotator pass over `pump-287`..`299` and the `detdata.py` skip/negatives
change (commits `4c21b9ad`, `b97569a9`) landed while the first model trained. The final export
(14:34, the numbers below) adds one train still and 259 boxes. The heldout yardstick is identical
between the two (68 stills, 252 boxes), so the old-model measurement is shared; the final model is
the one reported. There are no `skipped` frames in the corpus yet, so the new filter is a no-op
here.

**Export** (`detdata --edge 1024 --frame-step 5`, 49 s, exit 0):

| train stills | heldout stills | Live frames | video frames | negatives | boxes |
|---|---|---|---|---|---|
| 249 | 68 | 1 247 | 819 | 116 | 9 152 |

`tests/test_detdata_disjoint.py` (new, 2 tests) proves on a scratch database that a heldout
still and every frame of a Live record paired to it stay out of `train`, and that a record whose
still is `tracking = bad` contributes no frame. Full suite: **44 passed** (42 + 2).
**Named mutation** - `heldout = row["split"] == "heldout"` -> `heldout = False` in `detdata.py`:
`test_no_heldout_still_or_paired_frame_reaches_train` goes red, verbatim

```
>               assert r["source"] not in heldout_names, f"heldout still in the detector's train set: {r['source']}"
E               AssertionError: heldout still in the detector's train set: pump-901-held-ee.jpg
ml/pump-reader/src/pump_reader/detdata.py:171: AssertionError
1 failed
```

Reverted byte-identical (no `git diff` on `detdata.py`), the two tests pass.

**Train** (`detector/train.swift`, 3 000 iterations): **2 454 s (41 min)**, model
**31 751 101 bytes (30.3 MiB)** at
`ml/pump-reader/.out/det/pu48-latest/DigitRows-pu48-latest.mlmodel`. Create ML validation mAP@50
**0.9400**. (The first, stale-export model: 2 456 s, the same size, mAP@50 0.9445.)

**Measure** (`detector/measure.swift`, heldout 68 stills, confidence 0.3; the old model
re-measured today because the old PU.33 numbers are on 64 stills and not comparable):

| metric | old (shipped PU.33) | new (PU.48) | gate |
|---|---|---|---|
| recall @ IoU 0.5 | 219/252 = 0.869 | **221/252 = 0.877** | rose |
| recall @ IoU 0.7 | 185/252 = 0.734 | 178/252 = 0.706 | fell |
| median IoU | 0.797 | 0.772 | fell |
| false rows / photo | 43/68 = 0.632 | 56/68 = 0.824 | **+0.191 (<= 0.2)** |
| photos with any row | 63/68 | 64/68 | rose |
| photos with every row | 53/68 | **55/68** | rose |

**(c) passes**: recall@0.5 and photos-with-every-row both rise, and false rows rise by 0.191,
under the 0.2 bound.

Per-still (found / truth), before -> after, for the night set and the PU.33 misses:

| still | old | new |
|---|---|---|
| pump-008 Topaz overlay | 0/3 | 1/3 (0 matched - a false row) |
| pump-186 Tatsuno amber LED | 0/3 | **1/3** |
| pump-187 Tatsuno amber LED | 0/3 | 0/3 |
| pump-134 Tokheim Kronur | 0/3 | 0/3 |
| pump-194 Tokheim dusk | 0/3 | 0/3 |
| pump-190 Tokheim fog | 1/3 | 1/3 |
| pump-198 Tokheim reflection | 1/3 | 1/3 (found 3, one matched) |
| pump-201 Tokheim Belarus night | 2/3 | 2/3 |
| pump-275 Wayne Neste night | 5/5 | 5/5 (found 8) |
| pump-277 Gilbarco Peetri night | 3/3 | 3/3 |
| pump-280 Gilbarco night | 3/3 | 3/3 |
| pump-281 Gilbarco night | 3/3 | 3/3 |

The extra recall is bought from the false-row budget: the Topaz still's one new box is a false
row, and pump-198's new box does not match a truth row either. The night stills are found by both
- they are heldout, so neither model trained on them.

**The gate (d): does not ship.** (c) passes, but the live floor falls - exactly the trap this
brief names, a candidate may not ship on (c) alone. `PumpReaderPipelineTests` was run with the
candidate temporarily at `.out/det/DigitRows.mlmodel` (restored after) via
`cd ios && swift test --filter PumpReaderPipelineTests`; this is macOS 27 and the suite is **not**
`.visionMeasuredRuntimeOnly`, so it ran with no bypass:

| model | live: committed / correct / precision / photos | annotated: committed / correct / precision / photos |
|---|---|---|
| old (shipped) | **43 / 43 / 1.000 / 14 of 68** | 104 / 103 / 0.990 / 30 of 68 |
| new (PU.48) | **28 / 27 / 0.964 / 7 of 68** | 104 / 103 / 0.990 / 30 of 68 |

The live floor is 43 at 0.99; the candidate reads 28 at 0.964, so it does not ship even though
(c) passed. The annotated path is identical because it uses the hand-drawn windows, never the
detector. This is the same "live path slides on every retrain" seam rounds 8-11 recorded: the
detector's recall improved, but the verifier's margin is fitted to round 6 and rejects the new
boxes.

#### Checks

| check | exit | note |
|---|---|---|
| `pytest -q ml/pump-reader/tests` | 0 | **44 passed** (42 + 2 new) |
| `detdata` (final) | 0 | 49 s; counts above |
| `train.swift` 3000 | 0 | 2 454 s; 31 751 101 bytes |
| `measure.swift` old | 0 | table above |
| `measure.swift` new | 0 | table above |
| `swift test --filter PumpReaderPipelineTests` (old) | 0 | live 43 / 1.000 |
| `swift test --filter PumpReaderPipelineTests` (new) | 1 | live 28 / 0.964 - the floor red, as the gate requires |
| `scripts/gate.sh` / `swiftlint` | not run | no model shipped; no Swift source or `ios/` file changed (Python test + docs only) |

#### Found and not fixed

- **The detector improved and the live path still fell** (43 -> 28): the verifier's margin is
  fitted to the round-6 boxes, so a better locator feeds it boxes it discards. The detector's next
  round cannot be judged by `measure.swift` alone - the verifier's margin is the seam rounds 8-11
  recorded, and no row owns it.
- **The two Tokheim stills PU.33 named (Kronur, dusk) and the Topaz overlay are still 0 matched.**
  The retrain added 96 train stills and ~1 300 frames and moved neither; they are a geometry/
  verifier problem, not a data-volume one.
- **False rows rose with the frames** (43 -> 56, +0.191 - inside the 0.2 bound but on the edge).
  The negatives (116) did not keep pace with the new forecourts; a future retrain should grow the
  keypad/`CLOSED` negatives with the positives.
- **`PumpReaderTestSupport.detectorURL` reads `.out/det/DigitRows.mlmodel`, not the shipped
  `ios/App/Resources/DigitRows.mlmodel`.** A candidate can be scored by the pipeline only after
  overwriting the dev copy, which is why the swap-and-restore above was needed. The two files are
  byte-identical today, so it does not change any number, but the seam is a trap for the next
  detector round; no row owns it.

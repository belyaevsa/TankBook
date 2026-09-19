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

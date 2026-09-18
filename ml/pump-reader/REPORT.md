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

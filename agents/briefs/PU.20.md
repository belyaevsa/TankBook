# PU.20 - an abstention signal that ranks

**Parent journey:** J4. **Row:** `docs/TASKS.md` → PU.20. **Read first:** `ml/pump-reader/REPORT.md`
(all rounds; the final state is round 4b), `agents/reviews/PU.11-REVIEW-IMPL.md` F11 (the flat
accuracy-vs-coverage curve, measured) and F12 (multi-task digit head, spatial evidence instead of
GAP), `PU.12-REVIEW-DATA.md` finding 2 (the faint regime).

## Where you may write

Only `ml/pump-reader/` and `ios/App/Resources/PumpSegments.mlpackage`. **Keep the model's input and
output contract** (`glyph` 32×48 RGB in, `segments` [1,8] out) - `PumpSegmentsModel.swift` and its
test consume it; an extra output (`digits` [1,10]) is allowed, a changed one is not. Never open a
fixture image by hand; the corpus is scored through `score.py` only. No `/tmp`; scratch is
`ml/pump-reader/.out/`. Three Swift agents are working in this checkout - ignore `ios/Sources`.

## Write code first, explore second

## The number

`score.py` gains `--frontier`: sort every count-correct transaction cell by the constrained
decoder's margin (top-1 minus top-2 log-likelihood) and print digit accuracy at coverage 10 %,
20 %, … 100 %, plus the coverage at which accuracy first reaches 0.99 and 0.95. Today's curve
is nearly flat (0.76 at 30 % → 0.61 at 100 % per F11 on an older model); **the deliverable is
that curve moved**, on the shipped slices (`ios/.build/pump-reader-out/slices.json`), reported
before and after each change below. The cell-level oracle is the annotation string.

## What to try, in order, each ablated against the frontier (keep what helps, keep the knobs)

1. **Test-time augmentation**: classify each real cell at 5 crops (±6 % phase, ±6 % band, the
   centre) and average the probabilities; margin from the averaged vector. No retraining.
2. **Temperature / label smoothing**: BCE on synthetic data saturates the logits; retrain with
   label smoothing 0.05 and/or calibrate a temperature on the synthetic validation split, and
   see whether the margin starts to rank real errors.
3. **A multi-task digit head**: `SegmentNet` gains a second output `digits` (10-way softmax,
   plus blank as class 11 for training only) trained jointly; the decoder's ranking uses the
   digit posterior × the segment likelihood. Export both outputs.
4. **Spatial evidence instead of global average pooling** (F12): replace GAP with a small
   flatten→linear head so each segment's logit can look at where that segment is.

Round-2 recipe otherwise (15 000 steps / 120 k samples, spill 0, contrast 0.15, calibrated
framing, comma).

## Tests

- `test_frontier.py`: on a synthetic validation split the frontier is monotone non-increasing
  in coverage and reaches ≥ 0.99 at ≤ 50 % coverage (oracle: the split's labels).
- Existing 28 stay green; the export round-trip test covers the new output if you add one.
- **Mutation named by this brief:** replace the margin with a constant - the frontier flattens
  to the overall accuracy at every coverage; paste it.

## Checks (by exit code)

`.venv/bin/pytest -q` → 0, count ≥ 29; train/export/score → 0; the Swift test
`cd ios && swift test --filter PumpSegmentsModelTests` → 0 after your export (its count is 2).

## Standing fences

Never stash / checkout / move; never commit; `pgrep -x` only; not alone in the checkout; no `/tmp`.

## Report back

Exit codes, counts, the frontier table before and after each step, the digit-only numbers next
to round 4b's (0.609 all / 0.728 count-correct), the red mutation, model size, anything found
and not fixed.

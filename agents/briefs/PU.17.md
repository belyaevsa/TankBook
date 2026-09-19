# PU.17 + PU.18 - the comma drawn where displays draw it, and cells shaped like the real ones; retrain

**Parent journey:** J4. **Rows:** `docs/TASKS.md` → PU.17 and PU.18 (one run: both live in
`dataset.py`/`glyph.py`/`row.py`). **Read first:** `ml/pump-reader/REPORT.md` (all rounds),
`agents/reviews/PU.12-REVIEW-DATA.md` findings 1, 3, 4 and `agents/reviews/PU.11-REVIEW-IMPL.md`
F2, F5, F8 - they carry the measurements this row acts on. **Decisions in force**
(`docs/EXTRACTION.md` → "Decisions (product owner, 2026-09-19)"): geometry MAY be calibrated on
aggregate statistics from `ios/.build/pump-reader-out/slices.json` (cell rects) and
`Spike/ReceiptSpike/fixtures/pump/windows.json` (strings) - never on pixels, never per fixture;
the gate is transaction fields only (`score.py` default).

## Where you may write

Only `ml/pump-reader/` and `ios/App/Resources/PumpSegments.mlpackage`. No Swift. Never open a
fixture image by hand. No `/tmp`; scratch is `ml/pump-reader/.out/`. Other agents are running
read-only reviews in this checkout - ignore them.

## Write code first, explore second

## What to build

### A. The comma (PU.17)

1. `glyph.py` `_draw_dp` / `row.py`: draw the decimal mark as the corpus draws it - a **comma**
   (a dot with a short tail) whose centre sits **below the digit baseline** (y ≈ baseline +
   0.05–0.15 × glyph height) and **in the gap after the glyph**, so its tail crosses into the next
   cell's left edge. Use `dp_offset_frac` (sampled today, never used) as the horizontal offset
   and add a vertical one. Keep a plain-dot variant at a minority rate for LED heads.
2. The row's ink band (`_row_ink_band`) must include the comma, so a dp-carrying cell has the
   digit in its top ~85 % - the vertical layout real dp cells have.
3. Label semantics unchanged: the dp bit belongs to the glyph the comma follows. A cell cut
   from the NEXT position carries the comma's tail at its left edge with dp = 0 - that is a
   real negative and must be in the data.
4. Comma rate per field from the strings in `windows.json` (count `,`/`.` per field over the
   transaction windows) - sample dp presence at that rate, not 50/50.

### B. The cell shape (PU.18)

5. `python -m pump_reader.calibrate --slices … --windows … --out src/pump_reader/calibration.json`:
   from `slices.json` rects × the window quads compute, over transaction windows only, the
   distributions of (a) cell aspect before resize (pitch / band height), (b) the glyph's
   horizontal phase within the cell (ink right-edge margin / pitch, ink left-edge margin /
   pitch), (c) digit frequency and leading-zero run length per field, (d) dp rate per field.
   Store quantiles (p5, p25, p50, p75, p95) and counts - aggregate only. Check the file in.
6. `render_slicer_cell` samples the crop's aspect and phase from those quantiles (piecewise
   linear), replacing the `U(0.2, 0.8)` slack split and the current band-only height.
7. **One strip resolution.** The harness warps to 96 px, the scorer to 48, training renders
   ~40: make the Python side render the row at the harness height (96) and then downsample to
   the model input exactly as `score.py` does, and make `score.py` use 96 too (PU.11 F5 measured
   +2 points). The Swift side already uses 96.
8. Retrain 15 000 steps / 120 k samples (the round-2 recipe: spill 0, contrast 0), export, score
   with `--boxes`, all 320 and `--only-count-correct`; write the lines next to round 3's
   0.569 / 0.698 (digit only) and the dp-bit accuracy / AUC (compute AUC in the scorer if it
   is not there) next to 0.74 / 0.52.

## Tests

- Existing 23 stay green (adjust `test_framing.py`'s expectations to the calibrated
  distributions, naming the calibration file as the oracle).
- `test_comma.py`: a rendered row's comma ink lies below the digit's baseline and its tail's
  rightmost column is inside the next box (oracle: the row's boxes). **Mutation named by this
  brief:** clamp the comma back inside the glyph box - red; paste it.
- `test_calibration.py`: the checked-in quantiles are monotone and every field has a count;
  and a 500-sample synthetic draw's aspect p50 is within 0.1 of the calibrated p50 (oracle: the
  calibration file).

## Out of scope

Slicer changes, multi-frame (PU.19), the digit head / abstention (PU.20), the locator.

## Checks (by exit code)

`.venv/bin/pytest -q` → 0, count ≥ 26; calibrate, train, export, score → 0. No iOS gate.

## Standing fences

Never stash / checkout / move; never commit. `pgrep -x` only. Not alone in the checkout.

## Report back

Exit codes, counts, run-or-only-written, the red mutation, the calibration quantiles (the
table), training wall time and validation, the before/after held-out lines (digit-only all /
cc, dp accuracy and AUC), `pump-009` and `pump-004` by name, anything found and not fixed.

# PU.9 - train on the slicer's own framing

**Parent journey:** J4. **Row:** `docs/TASKS.md` → PU.9. **Read first:** `ml/pump-reader/REPORT.md`
→ "The shipped recipe" (the table that motivates this row) and `runs/2026-09-19/held-out-cells-final.png`
(what a real cell looks like when the slicer hands it over: full glyph band height, one pitch
wide, the glyph roughly centred, neighbour edges at both sides, no vertical margin).

## Where you may write

Only `ml/pump-reader/` and `ios/App/Resources/PumpSegments.mlpackage`. Nothing in `ios/Sources`,
`ios/Tests`, `Spike/`. Do not change `score.py`'s `--boxes` path or `PumpGlyphSlicer.swift`.
No `/tmp`; scratch is `ml/pump-reader/.out/`. The corpus stays held-out: no fixture image is
opened except through `score`; the cell sheets may be looked at.

## Write code first, explore second

## What to build

1. **`dataset.py`: a framing that mirrors the slicer.** Render a short row with PU.1's
   `render_row` (2–4 glyphs around the target, spill OFF - the neighbours are there for
   framing only, at the profile's normal pitch), then cut the target's cell exactly as
   `PumpGlyphSlicer` does: **x** = the target's advance-grid cell (its box x, one pitch wide,
   jitter ±8 % of pitch), **y** = the glyph ink band of the whole row (top of the highest lit
   pixel to bottom of the lowest, jitter ±6 %), then resize to 32×48 with the same resampling
   `score.py` uses. A `1` sits at the right of its cell the way the profile's segment geometry
   puts it - do not centre it. Blank cells are cut the same way from a blank position in the
   row; dp-only cells too.
2. Keep the existing cell renderer reachable (`framing="glyph"` vs `framing="slicer"`, default
   `slicer`) so the ablation can be re-run; `train.py --framing`.
3. **Retrain** 6 000 steps with the shipped recipe (spill 0, contrast 0) → `runs/<date>/`;
   **export**; **score** with `--boxes ../../ios/.build/pump-reader-out/slices.json`, all windows
   and `--only-count-correct`, and write both lines under REPORT.md's table with the before
   (0.091 / 0.105). Also print dp-bit accuracy on the real windows separately.
4. If the count-correct number does not beat 0.105, run the `glyph` framing with the same seed
   as a control and report both - the row's answer is then "framing was not it", which is
   still the deliverable.

## Tests

- Existing 18 stay green.
- `test_framing.py`: a slicer-framed sample of `8` has lit pixels within 2 px of both the top
  and bottom canvas edges (oracle: the band trim), and a `1`'s lit columns are in the right
  half (oracle: the profile's segment geometry); 300 samples, ≥ 95 %.
- **Mutation named by this brief:** in the slicer framing, replace the ink-band y-crop with the
  full row height (the old margin framing) - the top/bottom test goes red; paste it.

## Checks (by exit code)

`.venv/bin/pytest -q` → 0, count ≥ 19; train, export, score → 0. No iOS gate (resource only).

## Standing fences

Never stash / checkout / move; never commit. `pgrep -x` only. Not alone in the checkout.

## Report back

Exit codes, counts, run-or-only-written, the red mutation, wall time and validation, the
before/after held-out lines (all + count-correct) and dp-bit accuracy, `pump-004` by name,
model size, anything found and not fixed.

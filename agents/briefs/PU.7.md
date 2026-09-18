# PU.7 - make the renders look like the corpus, then retrain

**Parent journey:** J4. **Row:** `docs/TASKS.md` → PU.7 (read it - it names the four gaps).
**Authority:** `docs/EXTRACTION.md` → "The pump reader". **Builds on:** PU.1/PU.3 in
`ml/pump-reader/`, PU.4's `score.py --boxes` and `ios/.build/pump-reader-out/slices.json`.

## Where you may write

Only `ml/pump-reader/` (source, tests, `runs/<date>/`, `REPORT.md`) and the exported
`ios/App/Resources/PumpSegments.mlpackage`. **Another agent is editing `ios/Sources/.../PumpReader/`
and `ios/Tests/.../PumpReader*.swift` at the same time - never touch, read-for-info only.** Do not
edit `score.py`'s `--boxes` code path; you may add flags. No `/tmp`; scratch is `ml/pump-reader/.out/`.

**The corpus is held-out.** You may LOOK at the two cell sheets (`runs/2026-09-19/held-out-cells.png`,
`held-out-cells-pu4.png`) and at `score --dump` output to understand failure shapes - that is what
this row is. You may NOT open fixture images to trace geometry into a profile, and nothing real
enters training. Every profile constant you change gets a docstring line saying which gap on the
sheet it answers.

## Write code first, explore second

## What to change

1. **Bolder segments** (`profiles.py`): `segment_ratio` ranges down to ~3.5–6 on the LCD makes;
   keep one thin profile so the classifier still sees thin glyphs.
2. **Neighbour spill** (`dataset.py`): render the target glyph with a random neighbour glyph on
   each side at the profile's pitch, then crop the centre cell with the existing jitter - so a
   cell carries a neighbour's edge the way a real slice does. Use PU.1's `render_row` for this
   rather than compositing by hand.
3. **Faint / low-contrast** (`augment.py` or `dataset.py`): a contrast-collapse augment that maps
   the on/ground colours toward each other so 10–20 % of samples land at 10–25 % contrast; plus a
   broad soft reflection overlay (a low-frequency bright blob covering up to half the cell).
4. **Italic slant with chamfered ends**: widen the `slant_deg` range on `gilbarco`/`wayne` to
   ~6–12 and add end chamfers to `_hseg`/`_vseg` if they are plain rectangles.
5. **Retrain** 6 000 steps (same recipe as PU.3) → `runs/<today>/metrics.json`; export to the
   `.mlpackage`; **score** twice with `--boxes ../../ios/.build/pump-reader-out/slices.json`:
   all windows, and the count-correct subset (add `--only-count-correct` if the scorer does not
   already separate them; PU.4's report got 0.175 on the 173 count-correct windows - find how).
   Write both lines next to the PU.3/PU.4 lines in `REPORT.md` → "Held-out score".

## Tests

- Existing 14 stay green; the two profiles-differ tests must still pass after the ratio change.
- Add `test_dataset_spill.py`: a spilled sample's left/right 15 % columns contain ink from a
  neighbour in ≥ 30 % of 500 draws (oracle: the spill probability you set), and the centre
  glyph's label is unchanged (oracle: the row's own box labels).
- Add `test_contrast.py`: the contrast-collapse augment yields a sample whose on/ground
  difference is ≤ 25 % of the original in the fraction you configured (oracle: the config).
- **Mutation named by this brief:** set the spill probability to 0 - `test_dataset_spill` goes
  red; paste it.

## Out of scope

Slicer changes, Swift, the locator, `windows.json`, `expected.csv`, any change to the model
architecture (keep `SegmentNet` as is so the before/after isolates the data).

## Checks (by exit code)

`.venv/bin/pytest -q` → 0, count ≥ 16; train → 0; export → 0; score → 0 twice.
No iOS gate (nothing compiled changes; the `.mlpackage` is a resource) - say so.

## Standing fences

Never stash / checkout / move files; never commit. `pgrep -x` only. Not alone in the checkout.

## Report back

Exit codes, pytest count, run-or-only-written, the red mutation output, training wall time and
validation numbers, the before/after held-out lines (all windows AND count-correct subset), model
size, and anything found and not fixed.

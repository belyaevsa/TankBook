# PU.41 - round 11: the classifier on the verified corpus, with the training material fixed first

**Parent journey:** J4. **Row:** `docs/TASKS.md` → PU.41. **Read first:** `ml/pump-reader/REPORT.md`
→ "Round 10" (the protocol and why volume is exhausted), "PU.36b" (the sampler options),
"The hand quads' own noise"; `ml/pump-reader/CORRECTIONS.md` §3; `ml/pump-reader/src/pump_reader/realglyphs.py`
(how real cells are cut, `--cap-fixture`, `--hard-weight`), `dataset.py` (the synthetic renderer:
`TECHNOLOGIES`, `TECHNOLOGY_PRIORS`, `contrast_prob`, `render_slicer_cell`), `train.py`,
`export.py`; `ios/Tests/TankbookCoreTests/PumpReaderPipelineTests.swift` (`PUMP_MODEL=` scores a
candidate; the floors: annotated **83 / 0.96**, live **39 / 0.99** on the heldout of 68 stills as of
2026-09-22).

## The situation - what the trainer is fed today (orchestrator, 2026-09-22, contact sheets)

Real pool `.out/real-r11` (40 755 cells from the slicer's export of every labelled train window
and frame), inspected by class:

1. **Label misalignment.** Every digit row holds cells that show a different glyph or half of a
   neighbour: the slicer cut them half a pitch off phase or one count off, so cell *i* carries
   label *i* over the wrong pixels. `realglyphs` only skips a window whose COUNT disagrees.
2. **The dp bit is trained on cells that do not show the dot.** 9 271 cells (23 %) carry
   `dp = 1`, but the mark sits in the gap AFTER the cell and the crop stops at the cell's edge -
   the classifier's mark bit learned nothing (PU.34b measured 0-9 % recall) and the slicer's own
   second look does the job now.
3. **The synthetic pool looks nothing like the real one**: saturated LED/VFD palettes, sharp
   segments; the real pool is ~90 % grey LCD at low contrast.

And the corpus itself grew since round 10: the owner's hand-pinned frames, per-frame labels
where a running display glitched (a glitched frame carries its own reading, not the run's -
the product owner's stated reason for this round), 26 clips read by the reader (20 294
readings, arithmetic labels where the reading closed), the Neste/Peetri night and day Live
records, and reader corrections in the ledger (`corrections` table, `proposedBy = reader`).

## Where you may write

`ml/pump-reader/src/pump_reader/{realglyphs,dataset,train}.py`, `ml/pump-reader/tests/`,
`ml/pump-reader/REPORT.md` ("Round 11"), `ml/pump-reader/runs/2026-09-22/` (metrics; never the
checkpoints - `.out/` holds those, gitignored), and **only if a seed ships**:
`ios/App/Resources/PumpSegments.mlpackage` and the two floor constants in
`PumpReaderPipelineTests.swift`. **Not** the Swift reader, the slicer, anything under `Spike/`
(the corpus is read through `corpus_db`), `scripts/corpus_db.py` / `tools/pump-annotate/`
(another session is editing them - do not touch, and if `corpus_db` fails to import, say so and
stop). The Swift export under `ios/.build/pump-reader-out/train/` exists; do not re-run the Swift
export unless it is missing (15 min, and the tree may be building).

## Write code first, explore second

## What to build, in order, each measured

1. **The centred-ink filter** in `realglyphs.py` (`--centred 0.25`, default off): a real cell
   is kept only when the column-ink centroid of its crop lies within ±25 % of the cell's width
   from the centre (ink = darker than the crop's median for a dark-on-light strip, the reverse
   otherwise - the slicer's polarity rule). Report how many cells it drops per class and per
   fixture; regenerate the contact sheet (`/tmp/real-cells.png`'s recipe is in the session:
   18 random cells per class, labels from `SegmentLabel(bits).digit`) so the orchestrator can
   look at the result - write it to `ml/pump-reader/runs/2026-09-22/real-cells-centred.png`.
2. **The dp crop** (`--dp-crop gap|none`, default `none`): `gap` widens every cell's crop to the
   right by 0.4 × pitch before the 32×48 resample, so a mark is inside the pixels the bit is
   trained on (and the label stays as labelled); `none` sets every cell's dp bit to 0 in the
   label and drops the dp term from the loss (`train.py`) - the slicer owns the mark now
   (PU.34b), and a bit that cannot see its evidence only adds noise. Measure both against the
   heldout's dp agreement print; pick by the number.
3. **The synthetic profile toward the real one**: `TECHNOLOGY_PRIORS` weighted to LCD (start at
   lcd 0.8 / led 0.15 / vfd 0.05), `contrast_prob` raised (start 0.5), a grey-panel palette
   band that matches the real pool's median contrast (measure it: the real cells' ink/panel
   contrast distribution, print its quartiles, and make the renderer's contrast draw from it).
   Regenerate the synthetic sheet beside the real one.
4. **The pool**: `--cap-fixture 0.02 --hard-weight 4 --centred 0.25 --dp-crop <winner>` with
   `--also` the videos' export; print the composition per make, per source, the glitch-labelled
   frame count (a frame whose label differs from both neighbours in its run), and the top-10
   fixtures by share.
5. **Three seeds**, round 10's recipe (`--steps 15000 --real <pool> --real-frac 0.3`), exported
   and scored with `PUMP_MODEL=` on the heldout (`swift test --filter PumpReaderPipelineTests`,
   ~6 min each). The table beside round 10's in REPORT.md. **Ship** (copy to the bundle, raise
   the floors to the run) only if all three seeds clear both floors AND the annotated tier moves
   by more than ±2 cells; otherwise round 6 stays and the report says which of steps 1-3 helped
   on their own (score at least the pool-only variant, i.e. step 4 without 1-3, so the data
   fixes are separable from the corpus growth).

## Explicitly out of scope

The slicer (PU.42 runs beside you), the detector, the app, the annotator, the heldout split.

## Tests

- `ml/pump-reader/.venv/bin/pytest -q ml/pump-reader/tests` → 0 with the count (33 now +
  yours): the centred filter drops a synthetic cell whose ink sits in the outer quarter and
  keeps a centred one; `--dp-crop gap` widens the crop and `none` zeroes the bit; the priors
  sum to one and LCD dominates.
- **Mutation named by this brief:** in the centred filter, compare against the cell's LEFT
  edge instead of its centre - the "keeps a centred one" test goes red. Paste red and green
  verbatim.
- Vacuous traps: a filter test on a cell with no ink; a seed table without the pool-only
  control; a floor raised past the run.

## Checks (by exit code)

pytest → 0 with the count; each `train`/`export` → 0 with wall time; each `PUMP_MODEL=` score
line verbatim; if the bundle changes, `scripts/gate.sh` → report each step (RV.302's red is
pre-existing) and the app-target bundle separately.

## Report back

The drop counts of the centred filter; the dp variant that won and its dp agreement; the
contrast quartiles and the synthetic sheet path; the pool composition; the seed table (pool-only
control + the full recipe, three seeds each); whether anything shipped and the floors; the
mutation red/green verbatim; pytest count; anything found and not fixed with the row that owns it.

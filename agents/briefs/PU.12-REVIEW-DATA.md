# PU.12-REVIEW-DATA - review the pump-reader TRAINING MATERIAL with one goal: a better model

**Read-only.** You write exactly ONE file: `agents/reviews/PU.12-REVIEW-DATA.md`. No code, no
tests, no training, no `/tmp`. You may run `ml/pump-reader/.venv/bin/python -m pump_reader.render`
into `ml/pump-reader/.out/review/` and `score.py --dump` to inspect samples by filename; you may
read every file. You may NOT open the real fixture images by hand - the corpus is held-out and
the reader is only ever measured on it, never tuned to it. The annotation file
`Spike/ReceiptSpike/fixtures/pump/windows.json` and `expected.csv` are yours to read.

## What this is

Tankbook reads fuel-pump displays with its own seven-segment reader: `docs/EXTRACTION.md` → "The
pump reader" (read first), `ml/pump-reader/REPORT.md` (read all of it - it records what was tried,
what helped and what hurt, with numbers). The model trains on **synthetic** glyphs only:

- `profiles.py`: five make profiles (segment geometry, slant, pitch, dp), technology palettes.
- `glyph.py`, `row.py`: the renderer; `augment.py`: glare, blur, perspective, LCD ghosting,
  canopy reflection, contrast collapse, noise/exposure, occlusion, with `DEFAULT_PROBS`.
- `dataset.py`: `SyntheticDataset` → `render_slicer_cell`: a short row is rendered, the target's
  cell is cut one pitch wide over the row's ink band (the way the Swift slicer cuts real cells),
  resized to 32×48; `LCD_PALETTES` (six families), `TECHNOLOGY_PRIORS` 85/10/5, label priors.
- `runs/2026-09-19/train-sheet-before.png` / `train-sheet-after.png`: 96 training samples before
  and after the last review round; `held-out-cells-r2.png` and `score.py --dump` output: the real
  cells, filenames `<fixture>-<field>-<i>-<truth>-<read>.png`.

**What the last two rounds found** (REPORT.md): neighbour spill and contrast-collapse augments
HURT held-out even though both are real; bold segments and italic slant helped; the ghost colour
sampled lighter than the ground was a large defect; framing the training cell like the slicer's
doubled the number; broadening the LCD palettes and taming augmentation doubled it again. Now:
per-glyph **0.400** on count-correct real windows, per-segment a .85 b .79 c .81 d .83 e .88 f .83
g .86 dp .74; synthetic validation 0.97 per-digit - so the gap is entirely synthetic→real.

## What to review, in order - each with a concrete, testable proposal

1. **Fidelity of the glyph itself.** Read `profiles.py` and `glyph.py` against what you know of
   real pump heads (Gilbarco Veeder-Root, Dresser Wayne, Tokheim, Scheidt & Bachmann, Lukoil
   heads): segment shape (hexagonal vs chamfered rectangles), the gap between segments, the
   dp's shape and position (comma vs dot, below baseline), inter-glyph spacing, zero-padded
   leading zeros drawn as dim `0`s, the `1` glyph's position within its cell, multi-row displays.
   Which of these are wrong or missing?
2. **Fidelity of the surface.** LCD polariser colour cast, viewing-angle darkening, the
   transflective backlight gradient, dirt and scratches on the window, rain droplets,
   photographer reflection, sensor noise at night, JPEG artefacts at the cell scale (a cell is
   ~30–60 px in the photo). Which are missing, which are overdone (the sheet said blur and
   occlusion were), and what is the cheapest way to add each?
3. **The sampling distribution.** Label priors (blank 8 %, dp-only 8 %, digits uniform),
   technology priors, make priors uniform, augmentation probabilities. Compare to what the corpus
   distribution must be (from `windows.json` strings and `expected.csv` alone: which digits,
   how many leading zeros, dp frequency per field, per-make counts). Where is the mismatch?
4. **The framing.** `render_slicer_cell` vs the Swift slicer's real cells: what does a real cell
   carry that the synthetic one never does (partial neighbour, cut segments, non-uniform
   background, the strip's own resampling)? Propose a way to generate cells by running the SAME
   slicing code on synthetic rows (a `slices.json`-style oracle) instead of imitating it.
5. **Would a small amount of real data change the game?** The corpus is held-out by design. Argue
   both sides: a held-out split (e.g. by station or by make) for fine-tuning vs keeping it pure,
   and what a self-training / pseudo-label loop over the user's own future captures would need.

## Questions back to the product owner

End with **"What I would need to know or have"**: ranked, specific asks - which makes and
countries to photograph next, night vs day, whether a burst/video capture would be available at
inference, whether glyph-level annotation of a subset is affordable, anything that would make the
synthetic renders provably closer to the photographs.

## Report

`agents/reviews/PU.12-REVIEW-DATA.md`: findings ranked by expected gain per unit of work, each
with the file:line, the proposal, and the number in REPORT.md it should move. Then the questions.
No code changes.

# PU.11-REVIEW-IMPL - review the pump-reader IMPLEMENTATION with one goal: a better model

**Read-only.** You write exactly ONE file: `agents/reviews/PU.11-REVIEW-IMPL.md`. Nothing else, no
code, no tests, no `/tmp`. You may run existing commands (`pytest`, `score`, `swift test --filter
PumpReader`) to check a claim; you may not train.

## What this is

Tankbook reads fuel-pump displays (seven-segment LCD/LED) with its own reader instead of OCR:
`docs/EXTRACTION.md` → "The pump reader" (read first), rows PU.1–PU.10 in `docs/TASKS.md`, the
running record in `ml/pump-reader/REPORT.md` (read all of it - every measured number and every
wrong turn is there). The pipeline today:

- **Python, `ml/pump-reader/src/pump_reader/`**: `profiles.py` (make profiles), `glyph.py` /
  `row.py` (renderer), `augment.py`, `dataset.py` (the training cell, framed like the slicer's),
  `model.py` (`SegmentNet`, 3 conv blocks → 8 sigmoid segment outputs a–g + dp), `train.py`,
  `export.py` (Core ML), `score.py` (held-out scorer over the real windows).
- **Swift, `ios/Sources/TankbookCore/Extraction/PumpReader/`**: `PumpQuadWarp` (quad → strip),
  `PumpGlyphSlicer` (polarity, Otsu on the column profile, local contrast normalisation,
  autocorrelation pitch, grid snap anchored on the first occupied cell, split merge, short-count
  retry), `PumpPanelLocator` (stub, median IoU 0.008). Tests in `ios/Tests/TankbookCoreTests/PumpReader*`.
- **Oracle**: `Spike/ReceiptSpike/fixtures/pump/windows.json`, 114 real photos × hand-annotated
  number windows; the corpus is HELD-OUT, nothing real is trained on.

**Where it stands** (all reproduced by the orchestrator): slicer count agreement 259/433 (0.598);
classifier per-glyph on count-correct windows **0.400**, on all windows 0.309; per-segment on
count-correct cells a .85 b .79 c .81 d .83 e .88 f .83 g .86 dp .74; per-window ~0. The ship gate
(`PumpPhotoGate`) needs ≥ 0.99 precision on committed *fields*. Look at
`ml/pump-reader/runs/2026-09-19/held-out-cells-r2.png` (real cells with truth>read) and
`train-sheet-after.png` (what it trains on) - you cannot see images, but the filenames encode
truth and read, and `score.py --dump` writes `<fixture>-<field>-<i>-<truth>-<read>.png`.

## What to review, in order - each with a concrete, testable proposal

1. **The slicer** (`PumpGlyphSlicer.swift`). 40 % of windows still get the wrong glyph count, and
   a miscounted window is unreadable. Read the code against the per-make table in
   `docs/TASKS.md` PU.8 (Scheidt 0.30, Lukoil 0.10, Wayne 0.53). Is column projection the
   right primitive at all for glare-split and faint glyphs? What would you replace or add
   (e.g. a learned cell-boundary head, template matching on the pitch grid, using the
   classifier's own confidence to choose among candidate segmentations)? Which of PU.8's four
   seams are load-bearing and which are noise?
2. **The classifier** (`model.py`, `dataset.py`, `train.py`). 32×48 RGB input, ~100 k params.
   Is 8 independent sigmoids the right head, or should a 12-class digit head (or both, multi-task)
   be added so decoding can use digit priors? Would grayscale input, a larger input, test-time
   augmentation, or a per-segment attention/spatial prior help a seven-segment problem specifically?
   Is BCE with a 0.5 threshold the right decoder given the downstream arithmetic cross-check
   wants ranked candidates?
3. **The framing contract** between the two halves: the Swift slicer cuts cells one way
   (`PumpReaderHarnessTests` writes `slices.json`), the Python `render_slicer_cell` imitates it.
   Find every place they can disagree (band trim, pitch slack, resampling, colour space, the
   dp's position) - a framing change alone moved the number by a third once (REPORT.md →
   "The shipped recipe").
4. **The scorer** (`score.py`): does it measure what the gate needs? Per-window requires every
   glyph AND its dp; is that the right unit, and what should a "committed field" mean here?
5. **The decoding that does not exist yet** (PU.5): row assignment and decimal recovery via
   `volume × price = total`. Sketch how you would use it to REPAIR reads (P2.13 already has a
   fixed 9-as-4 confusion table), and what the classifier must output for that to work.

## Questions back to the product owner

End the review with a section **"What I would need to know or have"** - the questions and
materials that would let the reader improve fastest: more photos of which makes, video instead
of stills, the phone's raw frames vs. JPEG, annotations at glyph level, a second annotator,
anything. Be specific and rank them.

## Report

`agents/reviews/PU.11-REVIEW-IMPL.md`: findings ranked by expected gain per unit of work, each
with the file:line it concerns, the proposal, and how it would be measured (which number in
REPORT.md moves). Then the questions section. No code changes.

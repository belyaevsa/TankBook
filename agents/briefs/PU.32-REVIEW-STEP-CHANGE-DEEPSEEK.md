# PU.32-REVIEW-STEP-CHANGE - what would DRASTICALLY raise the pump reader's quality?

**Read-only.** You write exactly ONE file: `agents/reviews/PU.32-REVIEW-STEP-CHANGE-deepseek.md`. No code. No `/tmp`.
Read before you write; every claim you make must point at a file, a number or a fixture.

## Where the reader stands (2026-09-20, all numbers on the held-out split, decision 9)

Read `docs/EXTRACTION.md` -> "The pump reader" and its decisions 1-9, then `ml/pump-reader/REPORT.md`
rounds 5-9, then `docs/TASKS.md` rows PU.24, PU.30, PU.31, then the code under
`ios/Sources/TankbookCore/Extraction/PumpReader/` (locator, verifier in `PumpReader.swift`, slicer,
row assignment, classifier wrapper, law) and `ml/pump-reader/src/pump_reader/` (renderer, dataset,
train, realglyphs, track).

The corpus: 217 pump stills (`Spike/ReceiptSpike/fixtures/pump/`, annotated in `windows.json`, 64
held out by `split.csv`), 88 Live Photo records tracked into 2 766 frames, 4 running-display videos
(4 010 frames, 196 labelled), receipts for 20 matched fills. Head types: Wayne/Dresser (~90), Gilbarco
(~45), Gilbarco Veeder-Root keypad (~35), Tokheim (~20), Tatsuno, Scheidt & Bachmann, Wayne Pignone;
13 currencies; comma and point decimals; zero padding; one-decimal totals.

The pipeline, and where it loses on the 64 held-out stills (`PumpLivePathDiagnosticTests` funnel):

| stage | number |
|---|---|
| locator (Vision text boxes + classical projection) puts a candidate on a true row | 29 / 31 photos |
| verifier keeps a true row (slicer >= 3 cells, aspect, height, edge, margin >= 1.0) | 25 / 31 |
| two transaction rows verified | 17 / 31 |
| row assignment gives the right roles | 15 / 31 |
| **live path commits** (photo in, nothing else) | **11 cells, all correct, 3 / 64 photos** |
| annotated windows + law (the classifier's ceiling with perfect localisation) | 66 committed at 0.970, 18 / 64 photos every field right |
| slicer count agreement on annotated windows | 210 / 238 |
| classifier per-cell (synthetic val) | 0.85; on real cells the law's precision is the only real number |

Three retrains with real glyphs (rounds 6/8/9, 25k-30k real cells from the train split at 30 % of
each batch) land within 7 committed cells of each other on 175, and the live path moved 11 -> 4 -> 2
across them because the verifier's margin threshold was fitted to round 6. The product owner asks:
**what would change this by a step, not a percent?** More corpus? Which corpus? Which engineering?

## What to answer, each with a concrete proposal, an expected effect and its cost

1. **Architecture.** Is the pipeline (find rows -> slice cells -> classify 8 segments per cell ->
   arithmetic law) the right one, or is its ceiling structural? Compare against: (a) a single
   detector+recognizer (e.g. a small CRNN/CTC over the whole row, no slicer), (b) a display-level
   detector (YOLO-nano class) feeding the existing cell classifier, (c) keeping the pipeline and
   fixing its weakest stage. For each: what it needs from the corpus, what it costs on device
   (iPhone 12, iOS 18, Core ML), and what it would plausibly reach on the held-out split. Name the
   stage you would replace first and why the funnel above says so.
2. **The slicer.** 28 of 238 held-out windows miscount; on the train export 25 % of windows do.
   Is a hand-built projection slicer the right tool, or should cell segmentation be learned
   (per-column ink/gap classifier, or the CTC path that needs no slicer)? What does the corpus
   give you for that today (annotated quads + text, no per-cell boxes)?
3. **The locator / verifier.** Vision's text-box proposals miss 2 of 31 photos entirely and rank
   the true rows low; the verifier drops true rows at margins 0.7-1.1 and by count. Propose the
   locator you would build with 217 annotated stills + 2 766 tracked frames as boxes, and what
   recall/precision it would need to make the live path match the annotated path.
4. **Training data.** Synthetic renders (120k/run) + real cells (30k). Is the real share too small,
   too large, wrongly sampled (per-frame near-duplicates dominate)? Would per-fixture balancing,
   hard-example mining on the verifier's misses, or a real-only fine-tune stage change anything?
   How many stills / heads / countries would the corpus need for the next doubling to matter, and
   which kinds (say which head types and conditions are under-represented, from the fixtures).
5. **Measurement.** 175 held-out cells is small; a retrain moves +-7. What is the minimum
   evaluation the owner should insist on before believing a number (seeds, bootstrap CI, per-head
   breakdown)? Is the 70/30 split the right shape, or should it be per-head stratified?
6. **The law and the ship gate.** `PumpPhotoGate` wants precision >= 0.99 at coverage >= 0.60.
   Given what the arithmetic can and cannot disambiguate (`PumpReadingLawTests`, PU.13 §4), is
   that gate reachable with this pipeline at all? If not, what gate is, and what would the app do
   with it (hard rules 13 and 15: suggest, never trust; typing is a peer path).
7. **The one thing.** If the owner can do exactly one thing next week - capture 200 more stills of
   kind X, or build Y - which, and what number on the held-out split would it move to?

Rank your proposals by (expected effect on the live path) / (cost). Be specific about what you
could not verify. Do not propose collecting "more data" without saying which data and why the
current 217 do not already contain it.

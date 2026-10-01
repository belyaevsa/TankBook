# PU.91-REVIEW (kimi) - the row locator: is the problem stated right, and what should the next round do?

*A second, independent opinion on the same question is being written in parallel by another agent
into a different file. Do not read it - the value is that the two were reached independently.*

**Read-only.** You write exactly ONE file: `agents/reviews/PU.91-REVIEW-kimi.md`. No code, no
edits to the corpus, the docs or the models - name what you would change, why, and how it would be
measured. Scratch, if you need any, is `ml/pump-reader/.out/review-pu91/`; never `/tmp`. **Do not
train, export or run the Vision/live suites**: the GPU is busy with the orchestrator's training runs
and a live run takes 4-10 minutes of the CPU. Reading files, running `scripts/pump-live-diff.py` on
the ledgers, `python` over the JSON, and quick unit tests (`pytest scripts/pump_live_diff_test.py`)
are fine. Other agents and a second Claude session work in this checkout: read anything, write
nothing but your own review, never move, rename or delete a file you did not create, and do not be
surprised by files changing under you.

## The product and the pipeline, in two paragraphs

Tankbook reads a fuel-pump display from a phone photo (total, volume, unit price). The app's path:
**RowSeg** (a PixelLink pixel + link segmenter, 0.91 M params, 512 px input, oriented quads -
`ml/pump-reader/src/pump_reader/segnet.py`, `segtrain.py`) finds the number rows ->
the verifier keeps plausible rows and decides whether the photo is a display at all ->
row assignment gives each row its role -> each row is warped to a 96 px strip, **widened by a
margin** (`PumpReader.detectedMarginHorizontal = 0.1` row heights each side, vertical 0) ->
the row reader (a CRNN + CTC, `RowRead.mlpackage`) reads the strip -> **the law**
(`PumpReadingLaw.swift`) commits a field only when total = volume x price closes, and otherwise
abstains. A wrong number costs far more than a missing one (hard rule 13 - the user edits the form).

The locator is judged in training by a rotated-IoU gate against hand quads (`rotgate.py`,
`segeval.py`: median IoU, recall@0.7, false rows per photo). What ships is judged by the **app
path on the 68 frozen heldout photos**: committed cells, precision >= 0.98, and no wrong cell
without a caution; measured on the iOS 27 simulator. `PumpPhotoGate.swift` holds the marks.

## What was done (2026-09-28..30) and what it showed

All live numbers below are the app path on the 68 heldout photos (183 scored cells). "macOS" runs
are `swift test` on the Mac (a few cells off the simulator by design); the simulator is the
measured runtime.

**The data.** seg-r1 (shipped): 256 train stills + 275 owner-verified frames + 116 non-pump
negatives. seg-r2 and D/B below: 284 stills + 288 verified frames + 128 negatives (the new material
is mostly black-LCD, TFT and night heads). Frames come from Live Photos / videos; only frames the
owner verified in the annotator train (a tracker's box drifts). Thousands of tracked but unverified
dark frames exist.

**The results table** (macOS unless marked; locator gate on the heldout; "dark" = the 5 dark
heldout2 stills, 27 windows):

| Model / setting | Locator gate: median IoU / recall@0.7 / false rows per photo | Dark recall@0.7 | Digit coverage: windows >= 97 % inside the found box | Live committed / correct |
|---|---|---|---|---|
| seg-r1 (shipped) | 0.861 / 0.885 / 0.088 | 15/27 | 160/252 | 126/125 (sim 128/127) |
| seg-r2 (new data, from scratch) | 0.857 / 0.889 / 0.074 | 19/27 | 151/252 | 130/127 (0.977) - refused |
| A: r1 + wider read margins (4 settings) | = r1 | = r1 | - | 104/103 .. 123/121: all worse |
| **F: r1 + a second read at wide margins (0.3 / 0.1) when the first read commits < 3 fields; keep the reading with more committed fields** | = r1 | = r1 | = r1 | **140/138 (sim 142/140; ship score 141 -> 147/186)** |
| r2 + F | as r2 | 19/27 | 151/252 | 139/136 (0.978) |
| D: r1 fine-tuned on r2's data (warm start, lr 3e-4, 10 k steps) + F | 0.862 / 0.893 / 0.059 | 19/27 | 171/252 | 134/132 |
| B: r2's data, training targets padded 3 % width / 5 % height per side + F | 0.775 / 0.762 / 0.088 | 10/27 | **195/252** | 115/112 (0.974) |
| C1, C2: r1's exact data, seeds 1 and 2 | *training - results not in* | | | |
| E: r2's data + 266 unverified dark frames where seg-r2 and the tracker agree (pseudo-labels) | *queued* | | | |

**The observations that frame the question:**

1. **Box sensitivity of the reader** (hand quads, no locator, reader + law only): hand boxes 159/159
   right; 6 % wider 160/160; 10 % taller 160/160; **6 % narrower 129; 10 % shorter 152; shifted
   down 8 % of height 123; shifted right 3 % of width 135**; 2 % corner jitter 153. Cutting a
   digit costs heavily, overshooting costs nothing - on hand boxes.
2. **But widening the locator's boxes at read time (A) hurts**, and training for coverage (B) hurts
   more, although B covers the digits best. The per-photo ledgers show the losses land in the law
   (`nothingClosed`, `priceUnvalidated`, `priceOutOfBand`) and in the display decision
   (`notADisplay`), not as misread digits.
3. **The flips are not location failures.** On the photos r1 and r2 disagree on
   (`pump-055, 056, 068, 089, 095, 104, 120, 165, 170, 201`) both models find every row with IoU
   within +-0.05 of each other and no extra rows - yet whole photos flip between committing all
   three fields and none.
4. **The locator's own metrics do not predict the live read**: D beats r1 on every locator number
   (IoU, recall, false rows, coverage) and reads 6 cells fewer; B has the best coverage and reads 25
   fewer.
5. **F, a read-time change, is the only win so far**: 13 cells gained, 0 lost, 1 new cautioned
   wrong cell (`pump-055` litres 56.09 for 56.05); the cost is a second full read on photos the first
   read leaves short (the live test took 438 s instead of 228 s).
6. Dark displays (black LCD, TFT) are where the product fails in the field; r2 and D find more dark
   rows (19/27) but every new model so far loses ordinary photos on the app path.

## The question

Validate or correct this problem statement, then recommend the next experiments, ranked. In
particular:

1. **Is the diagnosis right?** Is the real bottleneck the locator, the read margin, the verifier /
   display decision, or the law's sensitivity to a few pixels - or is the heldout (68 photos, 183
   cells) too small to rank models that differ by 5-15 cells? Use the ledgers to say how many of
   the differences are within noise (C1/C2 are the orchestrator's seed test; say what result would
   mean what).
2. **What is the right quality criterion for the locator**, given observations 1-4? Propose a
   locator-level metric that predicts the app path (e.g. read-success on the locator's own boxes, a
   containment-with-tightness score, a strip-level CTC confidence) and how to validate that it
   predicts it.
3. **Would a larger corpus help, and of what?** The owner asks directly: grow the corpus? If so -
   more verified frames, more stills, more dark heads, more negatives, synthetic data, or
   pseudo-labels at scale (the thousands of tracked frames)? What quantity would move the number,
   and how would you tell?
4. **Training changes worth trying**: loss (e.g. an asymmetric loss that punishes cutting a row
   more than overshooting), end-to-end training against read success, multi-seed ensembling or
   test-time augmentation of the locator, the decode thresholds, a separate dark-display model or
   head, or anything else the code suggests.
5. **Read-time changes beyond F**: e.g. several margins or several locators per photo, voting
   across Live-photo frames, letting the law choose among candidate strips - with their cost.

For each recommendation: the expected effect, how to measure it (the app-path heldout score and the
per-photo ledger diff are the criteria that decide; say if you think they should not be), its cost,
and what result would kill it. Say plainly what you think is a dead end.

## What to read

1. `ml/pump-reader/REPORT.md` - the end: "The round protocol: every round reports its live ledger
   diff (PU.56)" and the PU.91 round-2 entry; earlier rounds for the history of "a better component
   makes the live path worse".
2. `docs/EXTRACTION.md` -> the pump reader, its decisions, and "Model registry";
   `ml/pump-reader/models.json`.
3. `docs/TASKS.md` -> the PU.90 and PU.91 rows; `agents/research/PU.90.md`.
4. The ledgers: `ml/pump-reader/runs/2026-09-30/ledgers/*.json` (r1, r1-F, r2, r2-F, D-F, B-F and
   the four margin settings) - diff any two with
   `scripts/pump-live-diff.py A.json B.json`; `ml/pump-reader/runs/2026-09-29/pu91-r2-live-diff.txt`;
   `ml/pump-reader/runs/2026-09-30/seg-r2-disagreements.json` (seg-r2 against the tracker, per
   frame, on the dark records).
5. The code: `ml/pump-reader/src/pump_reader/{segnet,segtrain,segdata,segeval,rotgate}.py`;
   `ios/Sources/TankbookCore/Extraction/PumpReader/{PumpReader.swift,PumpDisplayCapture.swift,
   PumpReadingLaw.swift,PumpRowAssignment.swift,PumpRowSegmenter.swift}` (F is uncommitted in
   `PumpDisplayCapture.classify` and `PumpReader.DetectedMargins` - read it as the working tree has
   it); `ios/Tests/TankbookCoreTests/PumpReaderPipelineTests*.swift` (the live arm).

## The report

`agents/reviews/PU.91-REVIEW-kimi.md`, in this order: (1) verdict on the problem statement - right,
partly right, wrong - with the evidence; (2) the ranked next experiments, each with effect,
measurement, cost and kill criterion; (3) the answer on corpus growth; (4) dead ends; (5) anything
in the numbers or code above that you believe is wrong or measured wrong. Cite files and ledger
rows, not impressions. En-dashes, never em-dashes.

# PU.76 spike report - option B (PixelLink: pixel + link segmentation, then a min-area rectangle)

*Built and measured by the orchestrator, 2026-09-24, from `agents/research/PU.76.md` (option B ranked
first; the astra and sol opinions read against it - sol's rank 1, "upright + fast Hough turn", is the
arm the note had already measured as churning; astra's pretrained OBB is the AGPL path that needs
the owner's licence call). Report only: nothing on the app path changes.*

## Verdict

**The locator is much better; the row's gate still fails.** Against the shipped detector, the
segmenter wins every locator measure by a wide margin and is 17x smaller. But on the app path it
commits **3 wrong cells** (the row requires zero) and reaches **58 correct**, not ~65. The framing
loss, measured as the row defines it, is **~41 cells**, not below ~15. By the row's own falsifiers
(F2, F3) the family closes unless the owner decides otherwise - the choices are in the last section.

## What was built

| Piece | File |
|---|---|
| Data: train stills, all 275 owner-verified train frames, 116 negatives - HAND QUADS, not their upright bounds; heldout written for scoring only (decision 9 asserted) | `ml/pump-reader/src/pump_reader/segdata.py` |
| Model: conv encoder to 1/32, top-down decoder to 1/2 ("2s", B2), 1 pixel + 8 link sigmoids; 0.91 M parameters (B1) | `segnet.py` |
| Targets and loss as published: overlap pixels negative, same-instance links, instance-balanced weights, OHEM r = 3, lambda = 2 | `segnet.targets`, `segnet.loss` |
| Decode as published: pixel/link thresholds, union-find, min-area rectangle; size floor from the train split's 1st percentiles (B7); confidence = the component's mean pixel probability (B3) | `segnet.decode` |
| Training: 30 000 steps, batch 8, Adam one-cycle 1e-3, MPS, ~42 min; rotation augmentation +-6 deg (55 %), +-12..25 deg (20 %) (B4) | `segtrain.py` |
| Thresholds chosen on a validation set (every 10th train still, 23 stills), never on heldout | `segeval.py` |
| The rotated gate: convex-polygon IoU vs the hand quad; `measure.swift`'s matching; a merge count for F4 | `rotgate.py` |
| The shipped detector's heldout boxes, for the same metric | `ml/pump-reader/detector/dump.swift` |
| Core ML export, mlprogram iOS 18 | `segexport.py` |
| Swift decode (union-find, rotating-calipers min-area rectangle), internal and unused by the app; parity with Python in an opt-in suite | `ios/Sources/TankbookCore/Extraction/PumpReader/PumpRowSegmenter.swift`, `ios/Tests/TankbookCoreTests/PumpRowSegmenterParityTests.swift` |
| The seam: `PumpRowDetector.init(rows:)` and `PumpRowDetector.load(contentsOf:)` (an `.mlpackage` loads the segmenter), internal; used by the tests (`PUMP_SEGMENTER`), `pump-read` and its trace server - not by the app | `PumpRowDetector.swift`, `PumpReadTool/main.swift`, `TraceServe.swift` |
| The annotator's detector picker lists the segmenters | `tools/pump-annotate/server.py` |

**Departures beyond the note's B1-B8, named here:**
- **B9 - a quadrilateral fit** in place of the rectangle (`segnet.fit_quad`, `segeval --shape quad`):
  tried because hand quads are trapezoids; measured below, not adopted.
- **B10 - the optimiser.** Paper §5.2: SGD, momentum 0.9, weight decay 5e-4, xavier init, lr 1e-3
  then 1e-2. Ours: Adam with a one-cycle schedule to 1e-3 and PyTorch's default (Kaiming-uniform)
  init. Why: the repo's classifier trains with Adam (`train.py`), the paper's schedule is for 3 GPUs
  at batch 24 over ~40-60k steps, and the spike's question is the formulation, not the optimiser.
  Cost: an unmeasured difference; the loss curve converged (`.out/seg-r1.log`: 2.6 -> 0.31).
- **B11 - augmentation beyond B4's rotations.** Paper §4.3: random rotation (0/90/180/270), crop
  with area 0.1-1 and aspect 0.5-2, resize to 512. Ours: in-plane turns (B4), a random scale
  0.7-1.25 of the fit-to-canvas size with a +-20 % placement (the paper's crop, in the form that
  keeps whole displays on the canvas), and brightness/contrast, grey and blur jitter (the
  classifier's photometric set). No 90-degree turns: the corpus is stored upright.
- **B7, the percentile, stated plainly.** The note says "99th percentile of train row shorter side
  and area". Read literally, a 99th-percentile floor would drop 99 % of real rows. The rule
  implemented is the paper's intent - drop a component smaller than what 99 % of train rows exceed
  - which is the **1st** percentile: short side 4.94 and area 57.0 on the output grid.

**Label re-pinning (B5 / F6) was not done.** The row asks for labels "re-pinned under one rule"
first; the rule is the owner's to pick (note §5.4), so this spike trained on the labels as they are.
**F6 is not measured** - the hand-vs-hand agreement stays the note's 0.745 median.

Tests: `ml/pump-reader/tests/test_segnet.py` (polygon IoU on known shapes, targets on stacked rows,
the decode separating touching rows only through the links, the merge count); the Swift parity
suite (opt-in).

## Measured

**F1 - the rotated gate** (68 heldout stills, 252 hand quads; `.out/seg-r1-eval.log`):

| | shipped DigitRows (conf >= 0.3) | segmenter (pixel 0.9, link 0.8, chosen on val) |
|---|---|---|
| median rotated IoU | 0.771 | **0.861** |
| recall @ IoU 0.7 | 168/252 = 0.667 | **223/252 = 0.885** |
| false rows / photo | 0.647 | **0.088** |
| recall @ 0.5 (never decides) | 0.865 | 0.976 |
| photos with every row | 52 | **65** |
| photos with a merged stacked pair (F4) | 3 | **1** (1.5 %, limit 5 %) |

**F1 passes; F4 passes.** A quadrilateral fit in place of the rectangle (adaptation B9, tried
because hand quads are trapezoids) leaves the gate where it is (median 0.861, recall@0.7 0.893).

**F5 - cost**: the model is **1.8 MB** (the shipped detector is 31.75 MB). Mean model time on the
Mac's MPS, including load and letterbox, 7 ms per image; the Swift decode's Release latency and the
iPhone number were not measured (the spike stopped at F2/F3).

**Swift parity** (`/tmp/agentlogs/pu76-parity.log`): 247/252 Python rows reproduced within 0.01 of the image; one photo (pump-008)
decodes 1 row in Swift against 3 in Python - a resampling difference (CoreGraphics vs OpenCV) at the
0.9 pixel threshold. The Swift arms below measure the Swift path, which is what the app would run.

**F2 / F3 - the apportionment** (178 asserted cells, 66 upright heldout stills, both runs on this
tree; `/tmp/agentlogs/pu76-apportion-{shipped,seg}.log`):

Counts are CORRECT cells except where a row says "committed"; the apportionment prints both.

| arm | shipped detector | segmenter |
|---|---|---|
| rows found by the learned detector (of 190) | 173 | **187** |
| rows kept by the verifier | 157 | **172** |
| detected windows, hand quads (committed = correct) | 106 | **114** |
| kept windows, hand quads | 85 | **100** |
| detector boxes, hand roles | 49 (49 committed) | 59 (62 committed) |
| framing loss (kept, hand quads -> detector boxes) | 36 | **41** |
| app | 47 / 47 | **61 committed / 58 correct** |

**Live path** (68 heldout stills, 183 cells; `/tmp/agentlogs/pu76-live-seg.log`): committed 61,
correct 58, precision 0.951; 19/68 photos all right (47/47 and 17/68 today). The wrong cells:
- `pump-063` total 13.19 for 13.15 - one misread total digit that the pair tier's shown-price band
  let through (EUR, 7.17 L x 1.834);
- `pump-165` unit price 459.4 for 45.94 and total 36021 for 3602.16 - a tenfold misplacement that
  still closes (RUB, 78.41 L): the segmenter's crop of that head changes the cell count the classifier
  sees.

## What the numbers say

1. **Finding and keeping rows is solved by this locator**: +14 rows found, +15 kept, and +15
   correct cells when the hand quads are read at the kept positions (85 -> 100).
2. **Reading from the segmenter's own quads still loses ~41 cells** against reading the hand quads
   at the same positions, although the quads agree with the hand quads at median IoU 0.861 and match
   their size (long side ratio median 1.008, short side 1.049). Rotated IoU does not predict what the
   slicer and classifier need; 6 of the 17 photos that lose are the same ones that lose when the hand
   quads become their upright bounds (pump-042, 055, 092, 119, 198, 275) - edge-sensitive framing.
3. **The wrong readings are downstream**: a misread through the pair tier and a tenfold close that
   the conventions table admits for RUB. Every retrain so far has produced wrong heldout readings
   where the shipped detector makes none (PU.66); this one does too.

## In the annotator

`pump-read --detector` loads a segmenter `.mlpackage` through `PumpRowDetector.load(contentsOf:)`
(the Swift decode now lives in `TankbookCore/.../PumpRowSegmenter.swift`; the app does not load it),
and the annotator's detector picker lists each `ml/pump-reader/.out/seg-*/RowSeg.mlpackage` beside
the object detectors, so the two locators can be compared by eye on any photo (live mode, compare
view).

## For the owner - the choices

- **Close the family** (the row's rule): F2 and F3 fail.
- **Or keep the locator and attack the two gaps**, each its own row: (a) framing - why a quad at
  IoU 0.86 reads worse than the hand quad (a per-edge margin sweep on the kept rows, or train the
  slicer on segmenter crops); (b) the wrong readings - pump-165's tenfold RUB close and pump-063's
  pair-tier misread are law and classifier questions, independent of the locator.
- Not measured, and required before any ship: Swift decode latency in Release, the iPhone 12 number
  (Capture Lab), and the non-pump leak battery with the segmenter.

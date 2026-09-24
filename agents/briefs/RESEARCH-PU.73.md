# RESEARCH-TO-CODE – read the published method before a row builds it

*A run of `RESEARCH-TO-CODE.md` for PU.73. Product owner, 2026-09-23: **"review the published research to apply it into the code,
instead of coming up with our own solution."** A research-grounded pump row (the PU.67 tranche in
`docs/TASKS.md`) is not briefed for building until this note exists.*

## Fill these in for the run

- **Row:** `PU.73` – The decimal-point bit, trained for its imbalance; the segment layout kept
  (`docs/TASKS.md`; this is the classifier sweep r7-r11 on hand boxes)
- **Papers the row cites:** Lin, T.-Y., Goyal, P., Girshick, R., He, K., Dollár, P. (2017). *Focal Loss
  for Dense Object Detection.* ICCV 2017, arXiv:1708.02002. For the head: the row says `SegmentNet`
  global-average-pools before `Linear(64, 8)` (`ml/pump-reader/src/pump_reader/model.py`), discarding
  the spatial layout a seven-segment code is - find the published treatment of position-sensitive
  heads for small glyph classifiers (e.g. the argument against GAP when location matters; CoordConv,
  Liu et al. 2018, arXiv:1807.03247; or a flatten/fully-connected head as in LeNet-style digit
  classifiers) and name what applies. Also PU.78's findings on the dp bit
  (`agents/research/PU.78.md` M4: dp AUC 0.52-0.55; a hard dp check would catch 4 wrong photos but
  refuse 4 correct heldout ones).
- **The code seam it lands in:** `ml/pump-reader/src/pump_reader/{model.py,train.py,realglyphs.py,export.py}`,
  `ios/Sources/TankbookCore/Extraction/PumpReader/PumpSegmentsModel.swift`.

Section 5: the training data (train split real glyphs + synthetic), the heldout annotated tier
(112/112) and live (45-47), and the dp-bit AUC on real cells; say what focal-loss gamma/alpha the paper
recommends and why they may not transfer to 8 independent sigmoids with ~20.6 % positive dp. Note that
PU.72 (calibration) runs before this row so a margin shift is not mistaken for a gain.

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:**
`agents/research/PU.73.md`. No code, no tests, no builds, no commits. Another agent or the
orchestrator may be building in this checkout; writing anything else corrupts its work.

## What the note must contain

1. **Each citation, checked.** Fetch the paper (arXiv abstract page or the publisher's) and confirm
   title, authors, year and venue. If the row's citation is wrong – a different paper at that id,
   a wrong author, a wrong year – say so first; a misattributed method is how an invented one gets
   a paper's authority. If you cannot fetch it, say that, and do not describe its method from memory.
2. **The method as published**, precisely enough to implement: the equations, the algorithm steps,
   the parameters the authors chose and the values they recommend, and the data they measured it on.
   Quote the paper's section and equation numbers.
3. **The mapping onto this code.** Which function the method replaces or extends (`file:line`), what
   its inputs and outputs become in our types, and which of our constants it retires.
4. **Every adaptation, named and justified.** On-device constraints (iOS 18.0, iPhone 12, Core ML /
   Vision / Accelerate / Metal, a C or C++ target inside `ios/Sources/TankbookCore` if the method
   needs one), a seven-segment display rather than the paper's domain, our corpus size. An adaptation
   is a departure from the published method: each one says what the paper did, what we will do
   instead, and why. **A departure the row's implementer adds later, not listed here, needs the
   product owner's OK** – that is the fence that keeps "apply the research" from drifting back into
   "invent something that looks like it".
5. **What the paper measured, and what we expect on our corpus** – with the population we will
   measure over, counted from the corpus at today's commit (`docs/DEVELOPMENT-TIMELINE.md`,
   2026-09-22: a brief counts its population), the file and filter that counted it, and the result
   that would falsify the row.
6. **Cost:** latency (a Release number, never Debug), bundle size, and new code to maintain.

Evidence rules as everywhere: every claim cites a paper section, a `file:line` or a measured number;
inference is labelled as inference.

**Context for every note in this tranche.** The measurement instrument is PU.68's
(`agents/research/PU.68.md`, `PumpPrecisionBounds`): report every precision with its Wilson interval;
the heldout app path today is 45/45 (`PumpReaderPipelineTests.livePath`), the annotated tier 112/112
(`gateMirror`), the reviewed train split 124/117 in-sample (`PUMP_CERTIFY=1`). The corpus scorer's
tolerance is 0.005 (`CorpusScorer.tolerance`) - never quote a number scored any other way. PU.78
(a last-digit misread validated as agreement) is being researched in parallel; PU.67 (row deskew on a
refusal) is held on it.

**The standing fences appended below were written for build briefs.** Their write and
stash/checkout rules apply to you (building `pump-read` into `ios/.build/opt` if missing is allowed -
build output only); their standing checks do not. The orchestrator and other agents are working in
this checkout at the same time.

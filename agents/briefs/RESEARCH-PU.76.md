# RESEARCH-TO-CODE – read the published method before a row builds it

*A run of `RESEARCH-TO-CODE.md` for PU.76. Product owner, 2026-09-23: **"review the published research to apply it into the code,
instead of coming up with our own solution."** A research-grounded pump row (the PU.67 tranche in
`docs/TASKS.md`) is not briefed for building until this note exists.*

*Scope (product owner, 2026-09-24): a note is written only for a row that changes the law, a model, or
the statistics. Engineering and derived rows name their sources in a line of their brief instead;
the completeness review runs on every row either way (`docs/DEVELOPMENT-TIMELINE.md`).*

## Fill these in for the run

- **Row:** `PU.76` – an oriented row detector: quads, not upright boxes (`docs/TASKS.md`; read it and
  the evidence it rests on: hand boxes read as upright rectangles commit 89 at 0.944, the same hand
  boxes as quads 111 at 0.991 - `docs/EXTRACTION.md` -> the PU.64 apportionment paragraph; PU.66's
  three refused rotated-data retrains; PU.70's cut (the detector frames a turned row as a small upright
  box - pump-302's hand row spans 0.30 of the frame, the detector's 0.10); PU.69's fast Hough angle and
  its confidence, available to any detector that outputs an angle)
- **Papers the row cites (verify each; the row itself flags one misattribution):** TextBoxes++ (Liao,
  Shi, Bai, 2018 - the quadrilateral version; the 2017 TextBoxes id arXiv:1611.06779 is horizontal
  boxes); Ma et al., *Arbitrary-Oriented Scene Text Detection via Rotation Proposals*, TPAMI 2018,
  arXiv:1703.01086; Deng et al., *PixelLink*, AAAI 2018, arXiv:1801.01315; Xie et al., *Oriented
  R-CNN*, ICCV 2021, arXiv:2108.05699. Also survey what actually runs on-device on iOS 18 today:
  rotated-box heads in small one-stage detectors (e.g. YOLO-family OBB variants and their Core ML
  export), segmentation-then-min-area-rectangle (PixelLink's shape), and the cheapest option of all -
  keeping Create ML's upright detector and turning each row with PU.69's angle before the verifier.
- **The code seam:** `ios/Sources/TankbookCore/Extraction/PumpReader/PumpRowDetector.swift` (the
  Create ML wrapper, upright boxes only), `PumpReader.candidates` / `PumpReader.deskewed`, the
  verifier `PumpRowGeometry.swift`, training in `ml/pump-reader/detector/{train,measure}.swift` and
  `ml/pump-reader/src/pump_reader/detdata.py`, decision 10's gate (tight IoU) in `docs/EXTRACTION.md`.

This is the plan's most valuable open research, and the method choice is unsettled - that is why it
is on this model. The note must RANK the options for THIS corpus and device (iPhone 12 floor,
Core ML, bundle size against the 31 MB detector), each with: its expected effect on the apportionment
(framing loss 33 cells today), what training data it needs (the hand quads exist; say how many and
how consistent they are - measure the owner's hand-quad agreement where two quads cover one row),
its conversion risk to Core ML, and the spike that would falsify it cheaply. Name the one to spike
first and why.

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:**
`agents/research/PU.76.md`. No code, no tests, no builds, no commits. Another agent or the
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

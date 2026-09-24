# RESEARCH-TO-CODE – read the published method before a row builds it

*A run of `RESEARCH-TO-CODE.md` for PU.77. Product owner, 2026-09-23: **"review the published research to apply it into the code,
instead of coming up with our own solution."** A research-grounded pump row (the PU.67 tranche in
`docs/TASKS.md`) is not briefed for building until this note exists.*

*Scope (product owner, 2026-09-24): a note is written only for a row that changes the law, a model, or
the statistics. Engineering and derived rows name their sources in a line of their brief instead;
the completeness review runs on every row either way (`docs/DEVELOPMENT-TIMELINE.md`).*

## Fill these in for the run

- **Row:** `PU.77` – a row-level sequence reader, offline spike first (`docs/TASKS.md`)
- **Papers the row cites:** Shi, Bai, Yao, *An End-to-End Trainable Neural Network for Image-based
  Sequence Recognition*, TPAMI 2017, arXiv:1507.05717 (CRNN); Graves et al., *Connectionist Temporal
  Classification*, ICML 2006; Jaderberg et al., *Spatial Transformer Networks*, NeurIPS 2015,
  arXiv:1506.02025; Baek et al., *What Is Wrong With Scene Text Recognition Model Comparisons?*,
  ICCV 2019, arXiv:1904.01906. Also what is published on reading seven-segment and meter displays
  with sequence models (the dial-meter work, e.g. Salomon, Laroca, Menotti 2020, arXiv:2005.03106,
  and Laroca's meter-reading papers).
- **The code seam:** today the slicer (`PumpGlyphSlicer*.swift`) cuts cells and `PumpSegmentsModel`
  classifies each; the law (`PumpReadingLaw.swift`) consumes per-cell ranked digits. A sequence reader
  would replace the slicer + classifier for a row strip and must hand the law per-position posteriors.

What the note must settle before any Swift: the architecture and the loss that fit ~32x? strips of
4-7 digits with a decimal mark (CTC vs attention, with or without rectification); how its outputs map
onto the law's per-cell candidates and nat windows (PU.72's temperature tool exists for the unit);
the training data available (the train split's window strings, the synthetic renderer); and the
offline bar the row names - string accuracy on the annotated tier's strips beating today's digit-only
0.732, and the law over its posteriors committing >= the annotated tier's count at >= 0.99. Given
PU.73 found the dp mark usually sits outside the cell crop, say whether a row-level reader (which sees
the gap) changes that ceiling - it is the one structural advantage this architecture may have here.

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:**
`agents/research/PU.77.md`. No code, no tests, no builds, no commits. Another agent or the
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

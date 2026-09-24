# RESEARCH-TO-CODE – read the published method before a row builds it

*A run of `RESEARCH-TO-CODE.md` for PU.71. Product owner, 2026-09-23: **"review the published research to apply it into the code,
instead of coming up with our own solution."** A research-grounded pump row (the PU.67 tranche in
`docs/TASKS.md`) is not briefed for building until this note exists.*

## Fill these in for the run

- **Row:** `PU.71` – Fit the turned row's height to its ink with an a-contrario line test (`docs/TASKS.md`)
- **Papers the row cites:** Grompone von Gioi, R., Jakubowicz, J., Morel, J.-M., Randall, G. (2010).
  *LSD: A Fast Line Segment Detector with a False Detection Control.* IEEE TPAMI 32(4) (and the IPOL
  2012 version with code, which is the implementable reference); Akinlar, C., Topal, C. (2011).
  *EDLines: A real-time line segment detector with a false detection control.* Pattern Recognition
  Letters 32(13). Also the a-contrario framework itself (Desolneux, Moisan, Morel, *From Gestalt Theory
  to Image Analysis*, 2008 - the NFA definition).
- **The code seam it lands in:** `ios/Sources/TankbookCore/Extraction/PumpReader/PumpRowDeskew.swift`
  (the `fitsBand` path - read it, it exists and is unmeasured on the app path), `PumpGlyphSlicer.swift`
  (`prepare`/`context`, the ink band), and the history: PU.58's upright-box trim lost cells because it
  read the bezel as ink (`docs/TASKS.md` PU.58 [cut], `ml/pump-reader/REPORT.md` PU.55/PU.58).

Section 5: the population is the app path's refusal photos (deskew `.onRefusal` arm, PU.67 held;
`agents/research/PU.67.md`) and the 190 heldout hand quads (their drawn top/bottom edges are the truth
for a band fit). Say what the NFA threshold is in the papers (epsilon = 1) and what it means on a
~96-px strip. Note the dependency: PU.71 turns rows only where PU.67's retry runs, and PU.67 is held on
PU.81 (a pair-repair guard, the owner's call) - measure the band fit on hand quads regardless.

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:**
`agents/research/PU.71.md`. No code, no tests, no builds, no commits. Another agent or the
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

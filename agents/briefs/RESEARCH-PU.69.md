# RESEARCH-TO-CODE – read the published method before a row builds it

*A run of `RESEARCH-TO-CODE.md` for PU.69. Product owner, 2026-09-23: **"review the published research to apply it into the code,
instead of coming up with our own solution."** A research-grounded pump row (the PU.67 tranche in
`docs/TASKS.md`) is not briefed for building until this note exists.*

## Fill these in for the run

- **Row:** `PU.69` – Row angle by a fast Hough transform, with a confidence (`docs/TASKS.md`; read it,
  and `agents/research/PU.67.md` which verified the projection-profile family our current estimator
  belongs to and handed PU.69 two findings: the sweep is 72 trials, and the method has no reading-side
  confidence)
- **Papers the row cites:** Bezmaternykh, P., Nikolaev, D. (2019). *A Document Skew Detection Method
  Using Fast Hough Transform.* arXiv:1912.02504. Classical base: Duda & Hart (1972), CACM 15(1). Follow
  the FHT paper to its own references for the FHT itself (Brady / Nikolaev's fast Hough transform
  papers) and cite the one the algorithm actually comes from.
- **The code seam it lands in:** `ios/Sources/TankbookCore/Extraction/PumpReader/PumpRowDeskew.swift`
  (`deskew`, `profileSharpness`, the coarse/fine search, `minimumGain`), and whatever confidence it
  exposes for PU.70 (`PumpDisplayCapture` size rule `minimumWidestRowFraction`).

Section 5: the population is the 190 heldout hand quads (their drawn angle is the truth - compute it
from `windows.json` the way `agents/research/PU.67.md` §5.2 did), plus the app path. Report what
accuracy and speed the paper measured, and what our 72-trial sweep's angle error is against the hand
quads today (you may compute this with `pump-read` in a read-only way). Say whether FHT's accuracy on a
single ~240-px row strip is expected to beat the sweep, and whether a C/Accelerate kernel is needed.

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:**
`agents/research/PU.69.md`. No code, no tests, no builds, no commits. Another agent or the
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

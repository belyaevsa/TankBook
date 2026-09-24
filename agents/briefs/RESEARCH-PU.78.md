# RESEARCH-TO-CODE – read the published method before a row builds it

*A run of `RESEARCH-TO-CODE.md` for PU.78. Product owner, 2026-09-23: **"review the published research to apply it into the code,
instead of coming up with our own solution."** A research-grounded pump row (the PU.67 tranche in
`docs/TASKS.md`) is not briefed for building until this note exists.*

## Fill these in for the run

- **Row:** `PU.78` – A last-digit misread is validated as agreement (`docs/TASKS.md`)
- **The defect, measured** (read the row, `agents/reviews/PU.68-COMPLETENESS-2.md` and the PU.68 row):
  on the app path the law committed a value wrong in its last digit(s) - pump-275 total 103.31 for
  103.37 (heldout, only with deskew on), and on the train split pump-099 20.27/20.21, pump-251
  75.36/75.35, pump-266 36.28/36.29 and 66.79/66.74; plus a tenfold scale error (pump-137 5.2/52.3,
  9.5/95.6) and a mid-digit misread (pump-264 59.9/55.4). **First task, before any literature:**
  trace each of these seven cells to the law tier and rule that admitted it - run the app path
  (`ios/.build/opt/debug/pump-read <image> --detector ml/pump-reader/.out/det/DigitRows.mlmodel`
  with stdin `{"rotationCW":0,"currency":"EUR","deskew":"off"}`; pump-275 with `"deskew":"onRefusal"`;
  build it with `swift build -c debug --build-path .build/opt` in `ios/` only if missing) and read
  `PumpReadingLaw.swift` (the triple close `closingSlack`, the nat windows, the pair tier's
  `pairValidationTolerance` 0.05 and `pairAgreementTolerance` 0.005). The literature question depends
  on the answer: if the triple arithmetic closes on a misread within one cent, that is a different
  problem from the pair band admitting it.
- **Papers the row cites (starting points, verify each; follow them to what actually fits):**
  selective classification / the reject option per cell - Geifman & El-Yaniv, *Selective
  Classification for Deep Neural Networks*, NeurIPS 2017, arXiv:1705.08500, and *SelectiveNet*,
  ICML 2019, arXiv:1901.09192; constrained decoding - Hokamp & Liu, ACL 2017, arXiv:1704.07138
  (PU.74's paper); calibration - Guo et al., ICML 2017, arXiv:1706.04599 (PU.72's). Also search the
  literature on **reading meters and numeric displays with a redundancy check** (a value validated
  against another reading - e.g. meter reading, check-digit / arithmetic-consistency validation in
  document OCR such as invoice total = sum of lines) for how published systems set the tolerance of
  such a check relative to the resolution of the last digit and the reader's per-digit confidence.
- **The code seam it lands in:** `ios/Sources/TankbookCore/Extraction/PumpReader/PumpReadingLaw.swift`
  (`resolve`, `pairOutcome`, the closing and repair tiers), `PumpReadingTypes.swift`
  (`PumpCellReading` posteriors), `PumpSegmentsModel.swift` (per-cell probabilities).

Section 5 must name the population: the seven cells above, the heldout app path (68 stills, 45/45
today; 52/51 with deskew on), and the reviewed train split (244 stills, 124/117 today) - counted at
your commit. The row's gate: zero wrong on heldout, the train wrong count falls, heldout commits do
not fall.

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:**
`agents/research/PU.78.md`. No code, no tests, no builds, no commits. Another agent or the
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

**The standing fences appended below were written for build briefs.** Their write and
stash/checkout rules apply to you (you may build `pump-read` into `ios/.build/opt` if it is missing -
that writes only build output); their standing checks do not. The orchestrator and another session
are working in this checkout.

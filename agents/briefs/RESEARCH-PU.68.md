# RESEARCH-TO-CODE – read the published method before a row builds it

*A run of `RESEARCH-TO-CODE.md` for PU.68. Product owner, 2026-09-23: **"review the published research to apply it into the code,
instead of coming up with our own solution."** A research-grounded pump row (the PU.67 tranche in
`docs/TASKS.md`) is not briefed for building until this note exists.*

## Fill these in for the run

- **Row:** `PU.68` – Interval estimates, a detector override, and the leak's consequences (`docs/TASKS.md`)
- **Papers the row cites:**
  - Wilson, E. B. (1927). *Probable Inference, the Law of Succession, and Statistical Inference.* Journal of the American Statistical Association 22(158): 209-212 – the score interval for a binomial proportion.
  - Angelopoulos, A. N., Bates, S. (2021). *A Gentle Introduction to Conformal Prediction and Distribution-Free Uncertainty Quantification.* arXiv:2107.07511 – conformal risk control and its related Learn-then-Test / risk-controlling prediction sets; follow its references to the primary papers it builds on for risk control (e.g. Bates et al., *Distribution-Free, Risk-Controlling Prediction Sets*; Angelopoulos et al., *Conformal Risk Control*; *Learn then Test*) and cite whichever the method actually comes from.
  Also compare, and say which fits a per-cell 0.99 precision floor on ~50-110 committed cells best: the Clopper-Pearson exact interval, and Brown, Cai & DasGupta (2001), *Interval Estimation for a Binomial Proportion*, Statistical Science 16(2) – the standard comparison of Wald / Wilson / Clopper-Pearson / Agresti-Coull.
- **The code seam it lands in:** `ios/Tests/TankbookCoreTests/PumpReaderPipelineTests.swift` (`report`, `LiveMeasurement`, `livePath`, the annotated-windows test), `ios/Sources/TankbookCore/Config/PumpPhotoGate.swift` (the precision threshold 0.99 and how it is compared), `ios/Tests/TankbookCoreTests/PumpReaderTestSupport.swift` (`detectorURL`).

What this row must decide from the literature, precisely enough to implement:
1. Which interval to print beside every committed-cell precision (Wilson vs Clopper-Pearson vs other), at what confidence, one- or two-sided, and the exact formula.
2. How a *risk-control* bound on the wrong-commit rate is computed. The pipeline's abstention thresholds (the law's nat windows) are fixed, not tuned per run - so say whether conformal risk control / Learn-then-Test applies to certifying a FIXED threshold (it is then a test on a calibration set) or only to choosing one, which split plays calibration (the train split's stills, never heldout), what exchangeability assumption it needs and whether the corpus (several photos of one fill, many photos per station) meets it - and if it does not, what the literature says to do (grouping by fill, per-group calibration).
3. What "the 0.99 floor holds" should mean once intervals exist: the point estimate, or the interval's lower bound. State what the papers imply, and the committed-cell count each reading requires to be reachable at all (e.g. how many 0-error commits make a 95 % lower bound clear 0.99). The product owner decides the gate's rule; your job is the arithmetic.
4. Counting unit: cells are not independent within a photo (the law commits a pair or a triple together). Say what the literature does with clustered binomial data (e.g. photo-level vs cell-level intervals, design effect) and which unit the interval should use.

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:**
`agents/research/PU.68.md`. No code, no tests, no builds, no commits. Another agent or the
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

**The standing fences appended below were written for build briefs.** Their "where you may write"
and "never stash/checkout" rules apply to you; their standing checks (`scripts/gate.sh`, UI suites,
screenshots) do **not** – you change no code, so do not run the gate. The orchestrator is building
and testing in this checkout while you work.

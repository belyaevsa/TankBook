# RESEARCH-TO-CODE – read the published method before a row builds it

*A run of `RESEARCH-TO-CODE.md` for PU.67. Product owner, 2026-09-23: **"review the published research to apply it into the code,
instead of coming up with our own solution."** A research-grounded pump row (the PU.67 tranche in
`docs/TASKS.md`) is not briefed for building until this note exists.*

## Fill these in for the run

- **Row:** `PU.67` – Turn the rows on a refusal, in the app (`docs/TASKS.md`; the method was built and measured under PU.65)
- **Papers the row cites:** none by name – the row says the method is a *projection-profile* skew estimate. Your first job is to find the published projection-profile skew-estimation methods it belongs to (the classical document-skew literature: projection profiles scored by a sharpness/variance criterion over candidate angles – e.g. Postl 1986, Baird 1987, and the surveys of document skew detection) and cite the ones that match, verified at the source. If a later, better-evidenced estimator for the same job exists, name it – but PU.69 already owns the fast Hough transform (Bezmaternykh & Nikolaev 2019), so do not re-derive that one.
- **The code seam it lands in:** `ios/Sources/TankbookCore/Extraction/PumpReader/PumpRowDeskew.swift` (`profileSharpness`, the angle search, the rowSize inversion past 6 deg, the in-frame crop clamp), `PumpReader.DeskewMode`, `PumpDisplayCapture.classify` (the `.onRefusal` retry) and `PumpDisplayCapture.makeReader` (where the app's mode is set).

For PU.67 the code already exists, so section 3 maps the published method onto what IS there, and section 4 lists every place our code departs from it (criterion, angle range, step, crop shape, the italic guard) – each as "the paper does X, we do Y, because Z, and the evidence is W". Section 5: the measured result is PU.65's (`docs/TASKS.md`): app path `.off` 45/45, `.onRefusal` 54/54, tilted-20 0 -> 3, leak 5/116; say what the literature would predict and whether ours is consistent.

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:**
`agents/research/PU.67.md`. No code, no tests, no builds, no commits. Another agent or the
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

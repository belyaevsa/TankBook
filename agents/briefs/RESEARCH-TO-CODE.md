# RESEARCH-TO-CODE – read the published method before a row builds it

*The template. Every run gets its own copy, `agents/briefs/RESEARCH-<row>.md`, naming one row and
its papers. Product owner, 2026-09-23: **"review the published research to apply it into the code,
instead of coming up with our own solution."** A research-grounded pump row (the PU.67 tranche in
`docs/TASKS.md`) is not briefed for building until this note exists.*

*Scope (product owner, 2026-09-24): a note is written only for a row that changes the law, a model, or
the statistics. Engineering and derived rows name their sources in a line of their brief instead;
the completeness review runs on every row either way (`docs/DEVELOPMENT-TIMELINE.md`).*

## Fill these in for the run

- **Row:** `<PU.nn>` – `<title>` (`docs/TASKS.md`)
- **Papers the row cites:** `<title, authors, year, link>` for each
- **The code seam it lands in:** `<file:line>`

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:**
`agents/research/<row>.md`. No code, no tests, no builds, no commits. Another agent or the
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

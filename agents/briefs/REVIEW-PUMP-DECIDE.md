# REVIEW-PUMP-DECIDE - what to do next about pump-display recognition

**You are a reviewer. This is READ-ONLY.** Change no file, run no build that writes a model, commit
nothing. Your output is a written decision, not a diff.

**The question, from the product owner (2026-09-22):** *"the goal - improve the recognition of
pump's photo, lift it and make it faster."* Two goals, and they are not the same goal. Say clearly
which of your recommendations serves which, and where they trade against each other.

**Scope: the WHOLE story, not the last week** (product owner, 2026-09-22, widening this brief).
This effort runs from the decision to build a trained seven-segment reader instead of using OCR,
through **54 `PU` rows (PU.1 to PU.60)**, eleven numbered decisions in `docs/EXTRACTION.md`, and a
**2101-line** round ledger in `ml/pump-reader/REPORT.md` that starts at PU.3. Read the arc end to
end before you rank anything. A review that starts at PU.43 will recommend the next increment of
a direction nobody has re-examined since it was chosen - and re-examining the direction is the
point of asking for the whole story.

So the first question is not "what is the next fix". It is: **given everything now known, is this
the right thing to be building, in the right shape?** The reader was chosen over OCR and over the
cloud model for reasons written at the time; the corpus, the measurements and four rounds of
outcomes did not exist then. If the original reasoning still holds, say so and say why it holds.
If it does not, say that plainly - **"stop, ship the gate off, and spend this effort elsewhere" is
a permitted conclusion**, and so is "the architecture is right but the unit of work is wrong".
`PU.6` is literally titled *"the ship decision, whichever way it goes"* and has never been taken.

**The failure mode you exist to prevent is a fifth round of the same shape**: a component is
improved, the end-to-end number does not move or falls, and the round is spent explaining why. Two
recent rows landed and moved the live committed count by **zero** (PU.53, PU.55). But do not stop
at the recent two - **trace the whole accuracy history through `REPORT.md`** (PU.3, PU.7, PU.9,
PU.36b, PU.37, PU.38, PU.42, PU.47, PU.51, PU.54, PU.55, PU.57 all have sections) and say what the
pattern actually is across all of it, with the numbers. Your job is to say what is worth doing, in
what order, with the evidence for each - and, just as importantly, **what to stop doing**.

## Read these, in this order

0. **The origin.** `docs/VISION.md` -> the OCR pipeline decision, and `docs/EXTRACTION.md`'s
   pump-reader section from its start - why a trained reader rather than Vision OCR, rather than
   the cloud model, rather than nothing. `CLAUDE.md` hard rule 15 carries the measured argument
   for the whole capture stance, including the pump number (`13 %` of numeric cells at the time
   it was written). `docs/JOURNEYS.md` **J4** is the journey this serves - read what the user is
   actually promised.
1. `docs/EXTRACTION.md` -> "The pump reader" **in full**, and **all eleven numbered decisions**,
   in order, with their amendments. Decision 11 has **two** amendments; the second is the product
   owner's ruling and overrules the first. The decisions are the spine of the story: each one
   records what was believed when it was made, and several were amended by measurement later -
   that pattern is itself evidence about how this work is decided.
2. `ml/pump-reader/REPORT.md` - the round-by-round ledger, **all 2101 lines**. This is the
   primary source for the whole story: every round's held-out score, what was changed, and what
   it cost. Build a timeline of the end-to-end number across every round - that table does not
   exist anywhere and making it is half your answer. Read PU.52, PU.55 and PU.53 closely, and its
   latency section (search for "decision ms"), the only real device-latency evidence there is.
3. `agents/reviews/PU.52-REVIEW-WHY-IT-LOWERED-qwen.md` - the diagnosis that named the mechanism.
   Its four ranked fixes are the last plan; **grade it**: #1 (PU.55) was refuted by measurement,
   #4 (PU.57) shipped, #3 (PU.56) is unstarted, #2 is partly PU.58. A plan that scored 1-for-4
   is evidence about how these are chosen.
4. `docs/TASKS.md` - **every `PU` row, PU.1 to PU.60** (start at the index, then read the rows).
   54 rows. Note which were closed, which were cut, and what each claimed it would move against
   what it did. `docs/TASKS-HISTORY.md` says which model did which - worth a glance if a pattern
   appears. **PU.6, the ship decision, is open and is the row this review most directly serves.**
5. `docs/DEFECT-PATTERNS.md` - the eight shapes, especially "docs naming behaviour with no call
   site" and "silently-reachable fallback".
6. The code: `ios/Sources/TankbookCore/Extraction/PumpReader/` - `PumpReader.swift`,
   `PumpPanelLocator.swift`, `PumpRowGeometry.swift`, `PumpRowAssignment.swift`,
   `PumpGlyphSlicer.swift`, `PumpSegmentsModel.swift`, `PumpReadingLaw.swift`,
   `PumpDisplayCapture.swift`.
7. `ios/Tests/TankbookCoreTests/PumpReaderPipelineTests.swift` - how the floors are measured.
8. `ios/Sources/PumpReadTool/main.swift` - the `timingsMs` instrumentation and `PUMP_REPEAT`.

## The state, as measured (do not re-derive; verify only if you doubt a number)

The funnel: **row detector** (`DigitRows.mlmodel`) -> **verifier** (`PumpRowGeometry`, model-free,
PU.47) -> **slicer** (`PumpGlyphSlicer`) -> **cell classifier** (`PumpSegments.mlpackage`, 8
sigmoids) -> **role assignment** -> **the law** (`PumpReadingLaw`, commits when the arithmetic
closes uniquely).

Two measurement tiers on 68 heldout stills: **annotated** (oracle hand quads - measures the read
stage alone) and **live** (the app's own path, end to end).

| | committed | correct | precision | photos all-right |
|---|---|---|---|---|
| live, before PU.54 | 43 | 43 | 1.000 | 14/68 |
| **live, after PU.54** | **47** | **47** | **1.000** | **16/68** |
| annotated, before | 104 | 103 | 0.990 | 30/68 |
| **annotated, after PU.54** | **112** | **111** | **0.991** | **34/68** |

**The gap between 112 and 47 is the single largest fact in this project** and it is the thing your
decision should be built around: with oracle boxes the read stage commits 112 cells; with the
app's own boxes it commits 47. Everything between the detector and the slicer is where ~65 cells
go. Say what you think the biggest contributor is and what evidence would settle it cheaply.

Shipped recently: PU.47 (verifier decoupled from the classifier), PU.51 (the law names its
refusal), PU.57 (detector re-gated on tight IoU - PU.48's retrained detector was **refused** under
it), PU.54 (the price became optional).

Ruled and not yet built: **PU.59** - a pair no shown price validates commits **with a caution**
rather than refusing, and the ship gate splits into a verified tier (0.99 floor) and a cautioned
tier (its own precision, no floor). Read its row and its brief.

Refuted by measurement, nothing shipped: **PU.55** (the clip guard - its signal does not exist;
the cell loss follows the box's *vertical* extent). **PU.53** (orientation search - built, correct,
and the committed count did not move: all five rotated stills refuse at their correct orientation
too, three of them with `boardFoundNoPrice`, which PU.54 has since eliminated - so PU.53 + PU.54
together are unmeasured and might move).

Open and unstarted: **PU.56** (per-reason/per-head ledger instead of a scalar floor), **PU.58**
(trim the strip to its ink band - running as you start; read its row), **PU.60** (role assignment
is at **0.989** against a 0.99 floor after the corpus doubled - 14 windows misassigned, upstream
of everything), **PU.49** (tilted displays), **PU.6** (the ship decision).

**Latency, the only measured numbers** (`REPORT.md`, Release build): the pump *decision* is
**13-73 ms**; `classify`+read is **112-164 ms** on a pump. Debug is 7-25x slower and is what the
test suite reports, so **a number from `swift test` is not a latency fact**. PU.53's search adds
two extra detector passes at ~3 ms each.

## What your decision must contain

1. **A ranked list of what to do next**, each item with: the measured evidence that it will move
   a number, *which* number (live committed, precision, latency, photos-all-right), roughly how
   much, and how it would be falsified. An item with no falsifier is not on the list.
2. **What to stop or cut.** Name rows that should be closed unbuilt, and say why. This is as
   valuable as the additions and nobody has done it.
3. **An explicit answer on "faster".** Against 13-73 ms decision and 112-164 ms read on device,
   is latency a real user problem or a solved one? If it is solved, say so plainly - the goal was
   stated, and the honest answer may be that accuracy is the only axis left that matters. If it
   is not solved, name the stage and the measurement that shows it. Consider also the latency the
   user actually experiences (`docs/JOURNEYS.md` J4), which is not the same as the pipeline's.
4. **A verdict on the 112 vs 47 gap** with the cheapest experiment that would apportion it
   between detection, verification, slicing and assignment. Prefer an experiment that reuses the
   oracle quads to isolate one stage at a time - that instrument already exists.
5. **A judgement on the method, not just the backlog.** Four rounds and a diagnosis review have
   produced two no-ops and one refusal. Is the unit of work wrong? Is the floor (a single scalar)
   causing this, as PU.56 argues? Should PU.56 come *first*? Say what you would change about how
   this work is chosen and measured, and route it to `docs/DEVELOPMENT-TIMELINE.md` if it is a
   change to how we work.
6. **A verdict on the direction itself.** Is a trained seven-segment reader still the right
   architecture for this problem? Consider, with evidence and against the corpus: the cloud model
   (`/extract` already exists and already reads receipts), Vision OCR on the display, a hybrid,
   and not shipping pump capture at all. Hard rule 15 says a capture is a head start and never
   the whole entry - so what does the pump door have to be worth to earn its place beside the
   receipt door and the keyboard? Answer `PU.6` if the evidence lets you: **ship, ship off, or
   what specifically is still missing before it can be answered.**
7. **The risks of what is already ruled.** PU.59 commits unvalidated pairs with a caution. That
   is the product owner's decision and is not yours to relitigate - but name what it will cost
   and what should be watched, including the F2 residue (`docs/JOURNEYS.md` F2).

## How to argue

Every claim cites a file, a line, a fixture name or a measured number. "Probably", "likely" and
"should help" are not evidence; if you are inferring, say you are inferring. If you contradict a
number in `REPORT.md` or a row in `TASKS.md`, quote it and say why it is wrong. If the right
answer is "the next thing is not a model change at all", say that.

**A note on running things**: a verification suite is running on this machine as you start, so
wall-clock timings you take yourself are contended and are not evidence. Read numbers rather than
generating them where you can; if you must measure, say the machine was loaded.

## Write your review to

`agents/reviews/PUMP-DECIDE-2026-09-22-fable.md` - **this one file is the only thing you may
write.** It must contain, as its own sections: the **end-to-end number by round, as a table,
from PU.3 to now**; your verdict on the direction; your ranked list; what to cut; and the answer
to `PU.6` or what is missing before it can be answered. End with **"If I could do exactly three
things"**, in priority order, each one sentence.

Length is not a virtue, but this is a whole-story review and the table alone will be long. Do not
compress away evidence to look concise.

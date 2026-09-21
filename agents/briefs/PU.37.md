# PU.37 - the slicer's count: the 29 heldout windows it miscounts

**Parent journey:** J4. **Row:** `docs/TASKS.md` → PU.37 (filed with this brief). **Read first:**
`ios/Sources/TankbookCore/Extraction/PumpReader/PumpGlyphSlicer.swift` end to end (it is the
subject; ~560 lines), `ios/Tests/TankbookCoreTests/PumpReaderHarnessTests.swift` (the ratchet
and what it writes), `ml/pump-reader/REPORT.md` → "PU.34", "PU.34b" and "PU.35" (the last three
slicer/locator rounds and how they were measured), `ml/pump-reader/CORRECTIONS.md` §2 and §4.

## The situation, in numbers

`PumpReaderHarnessTests.slicerRatchet` on the 64 heldout stills (hand quads, so the locator is
out of it):

    PU.4 slicer: count agreement 209/238, dp agreement 128/237
    per-make count agreement:
      circlek 7/9 (0.78)  dresser 23/30 (0.77)  gilbarco 72/80 (0.90)  scheidt 7/9 (0.78)
      tatsuno 6/6         tokheim 27/30 (0.90)  topaz 3/3            wayne 61/68 (0.90)

**29 windows out of 238 get the wrong number of cells**, and a miscounted window never reaches
the law (`PumpReader.read` drops a count the field cannot show; the harness's cell labels
misalign). After the marks (PU.34b) this is the largest read-stage loss on the annotated path
(79 cells / 22 photos of 64), and it is geometry: the same run writes every window's warped
strip and its cells to `ios/.build/pump-reader-out/slices.json` (`{ "<still>": [ { "strip":
"strips/<still>-w<i>.png", "cells": [ {x0, x1, y0, y1, isBlank, hasDecimalPoint} ] } ] }`,
normalised over the strip) and the PNGs under `ios/.build/pump-reader-out/strips/`. The truth
count per window is `PumpReaderTestSupport.glyphCount(window.text)` over `pump/windows.json`'s
`text`. Run the ratchet first (`cd ios && swift test --filter PumpReaderHarnessTests/slicerRatchet`,
~70 s) and keep its print as the before.

## Where you may write

`PumpGlyphSlicer.swift`, `ios/Tests/TankbookCoreTests/PumpGlyphSlicerTests.swift`,
`PumpReaderHarnessTests.swift` (the floor constants and their comments; a print listing the
miscounted windows with expected/got is welcome), `ml/pump-reader/REPORT.md` ("PU.37").
**Not** `PumpReader.swift`, the law, the assigner, the detector, anything under `Spike/`
(the owner's corpus - read it, never write it), the Python package, the models.

## Write code first, explore second

## What to build

1. **Name the 29.** From `slices.json` and the texts: for each miscounted heldout window,
   expected vs got, the make, and by looking at the strip PNG the failure class - the
   candidates, from the corpus's history: (a) **dim leading zeros** on a zero-padded face
   read as blanks or merged (Dresser/Gilbarco `0025,51`); (b) **glare** splitting a glyph
   into two runs or washing out a column (`pump-014`, `pump-023`, `pump-021` 3/185 windows,
   `pump-022`); (c) **a merged pair** - two glyphs whose gap is under the merge gap at that
   scale; (d) **the mark taken for a glyph** or a glyph for a mark (PU.34b's second look
   could over-fire); (e) **pitch wrong** (fundamental vs harmonic, the body check's
   `pitchToBodyMaximum` 2.2 / `pitchToBodyMinimum` 0.9). Print the table; it is the first
   deliverable and decides the rest.
2. **Fix the largest class first, measured on its own**, then the next; each fix is a
   geometric rule with a reason (§2 of CORRECTIONS.md: no threshold tuned until the 29 pass).
   Likely levers, to be confirmed by the table: the run threshold per REGION of the strip
   instead of one Otsu over the whole profile (a dim leading zero sits next to bright digits
   - a threshold that is local in x, as the LCN already is in y); the split-merge
   (`splitMergeGapFraction` 0.35 / `splitMergeWidthFraction` 1.1) admitting a glare-split
   glyph whose halves are unequal; the leading-blank rule (`leadingBlanks`) when the strip's
   left margin holds a dim zero rather than panel.
3. **Raise `countAgreementFloor`** to the measured number (0.85 now; the run decides - never
   above it) and report dp agreement, which must not fall below 128/237.
4. **The floors downstream must hold or rise**: `PumpReaderPipelineTests` annotated 79 / 0.96
   and live 37 / 0.99; `PumpReadingLawTests`; `PumpRowAssignmentTests`. A slicer change that
   lifts count agreement and drops the annotated path has traded a count for a wrong digit -
   report it and do not ship that part.

## Explicitly out of scope

The classifier, retraining, the marks (PU.34b shipped; do not touch `markRuns`/`isMarkBlob`
except where a mark is counted as a glyph), the locator, the app, the annotator.

## Tests

- `swift test` is **2218** and must not fall (one pre-existing red, `RV277ExpenseTotalTests`,
  is `RV.302`'s - report it as such). Every rule you add gets a synthetic-strip test in
  `PumpGlyphSlicerTests` that encodes the failure class from the table (a dim leading zero at
  a third of the digits' contrast is counted; a glyph split by a glare column is one glyph; two
  glyphs at the minimum gap stay two) - the real strip is the evidence, the synthetic one is
  the test.
- **Mutation named by this brief:** revert the largest class's rule (the one constant or
  branch that carries it) - its synthetic test goes red AND the count agreement print drops.
  Paste red and green verbatim.
- Vacuous traps: a test whose truth is the slicer's own output; a floor raised past the run;
  a "class" with one member fixed by a constant that only that window needs.

## Checks (by exit code)

`scripts/gate.sh` → report each step's exit and both counts (`swift test` stops at RV.302's
red - run the app-target bundle separately, `xcodebuild … -only-testing:TankbookTests test`,
281). `swiftlint lint` from the root → 0, no new warnings in touched files. No UI.

## Report back

The table of the 29 (still, field, expected, got, class); count agreement before/after per
fix and per make; dp agreement; the four downstream floors' prints; the mutation red/green
verbatim; gate exits and counts; anything found and not fixed with the row that owns it.

# PU.47 - The verifier judges on slicer geometry, never on the classifier

Row: `docs/TASKS.md` -> PU.47. The finding it answers: `ml/pump-reader/REPORT.md` round 11 (the
seed table and "the live path slides on every retrain"), and rounds 8-9 before it.

## Where you may write

`ios/Sources/TankbookCore/Extraction/PumpReader/` (a new `PumpRowGeometry.swift`; edits in
`PumpReader.swift`'s `verify`), `ios/Tests/TankbookCoreTests/PumpRowGeometryTests.swift` (new),
`ios/Tests/TankbookCoreTests/PumpReaderPipelineTests.swift` (the floor and the report table only),
`ml/pump-reader/REPORT.md` (a dated "PU.47" section). Scratch: `ios/.build/pump-reader-out/pu47/`.
Nothing under `Spike/` - the corpus is another session's live work; read it, never write it.

## What exists (read first, in order)

1. `PumpReader.swift` `verify(image:candidates:)` (~line 302-405): the current rule. A DETECTED
   candidate is kept on `shaped && !keypad`; a Vision PROPOSAL on `shaped && mean >= minimumMeanMargin`
   where `mean` is the classifier's decode margin - that is the coupling. `isKeypadRow` is the one
   geometry rule that exists; `maximumAspectPerCell`, `minimumRowHeightFraction`, `frameEdgeFraction`
   are the others.
2. `PumpGlyphSlicer.swift` (+ `Marks`, `DimGlyphs`, `Primitives`): what a cell carries - `rect`,
   `isBlank`, `hasDecimalPoint`; the pitch; the ink band. The geometry verdict is built from these
   and nothing else.
3. `ml/pump-reader/REPORT.md`: round 11's table (round 6 83/39, control 95/29, +step 3 97/36, the
   `gap` rows), PU.33's funnel (candidate on a true row 61, verified 60, two rows 50, roles right 45),
   PU.37 (the 29 miscounted windows by class - the geometry a verifier can and cannot trust).
4. `PumpReaderPipelineTests.swift`: the two paths and their floors (`liveCommittedFloor` 43 at 0.99);
   `PumpReaderTestSupport.isHeldout`/`isTrain` (decision 9 + the 2026-09-21 amendment: heldout AND
   reviewed measures; train is the split's `train`).
5. `Spike/ReceiptSpike/fixtures/pump/windows.json` `_about` and a few entries - the hand windows
   (quads + texts) are the oracle for "this is a display row".
6. `docs/EXTRACTION.md` -> "The pump reader", decisions 9 and 10.

This brief's diagnosis is a hypothesis - confirm the coupling by reading `verify` before changing
anything; if the live number moves for a reason other than the margin gate, say so and stop.

## What to build

**(a) `PumpRowGeometry`** - a pure function from a strip's `[GlyphCell]` (and the strip size) to a
verdict with named reasons, no model, no image beyond what the slicer produced:
- cell count in `[minimumVerifiedCells, PumpReadingLaw.maxCells]` (exists);
- **pitch regularity**: coefficient of variation of the non-blank cell widths under a bound;
- **ink band**: the ink rows' height as a fraction of the strip height within a range (a bezel band
  or a text line differs from a seven-segment row);
- **dp position**: a decimal mark, when present, sits at a cell index the law could use for that
  count (never the first cell, never after the last);
- **blank layout**: blanks form at most one leading run (a display's unlit leading cells); interior
  blanks beyond a bound mean a keypad or spaced text.
Every bound is a `static let` with a doc comment that names the measurement it came from.

**(b) Measure the bounds on the TRAIN split's annotated windows** (positives: each window's cells
through the current slicer) and on the Vision proposals of the same stills that overlap no
annotated window at IoU 0.3 (negatives). For each rule print the positive/negative distributions
(p5/p50/p95) and the chosen bound with its true-positive and false-positive rates; put the table in
the report. **Never look at the heldout split while choosing a bound.**

**(c) `verify` keeps a candidate on the geometry verdict** for detected AND proposed candidates; the
margin is still computed and carried in `Verdict.meanMargin` for the diagnostic print, but no
branch reads it. `isKeypadRow` folds into (a)'s blank-layout rule if it is the same thing; keep it
if it is not and say why.

**(d) The decoupling, measured.** Score the heldout live path through the new verifier with
`PUMP_MODEL=` for round 6 (`ios/App/Resources/PumpSegments.mlpackage`) and the round-11 `+step 3`
candidate (`ml/pump-reader/.out/` - the report names its file; if it is gone, retrain it with the
report's recipe and say so). The claim is that the two live numbers are within 3 cells of each
other; today they are 39 vs 36 with different verifiers. Put both, and the annotated tier, in the
report's table.

Out of scope: retraining the classifier (PU.41), the detector (PU.48), the law (PU.34), the
slicer's count (PU.37/42).

## Tests you must add

`PumpRowGeometryTests` (L1), one test per rule, each with a named positive and negative whose
oracle is a `windows.json` entry or a still the corpus names:
- pitch: positive `pump-032`'s total window cells; negative a keypad row from `pump-215` (its
  `board` cells are the price ladder; the keypad is the row of 3-4 key caps below - locate it by the
  detector or by a hand quad you write in the test, and say which);
- dp position: positive `pump-001` liters (`67.00`, dp at cell 2 of 4); negative a mark in cell 0;
- blank layout: positive `pump-215` (`00809,59`, a leading run of blanks/zeros); negative
  `pump-263`'s `CLOSED` sum window;
- ink band: positive any Gilbarco total; negative a Vision text line from the same still.
**Named mutations** (the brief names them, you run them): remove the pitch rule - the keypad
negative must be kept and its test go red; remove the blank-layout rule - the `CLOSED` negative must
be kept and go red. Paste both red-then-green outputs.
`PumpReaderPipelineTests`: `liveCommittedFloor` holds at 43 / 0.99 with round 6 (or moves up - say
which); the decoupling table from (d) is printed by the test and pasted in the report.

## Checks

`scripts/gate.sh` (the whole baseline - you change core code); `swiftlint lint` from the repo
root exit 0; `swift test --filter "PumpRowGeometryTests|PumpReaderPipelineTests|PumpReaderHarnessTests|PumpReadingLawTests"`
with counts (the pipeline suites are heldout-only and skip on macOS != 26 - if they skip, run them
with the runtime gate bypassed the way the round-11 brief did and SAY SO; a skipped suite is not a
measurement).

## Vacuous traps

A bound chosen by looking at the heldout numbers. The margin gate kept "for proposals only". A
geometry rule whose positives are the heldout windows. Reporting the live number without the
precision beside it. A `--filter` that matches nothing.

## Report back

Exit codes, counts, run-or-only-written, both mutations red-then-green verbatim, the bound table
from (b), the decoupling table from (d), and anything found and not fixed.

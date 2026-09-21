# PU.35 - the locator's geometry: box margin, stacked-row rescue, keypad rows

**Parent journey:** J4. **Row:** `docs/TASKS.md` → PU.35 (filed with this brief; the locate
stage after PU.33's detector). **Read first:** `docs/EXTRACTION.md` → "The pump reader"
(decisions 8 and 10), `ml/pump-reader/REPORT.md` → "The detector" and "Round 10" (the last
paragraph: why the lever here is geometric, not more training data), then
`PumpReader.swift` (`candidates(for:)`, `verdicts`, `verify`), `PumpRowDetector.swift`,
`PumpRowAssignment.swift`.

## The situation, in numbers (heldout split, 64 photos, `PUMP_LIVE_DIAG=1`)

    DIAG stages over 64 photos: candidate hit 61, verified hit 60, two transaction rows verified 50,
    assigned right 44, committed 11

Nothing after the assigner is this row's; the read is 29 cells / 1.000 (`PumpReaderPipelineTests`
live floor) and the mark work just moved it. This row is the 61 → 50 → 44 part, plus the detector
box edges that cost digits inside a "hit" row. The detector alone on the heldout stills
(`swift ml/pump-reader/detector/measure.swift ios/App/Resources/DigitRows.mlmodel ml/pump-reader/.out/det/heldout 0.3`):

    rows 238, recall@0.5 205 (0.861), recall@0.7 172, median IoU 0.796, false rows 42 over 64 photos,
    photos any row 59, photos all rows 49

A retrain on the whole corpus (926 images) changed none of that beyond noise (REPORT.md, round 10's
last paragraph) - so the fixes are in how the boxes are USED, not in the model.

Three named cases, all running-display frames with the owner's hand quads
(`Spike/ReceiptSpike/fixtures/pump-live/frames/<clip>/windows.json`) - read them with
`ios/.build/debug/pump-read <frame> < '{"currency":"EUR"}'` (live mode prints `rows` with
`detected`, `cells`, the normalised quad, and `rowTexts`; `swift build --product pump-read` in `ios/`):

| case | what the detector did | cost |
|---|---|---|
| video-003 `001.jpg` (Wayne, `145.41 / 70.62 / 2.059`) | total box x 0.307–0.640 vs truth 0.286–0.649: the thin leading `1` is outside; liters box 0.366–0.630 vs 0.420–0.642: starts too far left, clips the last `2` | 5 cells and 3 cells instead of 6 and 4 - two rows lost |
| video-002 `093.jpg` (Wayne, `2336.06`) | total box starts at 0.253 vs 0.226: half the `2` outside | still 6 cells (survives), but no margin to lose |
| pump-224 (Topaz, train still, `34999.72 / 714.28 / 49.00`) | the keypad's `4 5 6` row detected at 0.33; the price row at 0.38 covers only the lit digits; the liters row at **0.25** (under the 0.3 cut); the total not found | keypad row becomes "total", price becomes "liters" |

## Where you may write

`PumpReader.swift`, `PumpRowDetector.swift`, `PumpBoxRefiner.swift` (parked; may be revived or
deleted), `PumpDisplayCapture.swift` (only if the classification's row counting needs the same
rescue), `ios/Tests/TankbookCoreTests/Pump*.swift`, `ml/pump-reader/REPORT.md` ("PU.35"),
`docs/EXTRACTION.md` (decision 10's paragraph, if the rescue changes what "detector first" means).
**Not** `PumpGlyphSlicer.swift`, `PumpReadingLaw.swift`, `PumpRowAssignment.swift` (the
assigner is measured 834/837; if a case needs it, file it), anything under `Spike/`, the Python
package, the models.

## Write code first, explore second

## What to build, each measured separately on the funnel line and the live floor

1. **A margin on detected boxes before slicing.** The detector's boxes hug or clip the
   digits (IoU 0.80 median; the two Wayne cases lose an edge digit). Widen each detected quad
   horizontally by a fraction of its HEIGHT (start at 0.5 × height each side - one digit
   pitch is ~0.6-0.7 × height on a seven-segment row) and vertically by ~0.15 × height, clamped
   to the frame. The slicer already tolerates a margin: leading/trailing blank positions are
   blanks, the band comes from the row projection. Measure: the two Wayne frames read 6/4 cells;
   the funnel's "two transaction rows verified" and the live floor do not drop; the count
   agreement in `PumpReaderHarnessTests` is untouched (it uses hand quads). `PumpBoxRefiner`
   went the other way (tightening, 22 → 21) - this is the opposite bet; delete the refiner if
   the margin is what ships, its comment says why it existed.
2. **A stacked-row rescue below the confidence cut.** When fewer than two rows pass
   `minimumConfidence` (0.3), take rows down to 0.15 that share the x-span of a row that did
   pass (both edges within ~0.25 of the passing row's width, or one contained in the other) and
   sit above or below it within ~3 row heights - transaction rows stack under one another on
   every head in the corpus; a keypad row does not share the display's span. `detect(in:)` must
   return the low-confidence rows for this (a second threshold, not a lower one everywhere).
   Measure: pump-224's liters row (0.25) is rescued; "candidate hit" and "two rows verified"
   on the funnel; false rows on `measure.swift` at 0.3 must not rise (the rescue is conditional
   on a passing row, so `measure.swift` at a flat threshold is not the measurement - write the
   funnel numbers).
3. **Keypad rows.** A detected row that is a keypad is a row of PRINTED digits in square keys:
   the verifier keeps a detected row on shape alone (decision 10), so nothing rejects it. Two
   candidate tests, pick by measurement: (a) cell aspect - keypad glyphs are as wide as tall
   and their pitch is > 1.5× the glyph width, a seven-segment row's glyphs are ~0.5-0.6 of
   their height; the slicer's cells give both numbers; (b) the classifier's margin on a
   detected row that is ALONE off the display's span. (a) is the structural one and the one
   decision 10 allows. Measure on pump-224 and on every heldout photo: the keypad row is
   dropped, no true row is (the funnel's "verified hit" stays 60).
4. If the live floor moves, raise `liveCommittedFloor` (29) to the run; if "assigned right"
   moves, say so in the report and in REPORT.md.

## Explicitly out of scope

Retraining either model; the slicer; the law; the assigner's rules; the annotator.

## Tests

- `swift test` is **2210** and must not fall (one pre-existing red, `RV277ExpenseTotalTests`,
  is `RV.302`'s - not yours; report it as such). Unit tests with synthetic boxes for: the margin
  (a quad widened by the rule, clamped at the frame edge); the rescue (a 0.2 row under a 0.6 row
  of the same span is kept, a 0.2 row off to the side is not, and nothing is rescued when no row
  passes); the keypad test on synthetic cell geometry.
- **Mutations named by this brief:** (1) set the margin to 0 - the video-003 read test (count 6
  on the total row, using the frame and its detected box) goes red; (2) remove the span
  condition from the rescue - the "off to the side" test goes red. Paste red and green verbatim.
- Floors: `PumpReaderPipelineTests` (annotated 79/0.96 untouched by this row - it uses hand
  quads; live 29/0.99 must hold or rise), `PumpReaderHarnessTests`, `PumpRowAssignmentTests`
  (4 tests, 834/837), `PumpDisplayCaptureTests` if the classification counts detected rows.
- Vacuous traps: a rescue test where the rescued row would have passed anyway; a margin test
  that never hits the frame edge; a keypad test whose geometry is the slicer's own output.

## Checks (by exit code)

`scripts/gate.sh` → report each step's exit; `swift test` will stop at RV.302's red - run the
app-target bundle separately (`xcodebuild … -only-testing:TankbookTests test`, 281) and report
it. `swiftlint lint` from the root → 0, no new warnings in touched files. No UI, no screenshots.

## Report back

The funnel line before and after each of the three parts; the live floor before/after; the
three named cases' rows and cells before/after; `measure.swift` numbers where they apply; the
two mutations red/green verbatim; gate exit codes and counts; anything found and not fixed with
the row that owns it.

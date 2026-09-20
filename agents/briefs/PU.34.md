# PU.34 - the read stage behind the detector: leading zeros and the one-digit misses

**Parent journey:** J4. **Row:** `docs/TASKS.md` → PU.34 (index line 123, row at ~967).
**Read first:** the row text; `docs/EXTRACTION.md` → "The pump reader" (decisions 8–10);
`ml/pump-reader/REPORT.md` → "The detector" (the funnel numbers this row starts from).

## The situation, in numbers (heldout split, `pump/split.csv`, 64 photos - never train on them)

With the detector locating rows, 45 of 64 heldout photos reach the reader with the right roles,
but the live path commits on only 9 (`PumpReaderPipelineTests`: live floor 22 cells / 1.000
precision). On the **40 correctly located transaction rows** the READ lines of
`PumpLivePathDiagnosticTests` say: slicer count right on **33**, digits exact on **23**, 7 rows one
digit wrong, 2 two wrong, 7 miscounted. The read stage is the loss; this row fixes it in two
measured steps and does NOT retrain.

Run the diagnostic yourself first and keep its output as the "before":

    cd ios && PUMP_LIVE_DIAG=1 swift test --filter PumpLivePathDiagnosticTests 2>&1 | tee /tmp/pu34-before.txt
    grep -c "      READ" /tmp/pu34-before.txt        # the rows
    grep "      READ" /tmp/pu34-before.txt            # truth vs read, per row

(`PUMP_LIVE_DIAG_ONLY=pump-032` limits it to one photo - use that while iterating; ~3 min for all.)

## Where you may write

`ios/Sources/TankbookCore/Extraction/PumpReader/` (`PumpGlyphSlicer.swift`, `PumpReadingLaw.swift`,
`PumpReader.swift`), `ios/Tests/TankbookCoreTests/Pump*.swift`, `ml/pump-reader/REPORT.md` (a
"PU.34" section under "The detector"). Nothing else. **Never edit anything under
`Spike/ReceiptSpike/fixtures/`** - the corpus is the owner's, and `windows.json` / `expected.csv`
/ `video-labels.json` may carry the owner's uncommitted annotation work. Not `PumpRowDetector`,
`PumpPanelLocator`, `PumpDisplayCapture`, `PumpRowAssignment` - the locate stage is measured as
right on these 40 rows and is out of scope.

## Write code first, explore second

## Diagnoses - hypotheses, not facts. Confirm each at its line before changing anything

**A. "Miscounted" rows are mostly dropped leading zeros, and half of them do not matter.**
The Gilbarco heads zero-pad (`0025,51` = 6 cells); in a detector box the dim leading zeros are
below the ink threshold, so `PumpGlyphSlicer.slice` never sees them as digit runs. The slicer's
leading-blank logic (`PumpGlyphSlicer.swift:~300-310`, `leadingBlanks`) only adds blanks where a
whole pitch fits between the strip's left edge and the first occupied cell, and `PumpReader.read`
(`PumpReader.swift:~72`, `for cell in cells where !cell.isBlank`) drops blank cells before the
law anyway - so a "4-cell" read of `0025,51` is `2551` → 25.51, **numerically right**. First
classify the 7 miscounted rows: value-preserving (only leading zeros lost) vs value-changing (a
real digit lost or a split glyph). Print that classification. Only the value-changing ones are a
read defect. For the value-preserving ones the question is whether the law still commits (it
should - check the DIAG line's committed fields for those photos); if it does not, find out why
(cell count vs `PumpRowAssignment.plausibleCount`, `minimumCells`, or the decimal placement with
fewer cells) and fix THAT, not the slicer.

**B. The one-substitution repair misses the 7 one-digit rows.** `PumpReadingLaw` repairs one
cell in liters or price within 6 nats (`PumpReadingLaw.swift:~107-125`), never in the total. For
each of the 7 rows determine which of these holds: (1) the wrong cell is in the **total**; (2) the
truth digit is outside the beam (`stringsPerField`, the `readWindow`); (3) the confusion table
lacks that pair (e.g. 8→0, 6→5, 3→9 - the seven-segment table must have them); (4) another row on
the same photo is also wrong, so no single repair can close. Print a table: photo, field, truth,
read, which case. Then fix the cases that are the law's to fix - a total-side repair is
legitimate ONLY if the arithmetic still closes exactly (the law's rule: `volume × price = total`
to the cent, no tolerance widening, `docs/EXTRACTION.md` decision 5); widening the beam is fine if
`PumpReadingLawTests` fragility (≤ 0.10) holds; adding a confusion pair needs the pair drawn from
the seven-segment geometry, not from the failing sample.

**C. Do not tune thresholds to the heldout rows.** Any constant you change must be explained
by geometry or by the TRAIN split, and the change must hold on the annotated path too
(`PumpReaderPipelineTests` annotated floor 66 / 0.96 must not drop).

## What to build

1. The before/after READ tables (A and B) - in the report and as a `PU.34` section in
   `ml/pump-reader/REPORT.md` with the same numbers.
2. The fixes A/B justify, each measured separately (run the diagnostic after each, keep both
   outputs).
3. A per-head table in `PumpReaderPipelineTests`' live-path print: committed / correct per
   manufacturer prefix of the fixture name (`wayne`, `gilbarco`, `tokheim`, `scheidt`, `tatsuno`,
   other) - the row asks for it; it is a print, not an assertion.
4. If the live path's committed count rises, raise `liveCommittedFloor` in
   `PumpReaderPipelineTests.swift` to the new number (it is the ratchet; it only goes up).

## Explicitly out of scope

Retraining or the 3-seed protocol (that is PU.34b, filed by the orchestrator); `PumpBoxRefiner`
(parked at 22 → 21); the locator; the detector; the annotator; any file under `Spike/`.

## Tests

- `swift test` is **2201** tests and must not fall; every new behaviour gets a unit test in
  `ios/Tests/TankbookCoreTests/` with synthetic cells (`PumpCellReading(certainDigit:decimalPoint:)`),
  not corpus images.
- **Mutation named by this brief:** whatever repair or recovery you add, revert its one load-bearing
  line (e.g. the total-side repair's closing check, or the blank-cell recovery) - the new unit test
  goes red. Paste red and green verbatim.
- Vacuous traps: a test that asserts only "does not throw"; a test whose truth is the reader's own
  output; a floor raised without the run that justifies it.

## Checks (by exit code)

`scripts/gate.sh` → 0 with both counts (package `swift test` and the app-target bundle, 281).
`swiftlint lint` from the repo root → 0 with no new warnings in the files you touched. No UI
suites, no screenshots (no UI change). Report wall time.

## Report back

The before/after READ tables; the classification tables A and B with one line per row; each
fix's separate measurement; the live committed count before/after and the annotated path's
66/0.970 unchanged or better; the mutation red/green; gate exit codes and counts; anything found
and not fixed with the row that owns it.

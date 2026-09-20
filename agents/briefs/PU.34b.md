# PU.34b - the decimal mark: the slicer sees it on 9 of 237 heldout windows

**Parent journey:** J4. **Row:** `docs/TASKS.md` → PU.34 (this is its second slice; PU.34's
first slice, the law, shipped 2026-09-21 as commit `1db7ba14`). **Read first:**
`ios/Sources/TankbookCore/Extraction/PumpReader/PumpGlyphSlicer.swift` end to end (527 lines - it
is the whole subject), then `docs/EXTRACTION.md` → "The pump reader", then
`ml/pump-reader/REPORT.md` → "PU.34".

## The situation, in numbers

`PumpReaderHarnessTests.slicerRatchet` prints, on the 64 heldout stills:

    PU.4 slicer: count agreement 209/238, dp agreement 9/237

**The slicer places a decimal mark on the right cell on 9 of 237 windows that have one.** The
count is fine (88 %); the mark is not seen. The classifier's own mark bit (`probabilities[7]`)
does not rescue it: on the running-display videos every row's `dp` came back false. Without a
mark the law has no placement hint and must close on arithmetic alone, which works only when the
currency's conventions leave one placement - on the Wayne heads of video-001/002/003 and the
Gilbarco of video-004 it did not commit the total until the conventions were widened, and a
mark seen on the wrong cell (`1.4541`, video-003) is worse than none.

The four named cases, all with the owner's hand-placed quads (`frames/<clip>/windows.json`) and
owner labels (`video-labels.json`, `source: "owner"`, the text carries the mark):

| clip / frame | row | truth | read | what the strip shows |
|---|---|---|---|---|
| video-002 `081.jpg` | total | `2331.65` | `233165`, no mark | a round dot after the `1`, clearly separate from both neighbours, bottom of the band |
| video-002 `081.jpg` | liters | `31.68` | `31.68` | the same dot geometry - SEEN here; find why this one and not the total's |
| video-003 `001.jpg` | total | `145.41` | `1.4541` | a false mark after the leading `1`, the real one after `5` missed (pink LCD) |
| video-003 `001.jpg` | liters | `70.62` | `7062` | missed |
| video-004 `001.jpg` | all three | `2955,04` / `29,58` / `99,9` | no mark on any | Gilbarco commas hanging BELOW the digits' baseline, in the gap before the next cell |

Look at the strips before theorising: `ios/.build/debug/pump-read <frame.jpg> --dump-strips <dir> < request.json`
writes each window's warped strip (`request.json`: `{"rotationCW":0,"windows":[{"field":"total","quad":[[x,y]x4]}]}`,
quads normalised, from the frame's entry in `frames/<clip>/windows.json`); build it with
`cd ios && swift build --product pump-read`. `PUMP_MERGE_GAP=0.04 PUMP_DP_TOP=0.4` override two
slicer options for a probe - the orchestrator tried 0.10→0.02 and 0.55→0.35 on video-002's total
and nothing changed, so the dot is not being merged into the `1` and not failing the
bottom-only test: **it never becomes a column run at all**, or it is dropped before
classification. Confirm at the line.

## Where you may write

`PumpGlyphSlicer.swift`, `PumpReader.swift` (only `read` and `singleDecimalMark`),
`ios/Tests/TankbookCoreTests/PumpGlyphSlicerTests.swift`, `PumpReaderHarnessTests.swift` (the
`dpAgreementFloor` constant and its comment only), a new `PumpMarkDiagnosticTests.swift`,
`ml/pump-reader/REPORT.md` (a "PU.34b" section). **Not** `PumpReadingLaw.swift`,
`PumpRowAssignment.swift`, `PumpRowDetector.swift`, `PumpDisplayCapture.swift`, anything under
`Spike/ReceiptSpike/fixtures/` (the owner's corpus - read it, never write it), the Python
package, the model.

## Write code first, explore second

## Diagnoses - hypotheses. Confirm each at its line before changing anything

**H1. The mark's column mass is below the run threshold.** `makePass` finds runs where the
column profile exceeds an Otsu threshold over the profile (`PumpGlyphSlicer.swift:~180`,
`otsuThreshold`) after local-contrast normalisation. A dot is ~10 % of the band height, so its
column sum is a tenth of a digit stroke's; Otsu splits digit columns from background and the
dot lands with the background. The liters row of video-002 passing while the total fails would
be the two strips' contrast ranges differing. Test: print the profile at the dot's columns
against the threshold for the total and liters strips of video-002 `081.jpg`.

**H2. The band excludes a comma below the baseline.** `bandTop/bandBottom` come from the row
projection at `bandRowThresholdFraction` (0.15 of the max row); a comma that hangs below the
digits' lowest segment sits in rows whose sum is a fraction of a stroke row's, so it is cut off
by the band and never projected (video-004). Test: the band's bottom row vs the comma's rows on
video-004's strips.

**H3. The false mark on video-003's total** is a run that IS bottom-only - a segment fragment of
the pink LCD's leading `1` or a bezel reflection. Whatever the fix for H1/H2, this must not get
worse: the fix is allowed to find more marks, not to find marks anywhere the band has a speck.

## What to build

1. **`PumpMarkDiagnosticTests`** (`PUMP_MARK_DIAG=1`, opt-in like `PumpLivePathDiagnosticTests`):
   over the four clips above, every 10th owner-labelled frame with its quads, per window: truth
   mark index (from the label text, counting cells as `PumpReaderTestSupport.glyphCount` does)
   vs the slicer's `hasDecimalPoint` index and the classifier's `decimalPoint` index; prints
   per-clip recall/precision for both detectors and the strip's band rows and threshold on a
   miss. Run it first, keep the output as the before.
2. **The fix the diagnosis justifies**, in the slicer - most likely a mark-specific second look
   in the gap between two digit cells: a small blob whose top is in the lower half of the band,
   whose height is under ~35 % of the band and whose width is under ~40 % of a pitch, found
   with a LOWER threshold than the digit runs, only in the inter-cell gaps and only in the
   lower band rows extended by up to ~25 % of the band height BELOW `bandBottom` (H2). It
   attaches to the cell on its left, as the existing `decimalCells` do. A blob touching the band
   top, or wider than the pitch's gap, is not a mark.
3. Whatever the classifier's mark bit says stays as it is (`PumpReader.read` ORs the slicer's
   mark in at 0.5); do not retrain.
4. Raise `dpAgreementFloor` in `PumpReaderHarnessTests` to the measured number (it is 0.0
   now - the honest floor after the fix; do not set it above what the run shows).

## Explicitly out of scope

The detector's box edges (PU.35), the law, retraining, the annotator, the Python package.

## Tests

- `swift test` is **2205** and must not fall. `PumpGlyphSlicerTests` gets synthetic-strip
  tests for the new mark rule: a dot in the gap between two digit cells is found (bottom half,
  small); a dot HANGING below the band by 20 % of its height is found; a speck touching the
  band top is NOT a mark; the existing tests stay green.
- **Mutation named by this brief:** in the mark rule, raise its threshold to the digit-run
  threshold (or remove the below-band extension) - the hanging-comma test goes red. Paste red
  and green verbatim.
- Floors to re-run and report: `PumpReaderHarnessTests` (count agreement ≥ 0.85 - **the count
  must not drop**: a mark taken for a digit run is a miscount), `PumpReaderPipelineTests`
  (annotated 67/0.96, live 23/0.99 - both must hold or rise), `PumpReadingLawTests`.
- Vacuous traps: a test whose truth is the slicer's own output; a floor raised past the run.

## Checks (by exit code)

`scripts/gate.sh` → 0 with both counts; `swiftlint lint` from the root → 0, no new warnings
in touched files. No UI, no screenshots. The before/after of `PU.4 slicer: ... dp agreement`
and of the mark diagnostic, per clip.

## Report back

The confirmed cause per case (H1/H2/H3 or other, at the line); the before/after numbers
(dp agreement, count agreement, annotated, live, the four clips' recall/precision); the
mutation red/green verbatim; gate exit codes and counts; anything found and not fixed with the
row that owns it.

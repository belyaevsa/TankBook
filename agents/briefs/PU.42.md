# PU.42 - the slicer's dim-glyph class: 12 of the 27 remaining miscounts

**Parent journey:** J4. **Row:** `docs/TASKS.md` → PU.42 (filed with this brief). **Read first:**
`ml/pump-reader/REPORT.md` → "PU.37" (the table of the 29 miscounts by class - this row is its
largest class) and "The decimal mark (PU.34b)"; `ios/Sources/TankbookCore/Extraction/PumpReader/PumpGlyphSlicer.swift`
(`prepare` - the LCN, the band, the Otsu threshold over the column profile; `makePass`;
`shortCountRetry`) and `PumpGlyphSlicer+Marks.swift`; `PumpReaderHarnessTests.swift` (the ratchet:
count agreement, dp agreement, `PU.4 miscount` lines, the strips written to
`ios/.build/pump-reader-out/strips/`).

## The situation

PU.37 named the 29 heldout miscounts; the largest class, **12 windows, is a dim or lost glyph
under the one global Otsu threshold**: `pump-028 liters 0025,51 6→5`, `pump-070 total 0067,05
6→3`, `pump-139 total 103.88 5→3`, `pump-092 liters 30.00 4→3`, `pump-014 total 7.01 3→2`,
`pump-035`, `pump-038`, `pump-062`, `pump-083`, `pump-092 total`, `pump-070 liters`, `pump-014
board`. PU.37 tried a local-profile threshold: count 218/238 but it cost two marks and three
annotated cells, so it was rejected - a threshold is the wrong lever. The heldout is now 68
stills / 251 windows (decision 9 amended 2026-09-22): the ratchet prints **count 223/251, dp
129/250** (floors 0.88 / 0.51); `PumpReaderPipelineTests` annotated **83 / 0.988 / 23 of 68**,
live **39 / 1.000 / 11** (floors 83 / 0.96 and 39 / 0.99).

Run the ratchet first (`cd ios && swift test --filter PumpReaderHarnessTests/slicerRatchet`,
~2 min) and keep the `PU.4 miscount` lines as the before; look at the twelve strips.

## Where you may write

`PumpGlyphSlicer.swift`, `PumpGlyphSlicer+Marks.swift` (only if the mark search needs the same
signal), `PumpGlyphSlicerTests.swift`, `PumpReaderHarnessTests.swift` (floors and their comments,
the miscount print), `ml/pump-reader/REPORT.md` ("PU.42"). **Not** `PumpReader.swift`, the law,
the assigner, the detector, `Spike/`, the Python package (PU.41 runs beside you and owns it),
`scripts/`, `tools/`.

## Write code first, explore second

## Diagnoses - hypotheses, confirm at the strip before changing anything

**H1. A dim glyph is not below the threshold everywhere - it is below it in its thin
strokes.** A zero-padded leading `0` on a Gilbarco LCD is a full-height glyph with faint
segments; its column profile has two weak peaks (the verticals) with a gap. Otsu over the
whole profile sits between the bright digits and the panel, above both peaks. A **per-glyph
contrast** rule: after the first pass finds the pitch and the bright cells, look at each grid
position the pass left EMPTY between the strip's left edge and the first bright cell (and
between two bright cells); if that position's own column-profile peak exceeds a fraction of
its own local background (the profile's minimum in that position ± half a pitch), it is a dim
glyph, not a blank. The fraction is geometric (a stroke must stand a fixed ratio above its own
panel), never fitted to the twelve.

**H2. Glare washes out a column run in the middle of a glyph**, so one glyph reads as two
short runs that the split-merge does not join (their gap is not "under the merge gap" - one
half is gone). The body check (`pitchToBodyMinimum`) and the split-merge width rule are the
places to look; the fix is likely "a run pair whose combined extent equals one pitch at the
grid's phase is one glyph even when the gap is wide".

**H3. The short-count retry at half the threshold** already exists (`shortCountRetry`); find why
it does not catch these - probably the retry recounts the whole strip and over-counts elsewhere,
so the plausibility check rejects it. A retry that only fills EMPTY grid positions (H1) would
not have that failure.

## What to build

1. The per-class table for the twelve (strip name, class H1/H2/H3/other, what the profile
   shows at the lost glyph) - the first deliverable.
2. The rule for the largest sub-class, measured on its own; then the next. Each rule is a
   geometric statement with a synthetic-strip test.
3. Raise `countAgreementFloor` to the run (never above it); dp agreement must not fall below
   129/250; the annotated and live floors must hold or rise. A rule that lifts the count and
   drops the annotated path has traded a count for a wrong digit - report it, do not ship it.

## Explicitly out of scope

Thresholds tuned to the twelve; the classifier; the marks beyond sharing a signal; the locator.

## Tests

- `swift test` is **2226** and must not fall (RV.302's red is pre-existing). Synthetic-strip
  tests in `PumpGlyphSlicerTests`: a dim leading glyph at a third of the bright digits' contrast
  is counted; a glyph split by a washed-out column in its middle is one glyph; two bright
  glyphs at the minimum gap stay two; a genuinely blank leading position stays blank.
- **Mutation named by this brief:** raise the per-glyph contrast fraction to 1.0 (a dim glyph
  must be as dark as the panel is bright - impossible) - the dim-leading-glyph test goes red
  AND the count print drops. Paste red and green verbatim.

## Checks (by exit code)

`scripts/gate.sh` → each step's exit and both counts (the app-target bundle separately, 299);
`swiftlint lint` from the root → 0 (the slicer file is near the 700-line limit - the marks
extension already moved out; move another `MARK` section to `PumpGlyphSlicer+<Name>.swift` if
you cross it). No UI.

## Report back

The table of the twelve; count agreement before/after per rule and per make; dp agreement; the
annotated and live prints; the mutation red/green verbatim; gate exits and counts; anything
found and not fixed with the row that owns it.

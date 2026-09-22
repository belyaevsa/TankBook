# PU.55 - The clip guard: a strip whose edge carries cut glyph ink abstains

Row: `docs/TASKS.md` -> PU.55. Source: `agents/reviews/PU.52-REVIEW-WHY-IT-LOWERED-qwen.md` §4,
the first-ranked fix.

## Where you may write

`ios/Sources/TankbookCore/Extraction/PumpReader/PumpReader.swift`, a new
`PumpGlyphSlicer+EdgeInk.swift` (or inside `PumpGlyphSlicer+Primitives.swift` - say which and why),
`PumpReadingTypes.swift` (one new abstention case), `ios/Tests/TankbookCoreTests/` (a new
`PumpEdgeInkTests.swift`, and `PumpReaderPipelineTests.swift` for the measurement print),
`ml/pump-reader/REPORT.md` (a dated PU.55 section). **Nothing under `Spike/`** - the corpus is
another session's live work; read it, never write it. **Nothing in `tools/pump-annotate/`.**
Scratch: `ios/.build/pump-reader-out/pu55/`.

## What exists (read first, in order)

1. `agents/reviews/PU.52-REVIEW-WHY-IT-LOWERED-qwen.md` §4 - the failure, measured: `pump-092`
   under the PU.48 detector commits `3.0` / `191.55` for 30.00 / 1915.5. Three small failures the
   law's decimal freedom assembles, and why the guard belongs at the slicer and nowhere else.
2. `PumpReader.swift`: `sliceDetectedOrOriginal` (~line 132) - it slices the box as it came AND
   widened by `detectedMarginHorizontal = 0.1`, keeps the widened slice only when it finds at least
   as many cells, and **silently falls back to the clipped plain slice otherwise**. That fallback
   is the missing abstention.
3. `PumpGlyphSlicer.swift` (+ `Primitives`, `DimGlyphs`, `Marks`) - the ink profile, the polarity
   decision, the cell rects. The guard must use the slicer's own ink measure, not a new one.
4. `agents/reviews/PU.13-REVIEW-ANNOTATIONS.md` - **the risk**: the slicer right-aligns every cell,
   so right-edge ink is LEGITIMATE on most cells (its margin table measured the medians). A guard
   that fires on "ink touches the edge" refuses the corpus. It must separate *touching* from *cut*.
5. `PumpReadingLaw.swift` and `PumpReadingTypes.swift` - how `PumpAbstentionReason` (PU.51) is
   carried, so the refusal has a name.
6. `PumpReaderPipelineTests.swift` - both tiers, the floors, and the `WRONG` lines the L5 check
   below reads.

This brief's diagnosis is the review's, not measured by you: **confirm it before changing anything**
- reproduce `pump-092` under the PU.48 detector (`ml/pump-reader/.out/det/pu48/DigitRows-pu48.mlmodel`)
with `ios/.build/opt/debug/pump-read` and check the strings and box coordinates it names. If the
clip is not there, say so and stop.

## What to build

A measure of **cut ink at a strip's edge**: after the slicer has chosen its polarity and ink band,
the first and last ink columns against the strip's left/right edge - a glyph that is *cut* leaves
ink at the extreme column with no background gutter between it and the edge, while a glyph that
merely *touches* leaves the slicer's normal right-alignment margin. Express it in the slicer's own
units (column ink relative to the band, gutter in pitch), and put every threshold in a named
constant with the measurement it came from.

Then, in `sliceDetectedOrOriginal`: when `detected` is true, the widened slice did NOT recover a
cell, AND the plain slice's edge carries cut ink, return no candidate - the verifier drops the row
and the law names the refusal (a new `PumpAbstentionReason` case, e.g. `clippedRow`). An undetected
(Vision-proposed) row keeps today's behaviour unless you can show the same guard helps there.

Out of scope: the detector (PU.57), the law's price requirement (PU.54), the slicer's count on
zero-padded rows (a separate row), any retraining.

## Tests you must add

`PumpEdgeInkTests` (L1), synthetic strips so the oracle is construction, not a fixture:
- a glyph cut at the right edge (drawn partly outside the strip) is **refused**;
- a glyph right-aligned against the edge with the slicer's normal margin is **kept** - this is the
  PU.13 risk and the test that proves the guard is not a blunt instrument;
- the same pair at the left edge;
- a blank-edged strip is kept.
Plus one corpus test: `pump-092`'s ANNOTATED window (the oracle quad, which is not clipped) is
kept - the guard must not refuse a hand window.
**Named mutation**: make the guard fire on any edge ink (drop the gutter test) - the
"right-aligned, kept" test must go red. Paste red-then-green.

L5 in `PumpReaderPipelineTests`: run the live arm under the **PU.48 candidate** detector (copy it
to `ml/pump-reader/.out/det/DigitRows.mlmodel`, which is what `PumpReaderTestSupport.detectorURL`
reads, and **restore the shipped copy afterwards** - both are `b560fef2…`/`d18531eb…`, check the
shas and say so) and report: the `WRONG` lines are empty, precision 1.000 (today 36 / 0.944), and
the committed count with a per-still `cellsPerRow` diff showing **no still that was correct flipped
to abstaining**. Then run the shipped detector and show the floor (43 / 1.000) unchanged.

## Checks

`scripts/gate.sh` (core code changes); `swift test --filter "PumpEdgeInkTests|PumpReadingLawTests|PumpReaderPipelineTests|PumpRowGeometryTests|PumpReaderHarnessTests"`
with counts; `swiftlint lint` from the repo ROOT exit 0. Verify by exit code. Note: the package
suite has ~97 pre-existing failures from a concurrent corpus session (PaddleOCR, CorpusAB, RV.277,
pump-300's oracle) - name them, do not chase them.

## Vacuous traps

A guard that buys precision by refusing rows wholesale. A threshold fitted on `pump-092`. Testing
only the cut case and not the legitimate right-aligned one. Reporting precision without the
committed count beside it. Leaving the candidate detector in `.out/det/DigitRows.mlmodel`.

## Report back

Exit codes, counts, run-or-only-written, the mutation red-then-green verbatim, the two L5 tables
(candidate before/after, shipped unchanged), the constants with their measurements, and anything
found and not fixed.

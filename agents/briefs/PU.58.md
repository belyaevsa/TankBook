# PU.58 - Trim the strip to its ink band before the pitch is computed

Row: `docs/TASKS.md` -> PU.58. It is PU.55's re-scope: `ml/pump-reader/REPORT.md` -> "PU.55 - the
clip guard: the diagnosis does not reproduce" carries the measurement this row starts from.

**You are working in a git WORKTREE** (`/Users/sbelyaev/repos/tb-pu58`, branch `pu58-bandtrim`,
from commit 82398950). Two sibling rows run in parallel in their own checkouts. Never touch another
checkout, never `git checkout`/`stash`. Do not commit.

**Baseline on this commit:** live **43 / 43 / 1.000 / 14 of 68**; annotated **104 / 103 / 0.990 /
30**; slicer count agreement **237/251**, dp agreement **133/250** (`PumpReaderHarnessTests`).

## The finding to start from (PU.55, measured)

On `pump-092` under the PU.48 candidate detector the litres row loses a cell (`30.0` for `30.00`),
and the cause is the box's **vertical** extent, not a horizontal clip:

| quad | horizontal | vertical | litres reads |
|---|---|---|---|
| raw | detector | detector | `30.0` (3 cells) |
| raw LR + oracle H | detector | **oracle** | `30.01` (4) |
| oracle LR + raw H | oracle | detector | `30.0` (3) |
| oracle | oracle | oracle | `30.00` (4) |

The raw box is 21 % taller than the hand window and its ink band runs rows 6..95 of 96, so the
pitch and the slicer's thresholds are computed over a strip that includes bezel. Reproduce this
table before building anything (the candidate is
`ml/pump-reader/.out/det/pu48/DigitRows-pu48.mlmodel`, sha `d18531eb…`; the shipped one is
`b560fef2…`). If it does not reproduce, say so and stop.

## Where you may write

`ios/Sources/TankbookCore/Extraction/PumpReader/PumpGlyphSlicer.swift` and its
`+Primitives`/`+DimGlyphs`/`+Marks` files, `PumpReader.swift` ONLY if the trim belongs at the warp
rather than the slice (argue which and say why), `ios/Tests/TankbookCoreTests/` (a new
`PumpBandTrimTests.swift`, plus the harness/pipeline prints), `ml/pump-reader/REPORT.md` (a dated
PU.58 section). **Nothing under `Spike/`** - the corpus is fixed at this commit. Scratch:
`ios/.build/pump-reader-out/pu58/`.

## What exists (read first, in order)

1. `PumpGlyphSlicer.swift` - `slice(_:options:)`: the polarity decision, the ink band it already
   computes, the column profile, the pitch, the cell rects. The band is the thing this row trims to.
2. `PumpGlyphSlicer+Primitives.swift` / `+DimGlyphs.swift` - the thresholds and the dim-glyph pass
   (PU.37/PU.42); both are computed over the strip's rows and both are what a bezel band poisons.
3. `PumpReader.swift` -> `sliceDetectedOrOriginal`, `widened`, `detectedMarginVertical = 0` - the
   detected box is widened horizontally and NOT vertically, which is why a tall box survives to the
   slicer unchanged.
4. `ml/pump-reader/REPORT.md` -> PU.55 (the measurement above), PU.37 (the 29 miscounted heldout
   windows by class), PU.42 (the dim-glyph class).
5. `PumpReaderHarnessTests.swift` - the slicer's count and dp agreement, the numbers this row moves
   most directly.

## What to build

Before the slicer measures pitch, **trim the warped strip to the rows its own ink occupies** - the
band it already computes for the polarity decision - with a margin, and recompute the profile,
thresholds and pitch on the trimmed strip. A strip whose band already fills the frame must come out
unchanged: that is the correctness property, not an optimisation.

Every constant (the margin, the minimum band height below which the trim is refused) is a named
`static let` with the measurement it came from. If the trim belongs at the warp instead - trimming
the quad before `warpToStrip` - argue it and do that; say which you chose and why.

Out of scope: the detector and its boxes (PU.57 gates them), the orientation search (PU.53), the
price requirement (PU.54), any retraining.

## Tests you must add

`PumpBandTrimTests` (L1), synthetic strips so the oracle is construction:
- a strip padded with a bezel band above and below its glyphs counts the same cells as the
  unpadded one, and **the test names the padding ratio at which today's slicer breaks** (measure
  it, do not guess);
- a strip whose band already fills the frame is byte-identical through the trim;
- a strip with no ink at all is unchanged (the trim must not divide by zero).
**Named mutation**: make the trim always take the full strip - the padded test goes red. Paste
red-then-green.

L5: `PumpReaderHarnessTests` count and dp agreement before and after (baseline 237/251 and
133/250), and `PumpReaderPipelineTests` live + annotated under **both** detectors: the shipped one
(floor 43 / 1.000) and the PU.48 candidate (today **41 committed / 39 correct / 0.951**, with
`pump-092` the only wrong still). `pump-092`'s wrong commit becoming either correct or an
abstention is this row's specific target - say which happened.
To score the candidate, copy it over `ml/pump-reader/.out/det/DigitRows.mlmodel` (what
`PumpReaderTestSupport.detectorURL` reads) and **restore the shipped copy afterwards** - check the
shas before and after and report them.

## Checks

`scripts/gate.sh`; `swift test --filter "PumpBandTrimTests|PumpReaderHarnessTests|PumpReaderPipelineTests|PumpReadingLawTests|PumpRowGeometryTests"`
with counts; `swiftlint lint` from the repo ROOT exit 0. Verify by exit code. Pre-existing package
failures from other rows are not yours - name them.

## Vacuous traps

A trim that changes an already-tight strip (the test must prove it does not). Trimming on the
classifier's output rather than the slicer's own band. Reporting the count agreement without the
live number beside it. Leaving the candidate detector in `.out/det/DigitRows.mlmodel`.

## Report back

Exit codes, counts, run-or-only-written, the mutation red-then-green verbatim, **the before/after
table (count agreement, dp agreement, live and annotated under both detectors)**, what happened to
`pump-092`, the padding ratio at which the old slicer broke, the constants with their
measurements, and anything found and not fixed.

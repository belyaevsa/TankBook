# PU.24 - the automatic locator (Vision proposals, ranked by the reader itself)

**Parent journey:** J4. **Row:** `docs/TASKS.md` → PU.24. **Authority:** `docs/EXTRACTION.md` → "The
pump reader" (decision 8: the locator is automatic). **Read:** `agents/reviews/PU.11-REVIEW-IMPL.md`
F14 (why polishing classical CV is the wrong investment), `PU.14-REVIEW-DECODE-DESIGN.md` §3
("measured layout facts" - display rows are horizontal bands of similar-height glyphs at a common
baseline; totals above volume above price on most heads; boards are a row of 3-4 short windows),
`PU.13-REVIEW-ANNOTATIONS.md` §1 (what a good window quad looks like: tight on the ink band,
right margin ~0, left slack).

## Where you may write

`ios/Sources/TankbookCore/Extraction/PumpReader/PumpPanelLocator.swift` (rewrite freely - it is a
stub at median IoU 0.008), a new `PumpVisionProposer.swift` beside it, and
`ios/Tests/TankbookCoreTests/PumpReaderHarnessTests.swift` ONLY in the locator section (the
`locator*` tests and `locatorMedianIoUFloor`) - **do not touch the slicer ratchet, the seams test or
`slice(window:...)`**. Nothing else in Swift, nothing in `ml/`, `ios/App/`, `Spike/`. **Three other
agents are working in this checkout** (the law, row assignment, the Python model) - never move or
revert a file you did not create. No `/tmp`; scratch is `ios/.build/pump-reader-out/locator/`.

## Write code first, explore second

## What already exists

- `PumpQuadWarp.loadOrientedImage / rgbImage / warpToStrip / readingOrder`; `PumpGlyphSlicer.slice`
  (count agreement 282/433 on annotated windows - the locator's proposals are judged by whether the
  slicer counts them as a clean row); `PumpSegmentsModel` (8 probabilities per cell and a
  likelihood margin - a display row scores high, a sticker or a label scores low).
- `VisionTextRecognizer.swift`: how the app already calls Vision; `VisionRequestGate`.
- The harness: `locatorFindsTotalOnCleanFixture` (`pump-078` ≥ 0.5), `locatorMedianIoU` over the
  non-board windows against the annotated quads, `rotatedQuad`, `iou`. The corpus median is the
  number; the floor is `0.0` today.
- `windows.json` (`rotationCW` 90 on `pump-019/020/021/022/023`): the oracle. Read it only
  through the harness.

## What to build

1. **`PumpVisionProposer`**: `VNDetectTextRectanglesRequest` (character boxes, `reportCharacterBoxes`)
   and/or `VNRecognizeTextRequest` at `.fast` for its **bounding boxes only** - never its strings -
   on the oriented image (and on the 90/270 rotations when the row structure is vertical).
   Group boxes into rows: similar height (±35 %), overlapping baselines, horizontal gaps below
   ~1.5 × height; a row of ≥ 3 boxes is a candidate window. Expand each candidate to the ink
   band (the slicer's own band trim on the warped strip) and to the row's full glyph pitch on
   both sides (a leading zero-padded cell is dim on Gilbarco heads - look one pitch left).
2. **Ranking**: warp each candidate, slice it, classify its cells; score = slicer count ≥ 3 and
   its cells' mean likelihood margin and the fraction of cells whose best pattern is a digit
   (not `?`); labels (`SUMMA`, `LIITRIT`, `€/L`, Cyrillic) rank low because the classifier's
   margin on letters is low. Keep the classical proposer as a second source, merged by IoU.
3. **Output**: `[PumpCandidateWindow]` (quad in the oriented image's pixel space, glyph count,
   score), most likely first, at most 8; `PumpPanelLocator.locate(image, rotationCW:)` keeps its
   signature so the harness runs unchanged.
4. **Measure**: the harness's corpus median IoU (best candidate per annotated transaction window);
   raise `locatorMedianIoUFloor` to what you measure; print per-make and the by-name list of
   windows with IoU < 0.3.

## Tests

- Existing locator tests stay green (`pump-078` ≥ 0.5); the median-IoU ratchet at the new floor.
- A synthetic row test: a PU.1 rendered row pasted into a larger neutral canvas at a known quad
  (generate with the same Python replay `PumpGlyphSlicerTests` uses) is located with IoU ≥ 0.7
  (oracle: the paste position). **Mutation named by this brief:** rank candidates by box area
  instead of the reader's score - on a fixture with a board AND a total (`pump-013`), the best
  candidate stops being the total; paste the red output.
- Vision availability: the proposer must degrade to the classical proposer when Vision returns
  nothing (a unit test with an all-grey image expects an empty, not crashing, result).

## Out of scope

The slicer, the classifier, the law (PU.21), row assignment (PU.23 - you return candidates,
not field roles), the app wiring (PU.29).

## Checks (by exit code)

`cd ios && swift build` → 0; `swiftlint lint` from the repo ROOT → 0; `cd ios && swift test
--filter PumpReaderHarnessTests` → 0 with the locator tests' count non-zero, then the FULL
`swift test` → 0 (Vision on macOS runs in the package tests - it does for the ratchet suites).
No app-target change → say so.

## Standing fences

Never stash / checkout / move; never commit; `pgrep -x` only; not alone in the checkout; no `/tmp`.

## Report back

Exit codes, counts, the median IoU before/after with the per-make table and the < 0.3 list, the
red mutation, wall time per image (the app will run this on device), anything found and not fixed.

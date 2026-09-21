# PU.19 - Live Photo per-cell fusion over frames: does it lift the heldout number?

**Parent journey:** J4. **Row:** `docs/TASKS.md` → PU.19 (line ~960). **Read first:** the row;
`docs/EXTRACTION.md` → "The pump reader" (decision 2 is the Live Photo decision; decisions 9 and
10 for the split and the detector); `ml/pump-reader/REPORT.md` → "Round 10" and "PU.35" (today's
numbers and what moved them); `Spike/ReceiptSpike/fixtures/pump-live/README.md` (what a Live
record is and how its frames are tracked).

## The situation

The product owner shoots Live Photos. The corpus pairs 63 stills with their Live records; for
each, `pump_reader.track` carried the still's hand quads into every frame
(`Spike/ReceiptSpike/fixtures/pump-live/frames/live-<id>/windows.json`: `_still`, `_split`,
`frames: { "NNN.jpg": { windows: [{field, text, quad}], inliers } }`, quads normalised over the
frame). **17 heldout stills have a tracked Live record - 860 frames.** Nothing in the reader
looks at more than the still today.

Heldout numbers this evening (`PumpReaderPipelineTests`, still only): annotated path **79 cells /
0.987 / 22 of 64 photos**; live path **37 / 1.000 / 11**. The question this row answers, with a
number: **does fusing the classifier's per-cell probabilities across a record's frames read more
cells right on the 17 stills that have frames?** Glare and reflections move between frames; the
digits do not.

## Where you may write

`ios/Sources/TankbookCore/Extraction/PumpReader/PumpReader.swift` (a NEW entry point beside
`read`; the still path's behaviour must not change - the floors prove it), a new
`PumpFrameFusion.swift` in the same folder if the fusion deserves its own file,
`ios/Tests/TankbookCoreTests/PumpReaderPipelineTests.swift` (a new test, the existing two
untouched except a shared helper), `PumpReaderTestSupport.swift` (a loader for a still's heldout
record), a new `PumpFrameFusionTests.swift`, `ml/pump-reader/REPORT.md` ("PU.19"). **Not**
the slicer, the law, the assigner, the detector, the app target, anything under `Spike/`
(read-only: the owner's corpus, with uncommitted work in it).

## Write code first, explore second

## What to build

1. **`PumpReader.readFused(still:frames:windows:)`** (name it as you see fit): for a window
   with hand quads on the still AND on each frame (the tracked file's quads), slice the still's
   strip as `read` does to fix the cell count and rects, then for every frame whose slicer
   count EQUALS the still's (a frame that miscounts is skipped whole - the row says so, and
   `realglyphs.py` applies the same rule), classify each cell and take the **median of the 8
   probabilities over the still plus the frames**, cell by cell. The still alone is the
   fallback when no frame agrees. Then the law as today (`PumpReadingLaw.resolve`).
   Alternative to measure if cheap: median of the warped cell PIXELS over frames, classified
   once - report which of the two wins, or that they tie.
2. **A test that prints the same number three ways** on the 17 heldout stills with records
   (`.pumpFixturesPresent`, a separate `@Test` in `PumpReaderPipelineTests`): still only;
   fused over all tracked frames; fused over every 5th frame (the app will not have 50 frames
   to spare - a Live Photo is ~1.5 s at 30 fps, and the reader has a 3 s budget on device,
   `docs/EXTRACTION.md` P4.12). Committed / correct / precision / photos fully right, exactly
   like the existing print. The 47 heldout stills without a record are outside this test.
3. **Write the three lines under a "PU.19" heading in REPORT.md** with the reading: if fusion
   lifts the 17-still number by more than seed noise (±2 cells, REPORT.md round 10), say what
   it costs per frame (time the fused read; `Date()` around it is enough); if it does not, say
   so - "fusion does not help on this corpus" is a deliverable, the row's hypothesis is exactly
   what is being tested.
4. Nothing is wired into the app or the live path in this row: the live path's frames would
   need the detector per frame and row matching across frames, which is PU.5's if fusion
   earns it. Say in the report what that wiring needs.

## Explicitly out of scope

The app target, the capture pipeline, the live path, retraining, the slicer, anything the
still-only floors would notice.

## Tests

- `swift test` is **2213** and must not fall (one pre-existing red, `RV277ExpenseTotalTests`,
  is `RV.302`'s - report it as such, it is not yours). `PumpFrameFusionTests` with synthetic
  cells: the median of three probability vectors is taken element-wise; a frame with a
  different cell count is skipped; with no agreeing frame the still's own reading is returned
  unchanged.
- **Mutation named by this brief:** replace the median by the still's own probabilities (i.e.
  ignore the frames) - the element-wise median test goes red. Paste red and green verbatim.
- Floors untouched: `PumpReaderPipelineTests` annotated 79/0.96 and live 37/0.99 must print the
  same numbers as before your change (still-only code path unchanged).
- Vacuous traps: a fusion test whose frames are copies of the still (the median of identical
  vectors proves nothing); a "fused" number computed on frames whose quads were never checked
  for the still's count.

## Checks (by exit code)

`scripts/gate.sh` → report each step; `swift test` stops at RV.302's red - run the app-target
bundle separately (`xcodebuild … -only-testing:TankbookTests test`, 281) and report it.
`swiftlint lint` from the root → 0, no new warnings in touched files. No UI, no screenshots.

## Report back

The three-way number on the 17 stills (still / all frames / every 5th), per-photo where fusion
changed the outcome (which cells flipped, right or wrong), the time per fused read, which fusion
(probabilities vs pixels) if both were tried, the mutation red/green verbatim, the unchanged
floors' prints, gate exit codes and counts, what PU.5 would need to wire it live, anything found
and not fixed with the row that owns it.

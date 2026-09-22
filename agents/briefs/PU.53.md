# PU.53 - The reader finds its own orientation

Row: `docs/TASKS.md` -> PU.53. Found by the product owner in the annotator's compare view,
2026-09-22.

**You are working in a git WORKTREE** (`/Users/sbelyaev/repos/tb-pu53`, branch
`pu53-orientation`, from commit 82398950). Two sibling rows run in parallel in their own checkouts;
everything you need is here. Never touch another checkout, and never `git checkout`/`stash` -
write, build, test, report. Do not commit.

**Baseline on this commit, which you must reproduce before changing anything:** live
**43 committed / 43 correct / 1.000 / 14 of 68 photos**; annotated **104 / 103 / 0.990 / 30**.

## The finding

`pump-019-gilbarco-circlek-sikupilli-pump8-ee.jpg` carries `rotationCW: 90` in `windows.json` -
the display is sideways in the frame - and the live path is run at 0 because nothing tells it
otherwise. Measured with `ios/.build/debug/pump-read` (build it: `swift build --product pump-read`
in `ios/`):

| rotationCW | rows | read |
|---|---|---|
| 0 | total 3, liters 3 | `1.19`, `295` - garbage |
| **90** | total 7, liters 6, unitPrice 4 | **`700.7932`, `0045.22`, `1.754`** |
| 180 | none | - |
| 270 | 3 rows, wrong | garbage |

Five heldout stills carry a rotation (`pump-019`, `020`, `021`, `022`, `023`) and **every one is
among the stills that commit nothing**. Reproduce this table before you build anything; if it does
not reproduce, say so and stop.

## Where you may write

`ios/Sources/TankbookCore/Extraction/PumpReader/PumpReader.swift` (the search),
`PumpDisplayCapture.swift` and `ios/App/Sources/Capture/` ONLY if the app needs to seed the search
from the capture's own orientation, `ios/Tests/TankbookCoreTests/` (a new
`PumpReaderOrientationTests.swift`, and `PumpReaderPipelineTests.swift` for the live arm),
`ml/pump-reader/REPORT.md` (a dated PU.53 section). **Nothing under `Spike/`** - the corpus is
fixed at this commit. Scratch: `ios/.build/pump-reader-out/pu53/`.

## What exists (read first, in order)

1. `PumpReader.swift`: `readPhoto(image:rotationCW:currency:priceBand:)` - the live entry point and
   where the rotation arrives; `PumpPanelLocator.rotatedRGB`; `candidates(for:)`; `verify(...)`.
2. `PumpRowGeometry.swift` (PU.47) - the model-free keep verdict. The orientation search scores
   itself on this, never on the classifier.
3. `PumpRowDetector.swift` and the `timingsMs.detectorOnly` line in `ios/Sources/PumpReadTool/main.swift`
   - the detector costs ~2 ms, which is what makes a three-way search affordable.
4. `PumpReaderPipelineTests.swift` - **the live arm currently passes the annotation's
   `rotationCW`**, which the phone does not have. Find that line; removing it is half this row.
5. `ios/App/Sources/Capture/CameraCapture.swift` -> `applyRotation` (RV.49) - the app knows the
   interface orientation at capture time. That is the seed, the search is the fallback.

## What to build

1. **The search.** When the caller does not state a rotation, run the detector at 0, 90 and 270 and
   keep the orientation whose rows best pass `PumpRowGeometry`: most kept rows, then total ink-band
   area as the tiebreak, with **0 winning ties** so an upright photo costs one extra detector pass
   and nothing else. 180 is not searched (a display photographed upside down is not a case the
   corpus has; say so in a comment).
2. **Seed from the camera where it is known.** In the app, the capture's own orientation is the
   first candidate; the search runs only when it produces nothing.
3. **The live arm stops borrowing the annotation's rotation.** `PumpReaderPipelineTests`' live path
   must not read `rotationCW` from `windows.json` - the phone never has it. Prove it with a grep in
   your report. **This may move the floor down before the search moves it up; report both numbers
   honestly** - the row's point is an honest measurement, not a higher one.

Out of scope: the price requirement (PU.54), the strip band trim (PU.58), tilt by a free angle
(PU.49), the detector, the annotator.

## Tests you must add

`PumpReaderOrientationTests` (L1):
- on `pump-019` the search picks 90, and the reader's rows equal an explicit `rotationCW: 90` run;
- on an upright still (name one from the corpus) it picks 0 and the rows are unchanged from today;
- the tie rule: a constructed case where two orientations keep the same rows picks 0.
**Named mutation**: make the search always return 0 - the `pump-019` test goes red. Paste
red-then-green.

L5 `PumpReaderPipelineTests`: report **live committed / correct / precision / photos** and the
abstention histogram (a) at the baseline, (b) with the annotation's rotation removed and NO search
(the honest floor), (c) with the search. Those three numbers are the row's result.

## Checks

`scripts/gate.sh`; `swift test --filter "PumpReaderOrientationTests|PumpReaderPipelineTests|PumpRowGeometryTests|PumpReaderHarnessTests|PumpReadingLawTests"`
with counts; `swiftlint lint` from the repo ROOT exit 0. Verify by exit code. Pre-existing package
failures from other rows (PaddleOCR, CorpusAB, RV.277, RV.49, pump-300) are not yours - name them.

## Vacuous traps

Keeping the annotation's rotation on the live arm "for now" - that is the defect. Scoring the
search on the five rotated stills only. A search that runs the whole pipeline three times instead
of the detector. Reporting (c) without (b).

## Report back

Exit codes, counts, run-or-only-written, the mutation red-then-green verbatim, **the three-row
table (baseline / no-rotation / search)**, the grep proving the live arm no longer reads
`rotationCW`, the per-still outcome for `pump-019`..`023`, and anything found and not fixed.

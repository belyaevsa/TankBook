# PU.40b - the detector on the preview: "display found / move closer" before the shutter

**Parent journey:** J4. **Row:** `docs/TASKS.md` → PU.40 (this is its preview half; the
production-preset half waits for PU.39's lab sessions). **Read first:**
`ios/App/Sources/Capture/CameraCapture.swift` (`CameraController` - the shared
`AVCaptureSession`, `.photo` preset, the photo output, `testFrame` for the simulator),
`CameraPreview.swift` (the preview layer on the same session), `CaptureView.swift` (the
capture screen: mode row, the caption under it - PJ.12b - the shutter and its manual peer;
`captureFrame`), `PumpRowDetector.swift` (`detect(in:) -> [Row]`, normalised quads with
confidence; `minimumConfidence` 0.3, `rescueConfidence` 0.15), `PumpReader.swift` →
`rescueStackedRows`, `sharesSpan`, `stacks`, `minimumRowHeightFraction` (0.025),
`PumpDisplayCapture.swift` → the fast verdict (PU.38: two stacked detected rows passing the
size rules = a display), `docs/DESIGN.md` (tokens; the overlay's colours are palette
semantics - hard rule 5), `docs/JOURNEYS.md` → J4 (add the hint to the journey text in the
same change - the journey is the spec), `docs/ERRORS.md` (a hint is not an error; but the
"no display in view" state names its next step), hard rule 15 (the hint must never make the
typed door harder to reach or frame it as the failure).

## The situation

The live path loses most of its photos before the read: on the heldout, 64 → 61 have a
candidate row, 60 a verified one, **52 two stacked rows** - framing, distance, tilt, glare the
user could have fixed before pressing. The detector decides "display" in 3-6 ms on the Mac
(PU.38), which is preview-rate on a phone. This row runs it on the preview and tells the
user, before the shutter, whether the reader will have something to read.

## Where you may write

`CameraCapture.swift` (an `AVCaptureVideoDataOutput` on the same session, delivering frames
to a delegate off the main thread, at most ~10 fps - drop frames while one is being
analysed), a new `ios/App/Sources/Capture/PreviewGuidance.swift` (the analyser + the state
machine below), `CaptureView.swift` (the overlay and the caption), `CameraPreview.swift`
(only if the overlay needs the preview's coordinate conversion - `layerRectConverted(fromMetadataOutputRect:)`
is the honest way to map normalised rows onto the preview), `Localizable.xcstrings` (EN + RU),
`CaptureUITests.swift` (or a new `CaptureGuidanceUITests.swift`), `scripts/capture-screenshots.sh`,
`design/screenshots/PU.40b-capture-guidance{,-ru}.png`, `docs/JOURNEYS.md` (J4), `docs/LOGGING.md`
+ `LogEvents.swift` only if you add a log line (counts only - hard rule 12; a `capture.guidance`
line at the shutter with `state` and `framesAnalysed` is reasonable). **Not** `CapturePipeline`,
the reader, `PumpDisplayCapture`'s verdict, the models, anything under `Spike/`.

## Write code first, explore second

## What to build

1. **The analyser**: on each delivered preview frame (downscaled - the detector runs on
   `.scaleFit` anyway; hand it the `CVPixelBuffer` via `VNImageRequestHandler(cvPixelBuffer:)`
   without copying), `PumpRowDetector.detect` → `PumpReader.rescueStackedRows` → the same
   size and stacking rules PU.38's fast verdict uses (do not duplicate them: expose the
   verdict-from-rows function from `PumpDisplayCapture` if it is private, and call it). One
   analysis in flight at a time; the rest of the frames are dropped.
2. **The state** (a small enum, debounced over ~3 consecutive frames so it does not flicker):
   - `searching` - no row: no overlay, the caption stays as it is today;
   - `tooSmall` - rows found but the widest under the size rule (`minimumRowHeightFraction`,
     `minimumWidestRowFraction`): hint **"Move closer"** and, when the device has a zoom
     range, offer a **2×** tap on the hint that sets `videoZoomFactor` (undo on leaving the
     screen); 
   - `oneRow` - one stacked row short: **"Tilt to show the whole display"**;
   - `ready` - two stacked rows passing: the rows drawn as a thin outline on the preview in
     the headlight/taillight token the palette assigns to fuel (`docs/DESIGN.md`) and the
     caption **"Display in view"**.
   The shutter is **never disabled** by the state (hard rule 15: scanning is a head start; a
   photo the detector could not read is still the user's to take), and the manual door is
   untouched.
3. **Mode awareness**: only in the fill-up scan mode (`CaptureView`'s mode row); expense and
   receipt-only modes get no guidance (a receipt has no rows to find - the receipt caption
   stands). The reader must be loaded (`CapturePipeline.pumpReader != nil`) - with it missing,
   nothing runs.
4. **Cost**: the analyser must not touch the main thread except to publish the state; measure
   and print (in the UI test's log or a DEBUG print) the per-frame analysis time on the
   simulator and note that the device number is RV.295's.
5. **The journey**: J4's text gains the hint as the first step ("the preview says when the
   display is in view; the shutter is the user's either way"); a `→` marker if you judge it
   v1.1, unmarked if v1 - say which and why in the report.

## Explicitly out of scope

Applying a production preset (PU.40's other half), any change to what the shutter captures
or how the photo is read, the alpha notice, receipts.

## Tests

- `swift test` is **2226** and the app-target bundle **287**; both must not fall (RV.302 is
  the pre-existing red). Unit tests for the state machine with synthetic rows (no camera):
  two stacked rows → `ready`; one → `oneRow`; two side by side → `oneRow` (not ready); rows
  under the size rule → `tooSmall`; the debounce holds a state for 3 frames before switching;
  a row below `rescueConfidence` counts only when rescued.
- **UI test**, signed, by name: with `CameraController.testFrame` set to a heldout-like pump
  photo the app can ship in its test bundle (there is a fixture the existing capture tests
  use - reuse it), the capture screen shows "Display in view"; with a receipt frame it shows
  the plain caption. Report the count.
- **Mutation named by this brief:** drop the stacking condition from the state machine -
  the side-by-side test goes red. Paste red and green verbatim.
- **Screenshots EN + RU**, dark, of the `ready` state with the outline drawn (the test
  frame): `design/screenshots/PU.40b-capture-guidance.png` and `-ru.png`; capture lines in
  the script. RU: `Наведите ближе` / `Наклоните…` must not truncate under the caption's width.

## Checks (by exit code)

`scripts/gate.sh` and `RELEASE=1 scripts/gate.sh` (app code); `swiftlint lint` from the root
→ 0; the localization gate → 0; the named UI suite signed, non-zero count;
`bash scripts/check-screenshot-manifest.sh` (pre-existing red on `PU.29-confirm-pump-alpha`
- report it as such).

## Report back

The state machine as built and the debounce; per-frame analysis time on the simulator; the
UI test count; the mutation red/green verbatim; both gates' exits and counts; the two
screenshots' paths; the J4 text you added and its marker; anything found and not fixed with
the row that owns it.

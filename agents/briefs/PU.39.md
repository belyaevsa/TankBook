# PU.39 - the Capture Lab: a DEBUG screen that shoots one scene under every camera preset and records time, size and what the reader made of it

**Parent journey:** J4 (and J3 - receipts are shot the same way). **Row:** `docs/TASKS.md` →
PU.39 (filed with this brief). **Product owner, 2026-09-21:** *"build for a debug build a
screen, where I will have presets of different settings. I will capture receipts, pump. After
that we will measure time, size, quality to choose the sufficient."* **Read first:**
`ios/App/Sources/Capture/CameraCapture.swift` (the `AVCaptureSession` the app owns - `.photo`
preset, `.near` focus restriction, an empty `AVCapturePhotoSettings()`; the delegate that turns
`fileDataRepresentation()` into a `UIImage` with its EXIF orientation - RV.49), `CameraPreview.swift`,
`CapturePipeline.swift` (`process(_:source:)` - the classification + pump read, or the receipt
path; the `capture.classify` and `capture.pipeline` lines), `ios/App/Sources/Settings/AboutView.swift`
(the `#if DEBUG` seams and how a DEBUG-only screen is reached), `docs/DESIGN.md` (tokens - even a
debug screen uses them, hard rule 5/6), `docs/LOGGING.md` §4 (hard rule 12 - a lab log in the
app's Documents is fine, the OSLog is not).

## The situation

Every setting on the camera is ours and almost none is set. The reader's misses on real phone
photos are exposure and focus (dim LCDs against bright panels, glare, a forecourt in focus
behind the digits) and size (rows under 2.5 % of the frame). Before choosing settings by
argument, the owner wants to shoot the SAME scene under several presets in one go and compare
by measurement: capture latency, bytes, pixel size, and what the reader committed. That is
this screen. It is DEBUG-only and never ships (`#if DEBUG` around every file it adds - the
Release gate is what proves it).

## Where you may write

New files under `ios/App/Sources/Capture/Lab/` (all `#if DEBUG`), `CameraCapture.swift` (a
`capture(settings:)` overload and a way to apply a preset's device configuration - the existing
`capture()` must behave exactly as before), `AboutView.swift` or `SettingsView.swift` (one
DEBUG-only row that opens the lab), `project.yml` only if a new folder needs listing (it does
not - `ios/App/Sources` is a folder source), `Localizable.xcstrings` (EN + RU for every string
on the screen - hard rule 10 has no debug exemption), `scripts/capture-screenshots.sh` (the two
capture lines), `design/screenshots/PU.39-capture-lab{,-ru}.png`, `docs/TASKS.md` nothing (the
orchestrator ticks). **Not** the reader, `CapturePipeline.process`'s behaviour, `CaptureView`,
anything under `Spike/`.

## Write code first, explore second

## What to build

1. **Presets** (`CaptureLabPreset`, a value with a stable `id` and a one-line description):
   - `default` - exactly today's capture (the control);
   - `quality` - `photoQualityPrioritization = .quality` (`maxPhotoQualityPrioritization` set
     on the output first);
   - `speed` - `.speed`;
   - `metered` - default + `exposurePointOfInterest`/`focusPointOfInterest` at the frame centre
     with `.continuousAutoExposure`/`.continuousAutoFocus`, `exposureTargetBias = -0.5`;
   - `locked` - `metered`, then focus and exposure LOCKED after they converge (observe
     `isAdjustingFocus`/`isAdjustingExposure`, cap the wait at 1.5 s), flash `.off`;
   - `zoom2x` - `metered` at `videoZoomFactor = 2` (or the telephoto if the device has one);
   - `high1080` - the `.high` session preset (~1080p) with `.speed` - the floor, to see what
     a small photo costs the reader.
   Each preset knows how to apply itself to the device/output (`lockForConfiguration`, guard
   every capability with the `isSupported`/`canSet…` check - a preset an iPhone 12 cannot do
   says so in the log rather than crashing) and how to undo itself (the next preset starts from
   the control).
2. **The screen** (`CaptureLabView`): the live preview (reuse `CameraPreview`), a segmented
   choice **receipt / pump** (which pipeline scores the shot), the list of presets with a
   checkbox each (all on by default), one big **shutter**. One press shoots the presets in
   order, back-to-back, on the same scene - the owner holds still; a preset's apply → capture →
   deliver is timed. A counter shows progress. When the run ends, a **results table** on the
   same screen: preset · capture ms · pixels (w×h) · bytes · classify path · display? · rows ·
   fields committed (count, not values on screen - the values go to the log) · pipeline ms ·
   for receipts: fields resolved (count) and cross-check state.
3. **The log** (`Documents/CaptureLab/<yyyy-MM-dd-HHmmss>/`): every photo as
   `<preset>.jpg` (the bytes the camera delivered - `fileDataRepresentation()`, untouched, so
   the corpus intake can take it), and `run.json` with, per preset: the preset id and what it
   actually applied (every capability that was unsupported), `captureMs`, `bytes`, `width`,
   `height`, EXIF exposure/ISO/focal if `photo.metadata` carries them, and the reader's
   outcome: `classifyPath`, `isDisplay`, `rows`, `textLines`, `committed` (the three values -
   this is the owner's lab log on the owner's device, not telemetry; hard rule 12 governs the
   OSLog, which gets nothing from this screen beyond what `CapturePipeline` already emits),
   `pipelineMs`, and for a receipt the resolved fields and cross-check. A **Share** button
   sends the session folder's files through `UIActivityViewController` (AirDrop to the Mac).
4. **The scoring uses the production path**: `CapturePipeline.process(image, source: nil)`
   for pump (so the classification decides, exactly as a real capture) and `source: .receipt`
   for receipts; nothing in `CapturePipeline` changes.
5. **Entry point**: a row in the DEBUG section of About/Settings, "Capture lab".

## Explicitly out of scope

Choosing a preset for production (that is the owner's, after the measurement - PU.40 will
carry it); the preview-time detector guidance (PU.40); changing `CaptureView`; the corpus intake
of the photos (the owner runs the intake skill on the shared folder).

## Tests

- `swift test` is **2226** (one pre-existing red, `RV.302`'s - report it as such). Unit tests
  in the app-target bundle (`ios/App/Tests` or wherever `TankbookTests` lives - find it) for:
  the run log's JSON shape (encode one result, decode it back, every field present); the
  preset list's ids are unique and `default` applies nothing; an unsupported capability is
  recorded, not thrown (inject a fake capability set).
- **UI**: one `CaptureUITests` (or a new `CaptureLabUITests`) test that opens the lab from
  Settings in DEBUG, sees the seven presets and the shutter, presses it with the test frame
  (`CameraController.testFrame` exists for the simulator - use it), and sees a results table
  with seven rows. Run it by name, signed (never `CODE_SIGNING_ALLOWED=NO` for the UI bundle),
  report the count.
- **Mutation named by this brief:** make every preset apply the control's settings (ignore the
  preset) - the "unsupported capability is recorded" test and the run log's `applied` field go
  red. Paste red and green verbatim.
- **Screenshots EN + RU**, dark theme, of the lab with a results table (the simulator's test
  frame is fine): `design/screenshots/PU.39-capture-lab.png` and `-ru.png`, capture lines in
  `scripts/capture-screenshots.sh`. RU expands: the table's headers must not truncate.

## Checks (by exit code)

`scripts/gate.sh` **and** `RELEASE=1 scripts/gate.sh` (every new file is `#if DEBUG`; the
Release build is the proof). `swiftlint lint` from the root → 0. Localization gate → 0, EN + RU
keys. The named UI test, signed, non-zero count. `bash scripts/check-screenshot-manifest.sh`
(pre-existing red on `PU.29-confirm-pump-alpha` - report it as such).

## Report back

The preset list as built and which capabilities each phone-agnostic guard covers; the run
log's schema; the simulator run's table (seven rows); the mutation red/green; both gates'
exits and counts; the UI test's count; the two screenshots' paths; anything found and not
fixed with the row that owns it.

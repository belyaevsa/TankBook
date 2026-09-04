# RV.49 – the in-app shutter hands Vision every photo sideways

Found 2026-09-04 while answering a product-owner question about camera features. **Not reported by
a user, because nothing surfaces it** - and the harness that should have caught it structurally
cannot.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**
**Do not touch `docs/TASKS.md`.** Touch no `backend/` file.

**Use the `iPhone 17` simulator for xcodebuild/xcrun steps.** Another agent may hold `iPhone 17 Pro
Max`; check with `pgrep -x opencode` and say in your report what you found.

**Never move, rename or delete a file you did not create.** On 2026-09-04 an agent moved another
session's uncommitted migration out of the repo to clean its baseline; it was 56 KB of unsaved work.
If something in the tree breaks your gate and is not yours, **report it and carry on**.

## The chain, verified end to end - do not re-derive it, but DO confirm it before fixing

1. **`CameraCapture.start()` never sets the connection's rotation.** `grep` finds no
   `connection(with:)`, `videoRotationAngle` or `videoOrientation` anywhere in `ios/App/Sources/`.
   So `AVCapturePhotoOutput` delivers the buffer in the sensor's native **landscape** orientation,
   regardless of how the phone is held.
2. **`CameraCapture.swift:70`** does `photo.cgImageRepresentation().map { UIImage(cgImage: $0) }`.
   `UIImage(cgImage:)` marks the image **`.up`** - the orientation is not wrong, it is **discarded**.
3. **`CapturePipeline.swift:49`** calls `VisionTextRecognizer.recognizeText(image: cgImage, …)`,
   which builds `VNImageRequestHandler(cgImage: image, options: [:])` - **no `orientation:`
   argument**, so Vision assumes `.up` as well.

Net effect: **a portrait-held phone photographing a receipt produces a 90°-rotated image that Vision
is told is upright.**

## Why nobody caught it, and why a green corpus proves nothing here

The OCR corpus harness reads **files**, and the file entry point `recognizeText(in url:)` uses
`VNImageRequestHandler(url:)`, which **does** honour EXIF. So the corpus measures the parser on
correctly-oriented images while the live camera path feeds it rotated ones.

**The measured 38.3% receipt rate is therefore an upper bound the in-app shutter may never reach,
and the harness cannot show the gap.** The photo-library and attachment paths are unaffected - they
go through files.

**So: the corpus gate will NOT move when you fix this, and a green corpus must not be reported as
evidence.** Say so explicitly in your report.

## What to fix - and do not stop one layer short

- **Set the photo connection's rotation** from the interface orientation at capture time.
- **Carry the orientation through instead of dropping it**: prefer
  `photo.fileDataRepresentation()` → `UIImage(data:)` (EXIF preserved), or construct
  `UIImage(cgImage:scale:orientation:)` from the photo metadata.
- **Pass it on.** `recognizeText(image:languages:)` must take an orientation and hand it to
  `VNImageRequestHandler(cgImage:orientation:options:)`. **A fix that corrects the `UIImage` but
  leaves the Vision handler at `.up` fixes nothing** - the handler reads the `CGImage`, which has no
  orientation of its own.
- Check the **landscape and upside-down** cases while you are here, and iPad if it is cheap.

**Do not change the parser, the vocabularies or the extraction thresholds.** This row is about the
image reaching Vision the right way up. If you believe a parser change is warranted, say so and
leave it.

## The measurement IS the deliverable, not just the diff

1. **An L5 that fails today and passes after.** OCR a corpus fixture **rotated 90°** through the
   **`cgImage` entry point** (not the URL one - the URL one already works, which is the whole point)
   and assert the recognised line count and key values match the upright run. That test is the only
   honest proof, because every existing gate stays green either way.
2. **Run the corpus gate before and after and report both** - to show it did not move, not to claim
   success.
3. **Measure the live path.** Capture a real receipt on the simulator or device through the in-app
   shutter, before and after, and report both extraction results. That is the number this row exists
   to move. If you cannot drive the shutter on the simulator, say so plainly rather than inventing
   a number.

**Vacuous-assertion traps, named:**
- Reporting the corpus gate as evidence. It is green today and will be green after.
- Asserting the `UIImage.imageOrientation` is correct without asserting what **Vision** returns -
  the bug is what Vision is told, not what the `UIImage` says.
- A rotated-fixture test that passes before your change. If it does, your fixture is not actually
  reaching the `cgImage` path - check it fails first.

**Mutation-check and report it**: after the fix, drop the orientation argument at the
`VNImageRequestHandler` call site and confirm the rotated-fixture test goes red. Restore
byte-for-byte, confirm green.

## While you are in this file - two cheap wins, but ONLY if they stay small

`CameraCapture.swift` is 75 lines and deliberately minimal. Two things are one-liners and pull the
same lever this row exists for:

- **`session.sessionPreset = .photo`.** It is unset today, so it defaults to `.high` (~1080p) - the
  app OCRs small print at a fraction of the sensor's resolution. **Measure it**: report the captured
  pixel dimensions before and after, and the extraction result on the same receipt.
- **Autofocus range restriction to `.near`** when the device supports it (`isAutoFocusRangeRestrictionSupported`).

**Torch, tap-to-focus, zoom and device selection are OUT of scope** - they need UI and their own
decisions. If you find the preset change regresses anything, keep the orientation fix and drop the
preset, saying why.

## Read before writing

1. **`CLAUDE.md`** - hard rules 12 (log the orientation as a code, never the image), 14, and 15
   (capture is a head start, never an answer - this row is about making the head start real).
2. `docs/EXTRACTION.md` - the pipeline stages and the named failure modes; `docs/VISION.md` for the
   recognizer's configuration rationale.
3. `ios/App/Sources/Capture/CameraCapture.swift`, `ios/App/Sources/Capture/CapturePipeline.swift`,
   `ios/Sources/TankbookCore/Extraction/VisionTextRecognizer.swift`,
   `Spike/ReceiptSpike/` (the corpus harness and its fixtures).

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"          # from the repo ROOT
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Today: iOS 1239 tests. Must not fall.** Echo the exit code from the COMMAND, never through a pipe
(`cmd | tail -2 ; echo $?` reports `tail`'s status); redirect to a file instead. Run swiftlint from
the **repo root**. Match the process NAME (`pgrep -x xcodebuild`); **never `pgrep -f`/`pkill -f`**.

## Screenshots

Probably none - no user-visible surface changes. Say "none applies" rather than fabricating one. If
you add any capture UI (you should not - it is out of scope), it needs EN + RU.

## Report back

- Exit codes (captured, not piped), test counts before/after, the mutation result.
- **The rotated-fixture test: confirm it FAILED before your change** and passes after. Quote the
  failure.
- **The corpus gate before and after**, stated as "unchanged, as predicted" - not as evidence.
- **The live-path measurement**, or a plain statement that you could not drive the shutter.
- If you took the `.photo` preset: the captured pixel dimensions before and after.
- Whether landscape/upside-down are handled, and anything you left.

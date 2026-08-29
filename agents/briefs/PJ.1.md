# Task PJ.1 - the capture pipeline: make an image become a prefill

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 1, order 1** - the highest-priority row in the project. This is **the hero feature, and it
does not exist**: no camera frame and no Photos pick ever becomes a `ConfirmPrefill`. A
"scan, don't type" app whose scan door is painted on is not this product, and **P2's exit gate
(5 live fill-ups under 15 s) cannot be measured until this lands.**

**PJ.2** (persist the scanned photo as an `Attachment`) is the follow-up row and is **out of scope
here** - it needs this pipeline to exist first.

## Where you may write

```
ios/App/Sources/Capture/**
ios/App/Sources/ConfirmManual/**
ios/Sources/TankbookCore/Extraction/**
ios/Tests/TankbookCoreTests/**
ios/App/UITests/CaptureUITests.swift
```

**Do not** touch `ios/Sources/TankbookCore/Config/**` or `ios/App/Sources/Config/**` - another
agent holds that lane and you will conflict. Nor `backend/`, `site/`, `deploy/`, `.github/`,
`Spike/` (the corpus is **read-only** to you), `project.yml`, `design/`.
**Do not commit. Do not tick `docs/TASKS.md`.**

## Write code first, explore second

Everything below was verified in the source by the orchestrator before this brief was written.

## The defect, verified

```
ios/App/Sources/Capture/CaptureView.swift:14   "The shutter circle is decorative in this task."
ios/App/Sources/Capture/CaptureView.swift:144  detection = .sample        // a SIMULATED frame
ios/App/Sources/Capture/CaptureView.swift:32   @State private var pickedImage: UIImage?
ios/App/Sources/Capture/CaptureView.swift:92   pickedImage = image        // written, and NEVER READ
```

The Confirm sheet's prefill seam is fully built and documented - and its own header says
(`ios/App/Sources/ConfirmManual/ConfirmPrefill.swift:11`):

> Nothing here produces an extraction - this consumes one.

Today the **only** producer is `-seedConfirmPrefill*` launch arguments. Every fill-up in the
shipping app is typed, and the Photos button silently discards the picked image.

## What already exists - do not rebuild any of it

| Piece | Where |
|---|---|
| OCR | `TankbookCore.VisionTextRecognizer.recognizeText(image: CGImage, languages:) -> [OCRLine]` |
| Parsing | `TankbookCore.FuelExtractor.extract(lines: [OCRLine], source:) -> FuelExtraction` |
| QR | `FiscalQRParser` + `FiscalQRAnchor` in core |
| The sheet's input | app `struct ConfirmPrefill { extraction, crops, qrAnchor, ocrLines, sourceImage, currencyLowConfidence }` |
| The destination | `ManualFillUpView`, which already renders a prefill, dims resolved fields and locks on cross-check |

Your job is **assembly**, not invention.

## The one design constraint that decides whether this is testable

**There is no app unit-test target** - `project.yml` has the app and a UI-test bundle, nothing else.
So anything you put in `ios/App/Sources` can be covered **only** by XCUITest, which asserts
behaviour and never values.

Therefore: **the assembler's decision-making must live in `TankbookCore`**, as a pure function over
values -

```
([OCRLine], qrPayload: String?, source: ExtractionSource) -> (FuelExtraction, FiscalQRAnchor?, crop rects)
```

- and the app layer stays a thin shell doing only `UIImage -> CGImage`, calling Vision, and wrapping
the result in `ConfirmPrefill` with the images attached. Crop **rects** are values and belong in
core; `UIImage` crops are app-side.

This is the P3.7 lesson: `AppTabBar`'s padding arithmetic lived in the app target, so a
double-counted inset survived two whole phases "verified by looking at one device". Do not repeat it.
**If you find yourself wanting an app-side unit test, you have put logic in the wrong tier.**

## What to build

1. **The shutter takes a real frame** and the Photos pick is read - both feed one path.
2. **That path**: image -> `VisionTextRecognizer` + `VNDetectBarcodesRequest` -> `FuelExtractor` /
   `FiscalQRParser` -> the core assembler above -> `ConfirmPrefill` (extraction, per-field crops,
   QR anchor, `ocrLines`, `sourceImage`) -> the existing `ManualFillUpView`.
3. **Delete `CaptureDetection.sample` from the live layout** and the "decorative shutter" comment.
   A simulated detection frame left in a shipping screen is a lie told to the user.
4. **A resolved-nothing scan opens the ordinary empty manual form** - never an error, never a dead
   end (**hard rule 15**, and `ConfirmPrefill`'s own contract: "a nil extraction IS the manual
   form"). A poor scan degrades to "correct two fields", never to "start over".
5. Whatever the extraction produced remains **fully editable** (**hard rule 13**) - it is a default
   input, not a fact.

## Explicitly out of scope

Persisting the photo as an `Attachment`, `provenance` and `ExtractionMeta` at save (**PJ.2**) ·
pump-photo mode (P2.7 ships off, gated) · the cloud gateway (P6.3) · mixed-receipt UI (P2.4, already
built) · any change to `FuelExtractor`'s parsing rules or the corpus · `docs/TASKS.md` · committing.

**Do not touch the accuracy ratchet or `high-water.json`.** If your work changes a corpus score, stop
and report it - that is a finding about the parser, not something to renumber.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 904 today. MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L1 (core, the real gate)**: a corpus fixture's `[OCRLine]` through the new assembler yields the
  extraction that fixture expects, a crop rect per resolved field, and a QR-only fixture yields an
  anchor with no OCR total. Core tests already reach the corpus - copy the path helper from
  `ios/Tests/TankbookCoreTests/AccuracyRatchetTests.swift:106`
  (`.appendingPathComponent("Spike/ReceiptSpike/fixtures")`).
- **L4 `CaptureUITests`**: `-cameraStatus authorized` + an **injected fixture image** -> the shutter
  opens Confirm with litres pre-filled and dimmed; Photos -> picker -> the same sheet. **Neither test
  may pass `-seedConfirmPrefill*`** - that argument is the thing this task replaces, and a test that
  keeps it proves nothing.

Run **only** that suite, and **report the observed count** - a selector matching nothing prints
"Executed 0 tests" and reads like success:

```
xcodebuild ... -only-testing:TankbookUITests/CaptureUITests test
```

**Do not run the full UI suite** (standing rule, 2026-08-29). **Never `pgrep -f`** for a build - your
brief is your command line, and that has killed a sibling agent 48 minutes in. Use `pgrep -x
xcodebuild`, never `pkill -f`.

## Mutations you must run and report

1. Make the assembler return a **nil extraction** for a fixture that resolves fields. The L1 test
   must fail.
2. Drop the crop rects while keeping the values. A test must fail, or the crops are unasserted.
3. Make a resolved-nothing scan present an **error state** instead of the empty form. A test must
   fail - this is hard rule 15, and it is the one a green suite is most likely to miss.
4. Re-add `-seedConfirmPrefill` to a `CaptureUITests` case. It must still pass **with the pipeline
   broken** - demonstrating why the brief forbids it. Report that contrast.

A mutation that does not fail is a finding. One that does not **compile** proves nothing. Use a
**heredoc** for scripted edits.

## Screenshots

EN **and** RU, dark, per the standing convention - the capture screen and the Confirm sheet it
opens. Capture **outside** a test run (`simctl` and `xcodebuild test` fight over the device), and
name the files `PJ.1-<screen>.png` / `PJ.1-<screen>-ru.png`. You cannot see them; the orchestrator
opens every one.

## Report back

Every command with its **real exit code** and observed counts; all four mutation results; which
logic you placed in core versus the app **and why**; the files changed; and anything in this brief
that is wrong - five agent refusals in this project have been correct.

En-dashes only, never em-dashes.

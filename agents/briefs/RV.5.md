# RV.5 – the capture review step (preview, Use this, Re-take)

Reported by the product owner from a device walk on the TestFlight build: a shot is
taken and the flow moves straight on with **nothing shown**. The user cannot see what
was captured, cannot accept it, and cannot re-take it. Registered as RV.5 in
`docs/TASKS.md`.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. Everything you need is in that
checkout; write nothing outside it, including no temp files elsewhere. If a path looks
like it needs writing outside the repo, the answer is that it does not.

**Do not run `git commit`.** The orchestrator commits after verifying independently.

## Write code first, explore second

The dominant failure mode in this repo's agent runs is a run that reads everything and
writes nothing. You have the file map below; open those files, then start writing.

## What already exists (build on it, do not redesign it)

`ios/App/Sources/Capture/`:

- `CaptureView.swift` – the capture screen. **The two call sites you are changing are
  `processScanned(_:)` (line ~202, the Photos pick) and `captureFrame()` (line ~215,
  the shutter).** Both today do exactly this and nothing else:

      let prefill = await CapturePipeline.process(image, source: .receipt)
      activeSheet = .scanned(prefill)

- `CaptureSheet` (in `ScannedFillUpSheet.swift`) – the `Identifiable` enum driving
  `.sheet(item: $activeSheet)`, with cases `manualForm`, `photoPicker`, `documentCamera`,
  `scanned(ConfirmPrefill)`. Its `Equatable` conformance compares the CASE only, because
  `ConfirmPrefill` carries a `UIImage`; keep that property if you add a case.
- `CapturePipeline.process(_:source:)` – `UIImage` in, `ConfirmPrefill` out. **It is
  cheap-ish but not free** (Vision OCR + QR on a full-resolution image), so decide
  deliberately whether the review step runs before or after it, and say which in a
  comment. Preferred: show the review IMMEDIATELY on the raw image and run the pipeline
  only once the user accepts – a re-take then costs no OCR at all.
- `ConfirmPrefill` (`ios/App/Sources/ConfirmManual/ConfirmPrefill.swift`) carries
  `sourceImage`.
- `-captureFixtureImage <path>` is the existing test double: with it set, BOTH the
  shutter and the Photos pick resolve to that image. Your L4 test uses it; do not invent
  a second mechanism.

## Read before writing, in this order

1. **`CLAUDE.md`** – the hard rules. Rules 15, 13, 7 and 10 all bind here; rule 15 is the
   authority for this task.
2. `docs/JOURNEYS.md` – J1 and J3 (the capture journeys). Your change adds a step to both.
3. `docs/SCREENMAP.md` – the navigation graph and the back-path conventions.
4. `docs/ERRORS.md` – the severity vocabulary and the "every error names its next step" rule.
5. `docs/DESIGN.md` – the Night Drive tokens, DIN/SF typography, and the **Motion** section:
   "Capture handoff: the receipt photo shrinks into the Pump Card". Nothing else animates
   beyond system defaults.

## What to build

A **review step between the capture and the Confirm sheet**, shown for both doors (the
shutter and the Photos pick), carrying:

1. **The captured image, large enough to judge** – can the user read the total on it?
   That is the question this screen answers. Fit the image, do not crop it to a chip.
2. **Use this** – proceeds exactly where the flow goes today: run the pipeline (if you
   deferred it) and present `.scanned(prefill)`.
3. **Re-take** – returns to the live camera with nothing kept.
4. **Type it instead** – the manual door, present as a **peer**, not a consolation.
   Hard rule 15 is explicit: "Any screen that makes manual entry harder to reach than
   capture, or that frames it as the failure branch, is a bug." Do not write copy in which
   typing is what you do when the photo is bad.

Copy is EN + RU in `ios/App/Sources/Localizable.xcstrings` (hard rule 10). RU runs 20–30%
longer and short strings expand worst; **never compose a string by concatenation** – write
a full localised phrase per language (the P1.4 bug: `"%@ spend"` + `"%@ расходы"` rendered
"АВГУСТ РАСХОДЫ").

Extend `docs/JOURNEYS.md`, `docs/SCREENMAP.md` and `docs/ERRORS.md` **in the same change** –
the docs are the spec, not documentation-after-the-fact, and a new screen that appears in
none of them is an unfinished task, not a finished one.

## Explicitly out of scope

- **Do not change where Save lands.** That is RV.12 (saving a captured entry re-opens the
  camera), a separate row, and the orchestrator is handling it. Touching the post-save
  destination here will collide.
- Do not touch `ManualFillUpView.swift`, `ManualFillUpGatewayBanner.swift` or
  `GatewayCaptureUITests.swift` – RV.8 just landed there.
- No cropping, rotation, filters, or multi-page capture. One image, accept or re-take.
- No changes to `CapturePipeline`'s recognition behaviour.

## What NOT to explore (closed questions)

- Whether the manual door should exist – it must; hard rule 15, decided.
- Whether to use a `.sheet` or a `fullScreenCover` – use whichever presents the image at a
  size a person can read a receipt total at, and say why in one comment. Do not survey.
- The palette – all colours come from `Theme.Palette` tokens. No ad-hoc hex (hard rule 5).

## Tests

- `cd ios && swift test` – **873 unit tests today; the number must not fall.**
- L4 in `ios/App/UITests/` (a new file, or the existing capture suite): with
  `-captureFixtureImage` set, a capture shows the image and **both `Use this` and
  `Re-take` are reachable**; `Use this` reaches the Confirm sheet; `Re-take` returns to
  capture and does NOT present Confirm.
- Name the suites you ran and **report the observed test count**. A `-only-testing:` or
  `--filter` that matches nothing prints "0 tests … passed", which is not a pass.

**Vacuous-assertion traps for this task, named:**
- Asserting an element `exists` for an identifier you also added to the OLD screen – it
  passes with the feature absent.
- Asserting `Re-take` exists without asserting that after tapping it the Confirm sheet is
  **not** presented. Existence is not behaviour.
- A test that never sets `-captureFixtureImage`: on the simulator there is no camera, so
  it exercises the permission screen and proves nothing about this feature.

## The baseline gate (CLAUDE.md rule 14)

Before anything else counts:

    swift build ; echo "BUILD=$?"
    cd /Users/sbelyaev/repos/fuel-counter-ios && swiftlint lint ; echo "LINT=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Judge by the exit code you echoed, not by skimming output**, and run swiftlint from the
repo root (the `excluded:` paths are root-relative). Zero lint ERRORS is the standard.
`ManualFillUpView.swift` sits at 635 of its 700-line limit and `file_length` is an error,
not a warning – if a file you touch approaches 700, split it rather than loosening the rule.

If you check whether the simulator is free, match the process NAME (`pgrep -x xcodebuild`).
**Never `pgrep -f` or `pkill -f`** on a build/test pattern: an agent's brief is part of its
command line, and on 2026-08-24 exactly that killed another agent 48 minutes into its task.

## Screenshots

`design/screenshots/RV.5-capture-review.png` and `-ru.png`, dark theme, captured from a
booted simulator **outside any test run** (`simctl` and `xcodebuild test` fight over the
device). RU:

    xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU

Pass `-homeResetDatabase` alongside any seed – the seeds are idempotent and silently do
nothing on a populated database, which renders "Entry not found" instead of the screen.

**You cannot see your own screenshot.** Verify what is in it by the accessibility tree, and
say in your report what you verified and how. The orchestrator opens both images personally.

## Report back

- The exit codes you observed for build, swiftlint, the app build, `swift test`, and each
  UI suite – the numbers, not a summary.
- The unit-test count before and after.
- The UI test names and the observed count per suite.
- **Whether each test was actually RUN, not only written.**
- Every file you created or modified, and the doc sections you extended.
- Anything you could not finish, named plainly. An honest gap is worth more than a green
  report that does not hold.

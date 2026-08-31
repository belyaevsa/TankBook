# PJ.12b – the capture caption promises what the build cannot do, to a car that could not use it

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`:

- `ios/App/Sources/Capture/CaptureView.swift` (the caption at line ~337, inside `liveLayout`)
- `ios/App/Sources/Localizable.xcstrings` – you own it this run. **Not line-mergeable**: add keys,
  never restructure the file.
- `ios/App/UITests/CaptureUITests.swift`
- `design/screenshots/`

No sibling lane is running. Do **NOT** touch `docs/TASKS.md`. **Never `git checkout`** to undo
anything - copy a backup back and verify with `md5`.

Write code first, explore second.

## Use this simulator

`iPhone 17`. **Never** `pgrep -f`/`pkill -f` for a build - a brief is part of the process command
line and that pattern once killed a sibling agent 48 minutes in. Use `pgrep -x xcodebuild`.

## The defect

`CaptureView.swift:337` renders, unconditionally:

> **"Receipts and pump displays are detected automatically"**
> RU: «Чеки и дисплеи заправок определяются автоматически»

Two false promises in one line:

1. **The build does not do it.** `PumpPhotoGate` measures **29/151** (19.2%) against a
   `threshold` of **0.95**, so pump mode **ships off**. Read those constants rather than trusting
   this number - they moved on 2026-08-31 when eight fixtures were added.
2. **It says it to EVs.** The screen renders the same sentence on an electric car, which has no
   fuel tank and no pump display to read.

This is the same over-promise class as **PJ.3b** (the Welcome tagline) and **W6** - copy written
before the corpus measured what capture can actually do. Hard rule 15 is the authority: a capture
is a **head start, not an answer**, and the app must not claim otherwise.

## What to build

Copy that **reads true for each powertrain** and does not claim automatic pump detection while the
gate fails.

The view already holds what you need: `@State private var powertrain: Powertrain` (line 40), set
from the selected car (line 124-132), and `CaptureMode.modes(for:)` already tailors the mode row -
so the caption can be tailored the same way, from the same source of truth. Do not add a second
mechanism for deciding what the screen offers.

Tie the pump claim to `PumpPhotoGate` rather than hard-coding today's answer: when the gate ships
on, the copy may say so; while it fails, it must not. A future reader turning the gate on should
not have to remember to edit a string.

EN and RU both. Read `docs/LOCALIZATION.md` first - **if a `%@` receives runtime data, the
surrounding phrase must not govern its case**; that error has shipped twice in Russian.

## Named vacuous traps

- **Asserting the caption renders.** It always does - that is the trap the task row names. Assert
  **which** sentence renders, for a given powertrain and gate state.
- Testing only the ICE path. The EV case is half the defect.
- Hard-coding "pump detection is off" so the copy lies again the day the gate passes.
- Softening the sentence into something vague enough to be true and useless ("Point at a receipt").
  It should still tell the user what the screen does.

## Checks

- `swift build --package-path ios` exit 0; `swiftlint lint` exit **0 from the repo root**.
  **`swift build` does not compile `ios/App`** - also `xcodebuild ... build` → `BUILD SUCCEEDED`.
  Keep files under **700 lines** (`file_length` is an error here).
- `swift test --package-path ios` – whole suite, never subsetted; it stood at **1121**.
- `xcodebuild ... -only-testing:TankbookUITests/CaptureUITests test` on `iPhone 17`, the whole
  suite, then `scripts/check-ui-test-count.sh` on the log.
- **Screenshots, EN + RU, dark**: the capture screen for an **ICE** car and for an **EV**
  (`design/screenshots/PJ.12b-capture-ice{,-ru}.png`, `PJ.12b-capture-ev{,-ru}.png`). The
  powertrain can be forced with the existing launch override (`arguments.powertrainOverride`,
  `CaptureView.swift:131`). `-homeResetDatabase` alongside the seed. **Reinstall the app before
  capturing after any mutation run** - `xcodebuild build` does not install, so the simulator
  otherwise keeps the reverted binary and you screenshot the mutant. **Never** set the RU language
  as a simulator-wide default; pass `-AppleLanguages "(ru)"` per launch.
- **Mutation**: force the gate to "shipping on" and confirm a test fails because the copy still
  claims detection is off (or vice versa) - proving the copy is tied to the gate, not to a
  constant. Restore by `md5`.

## Report back

The exact EN and RU sentences per powertrain and gate state; how the copy reads the gate; observed
counts and exit codes; the mutation result; the `md5` match; screenshot filenames. Say whether you
**ran** the tests or only wrote them. Do not commit.

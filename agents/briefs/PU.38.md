# PU.38 - classification from the detector alone: under 100 ms, and a cap on the fallback

**Parent journey:** J4. **Row:** `docs/TASKS.md` → PU.38 (filed with this brief). **Read first:**
`ios/Sources/TankbookCore/Extraction/PumpReader/PumpDisplayCapture.swift` (the whole file - the
classification and `read`/`classify`), `PumpRowDetector.swift`, `PumpReader.swift` →
`candidates(for:)`, `rescueStackedRows`, `verify`, `verdicts`; `ios/App/Sources/Capture/CapturePipeline.swift`
(the caller: `readPumpDisplay`, the `capture.classify` log line); `docs/EXTRACTION.md` → decision
10 and its 2026-09-21 amendment; `docs/EXTRACTION.md` → "P4.12" (the 3 s budget on device);
`ios/Tests/TankbookCoreTests/PumpDisplayCaptureTests.swift`.

## The situation

Every capture, attach and re-attach runs `PumpDisplayCapture.classify` to decide whether the
photo is a pump display before the receipt or the pump arm runs. Today that decision is made
AFTER the whole verifier has run: every candidate row (the detector's, plus Vision text boxes
and the classical projection when the detector found fewer than two) is warped, sliced and
every cell classified - then `displayRows` counts what survived. Measured on the Mac with
`pump-read` (`timingsMs`): detector 3-40 ms, Vision text-line count ~10 ms, **verify 770-3 546 ms
per photo, and the fallback path 28 s on pump-190**. On the phone (`docs/EXTRACTION.md` P4.12)
the reader has 3 s in total, and the classification is the part that runs on EVERY photo,
including every receipt.

The classification's own number: `PumpDisplayCaptureTests` → `PU.29 heldout classification:
4/6` pumps, 0 of 8 receipts (~200 s for the test - the verifier). The current rule:
`displayRows ≥ 2 && textLines ≤ 30 && widestRow ≥ 0.18`, where a display row is a verified row
taller than 2.5 % of the frame and (for a Vision row) with mean margin ≥ 1.5, or any detected
row.

## Where you may write

`PumpDisplayCapture.swift`, `PumpRowDetector.swift` (only if the detector needs to expose
something), `ios/Tests/TankbookCoreTests/PumpDisplayCaptureTests.swift` (a new test file for
the fast path is fine), `ios/App/Sources/Capture/CapturePipeline.swift` (only the
`capture.classify` line's fields, if the fast path adds a duration or a source to log - counts
only, hard rule 12), `ios/Sources/TankbookCore/Logging/LogEvents.swift` (`CaptureClassify`'s
fields, same rule), `docs/LOGGING.md` (the `capture.classify` paragraph, if the fields change),
`docs/EXTRACTION.md` (a paragraph under decision 10's amendment), `ml/pump-reader/REPORT.md`
("PU.38"). **Not** `PumpReader.swift`'s read path, the slicer, the law, the assigner, anything
under `Spike/`, the models.

## Write code first, explore second

## What to build

1. **A fast classification from the detector's rows alone.** `PumpDisplayCapture.classify`
   first asks the detector (`PumpReader.candidates(for:)` already returns its rows with the
   stacked-row rescue applied, each `detected`): the frame IS a display when **at least two
   detected rows pass** the existing size rules (`minimumRowHeightFraction`, `widestRow ≥ 0.18`)
   **and stack** (share an x-span - `PumpReader.sharesSpan`/`stacks` exist), at the detector's
   own confidence (≥ 0.3 for both, or one ≥ 0.5 and the other rescued). No warping, no slicing,
   no classifier for the decision - the reading runs afterwards, as it does now, only on a
   frame the decision accepted. The Vision text-line count stays as the receipt guard
   (`textLines ≤ 30`) - it is ~10 ms.
2. **The slow path only when the fast path abstains** (fewer than two detected rows): then the
   current full verify runs, exactly as today, so a head the detector never saw (Topaz, Tatsuno)
   still gets the Vision + classical chance - **but capped**: `PumpReader.maximumCandidates` (48)
   is the existing cap on candidates; add a wall-clock budget to the classification's slow path
   (`slowPathBudget`, start at 1.5 s; a constant with the P4.12 reason) after which the verdict
   is "not a display" for the classification (the read may still run on what was verified - do
   not change the read). Measure what the budget costs on the heldout: which of the 4/6 (and
   which receipts) change verdict.
3. **Measure both**: extend `PumpDisplayCaptureTests` to print per photo which path decided
   (`fast` / `slow`) and the milliseconds, and the totals: pumps classified (must not drop below
   4/6 - and say which of the two misses the fast path could rescue), receipts leaking (must
   stay 0 of 8 - extend to all receipts in the folder if the run stays under ~2 min with the
   fast path), and the median / max classification time on the Mac before and after.
4. **The `capture.classify` log line gains `path=fast|slow`** (a token, not a value) so the
   device's diagnostics say which path ran; `docs/LOGGING.md` updated in the same change.
5. **The app's `CapturePipeline` is unchanged** apart from the log field - it already calls
   `classify` and reads `.detection`/`.reading`.

## Explicitly out of scope

The read path (locate/verify for the READ stays as PU.35 left it), the models, the slicer,
the assigner, the UI, the alpha notice, device measurement (RV.295 - report what the Mac
numbers suggest, no more).

## Tests

- `swift test` is **2219** and must not fall (`RV277ExpenseTotalTests` is `RV.302`'s
  pre-existing red - report it as such). Unit tests with synthetic detector rows (no corpus):
  two stacked rows ≥ 0.3 classify fast; two rows side by side (a keypad beside a display) do
  not; one row ≥ 0.5 plus a rescued 0.2 under it classify fast; one row alone abstains to the
  slow path; a frame with 40 Vision text lines is not a display whatever the detector says.
- **Mutations named by this brief:** (1) drop the "stack" condition - the side-by-side test
  goes red; (2) set `slowPathBudget` to 0 - a test that feeds one detected row and a slow path
  that finds two (synthetic, or pump-190 if the corpus is present) shows the budget refusing.
  Paste red and green verbatim.
- Floors: `PumpDisplayCaptureTests` 4/6 pumps, 0 receipts; `PumpReaderPipelineTests` 80 / 0.96
  and 37 / 0.99 untouched (the read path is not changed - prove it by the print).
- Vacuous traps: a fast-path test whose rows would also pass the slow path; a timing assertion
  on wall clock (print, never assert, timings).

## Checks (by exit code)

`scripts/gate.sh` → report each step's exit and both counts (the app-target bundle separately,
281; `swift test` stops at RV.302's red). `swiftlint lint` from the root → 0, no new warnings in
touched files. **`RELEASE=1 scripts/gate.sh`** as well: `CapturePipeline.swift` is app code.
No UI change, no screenshots (the log field is not UI).

## Report back

The per-photo table (path, ms, verdict) before and after; the totals and the two floors; what
the budget costs; the two mutations red/green verbatim; gate exits and counts (Debug and
Release); the `capture.classify` field added; anything found and not fixed with the row that
owns it.

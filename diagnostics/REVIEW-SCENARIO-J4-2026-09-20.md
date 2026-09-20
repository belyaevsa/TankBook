# REVIEW-SCENARIO J4 · No receipt – pump display photo · 2026-09-20

Walked by the orchestrator (standing instruction 2026-09-12), read-only, after PU.33 shipped.
Rows naming J4: 36, of which 7 open (`RV.289`, `RV.290`, `RV.295`, `PU.5`, `PU.19`, `PU.34`,
`PU.6`). Adjacent: J3 (the receipt scan it mirrors), F2 (scan recognised wrong data).

## Verdict

**NOT IMPLEMENTED.** The capture-to-save chain the journey describes exists end to end and is
reachable; what is missing is the journey's own bar - *"it must feel as reliable as J3 or not
exist"* - which the shipped build meets by framing (the alpha notice), not by reading: on the
heldout split the live path reads 22 of 175 cells and 5 of 64 photos fully. Plus one promise
with no row and one fact that stops being carried after the save.

## Ticked rows found to be untrue

None. `PU.29`'s and `PU.33`'s claims hold at their cited lines (below). One ticked row is
narrower than its text: `PJ.12b`'s caption promises *"Receipts and pump displays are detected
automatically"* only above the gate (`ios/App/Sources/Capture/CaptureView.swift:528-533`) -
correct by design (PJ.12b), but it means the journey's *"→ prompt tip"* is currently withheld
from every user, see the map.

## Promise-to-code map

| promise (journey text) | status | where |
|---|---|---|
| camera at the pump display, before hanging up the nozzle | MET | the fill-up scan mode offers the camera with no receipt-only framing, `CaptureView.swift:528` caption; the capture door is the same as J3's |
| → prompt tip on first use: "no receipt? Shoot the pump" | **MISSING** (opportunity marker, `→` = v1.1 per `CLAUDE.md` version scope) - **no row carries it**; searched `Shoot the pump`, `no receipt` in `ios/App/Sources`, `Localizable.xcstrings`, `docs/TASKS.md`, `docs/TASKS-DONE.md` - nothing | the caption deliberately omits the pump claim below the gate (`CaptureView.swift:528-533`), so a first-time user is never told the pump is a target |
| OCR reads the three numbers, arithmetic triple-match assigns them | MET (as the reader, not OCR) | `PumpReader.readPhoto` `ios/Sources/TankbookCore/Extraction/PumpReader/PumpReader.swift:84-98`; roles `PumpRowAssignment.swift:36`; the law `PumpReadingLaw.swift` (`volume × price = total` the only judge) |
| ⚠ the ~95 % gate applies before this ships | MET as a gate; **PARTIAL as a measurement** | `PumpPhotoGate.allowsPumpPhoto` `ios/Sources/TankbookCore/Config/PumpPhotoGate.swift:96-98`; its constants hold the RULES arm's full-corpus score (`measuredCommitted = 56` of `611`, `:48-52`), not the reader's heldout numbers - the arm the journey now runs is measured elsewhere (`PumpReaderPipelineTests` floors 66 / 22). `PU.6` owns the reconciliation |
| station name auto-suggested from location + favourites | MET | PJ.19 shipped (station ranking in Confirm), see J4's own "Station suggestion" paragraph and its rows |
| a frame is a display by structure, never by strings | MET | `PumpDisplayCapture.Detection.isPumpDisplay` `PumpDisplayCapture.swift:18-22` (rows ≥ 2, text lines ≤ 30, widest row ≥ 0.18); detector rows counted on size `PumpDisplayCapture.swift:displayRows` |
| the same classification on capture, attach, re-attach, replace | MET | `CapturePipeline.process(_:source:)` `CapturePipeline.swift:42`; call sites `CaptureFillUpScan.swift`, `CaptureReviewView.swift`, `EditEntryView.swift:397,426,680`, `AttachmentViewerActions.swift:117`; `CaptureExpenseScan.swift` passes `.receipt` (an expense scan is never a pump) |
| a display runs the pump reader, arrives at Confirm as `.pumpPhoto`, committed fields pre-filled, the rest empty | MET | `CapturePipeline.swift:85-86` (`provenance = .pumpPhoto`, `pumpAlpha`), `ConfirmPrefill.swift:246` |
| below the gate the sheet says so - the alpha notice text | MET | `PumpDisplayAlphaNotice.swift:18`, `L10n+PU29.swift:9`, EN + RU in `Localizable.xcstrings`; UI test `CaptureUITests.testPumpCaptureBelowTheGatePrefillsWithTheAlphaNotice` (passes with the detector in the bundle, 2026-09-20) |
| typing stays the peer door | MET | the same Confirm form, `captureTypeItButton` in the UI test |
| a pump photo never runs the receipt parser in silence | MET | `CapturePipeline.swift:42-90`: a classified display takes the reader branch; a frame not classified runs the receipt path as before, which is the journey's "anything else" |
| the kind recorded on the attachment (`pump-reader v1`) | MET | `ManualFillUpReceiptSave.pipelineName(for:)` `:123`, `ScannedSavePlan.pumpReaderPipeline` `:85`; on re-attach `EditEntryView+FillReceiptSave.swift:48`, `AttachmentViewerActions.swift:117` |
| the entry carries `.pumpPhoto` | MET at the write; **PARTIAL after it** | written `ManualFillUpReceiptSave.swift:124,271`, `EditEntryView+FillReceiptSave.swift:53`; encoded `PayloadCodable.swift:92`. **No screen reads it back**: the Log row, the entry editor and the attachment viewer show nothing that says "read from a pump display" - searched `.pumpPhoto` readers in `ios/App/Sources`, all are writers or the gateway `kind` |
| the gateway asked with `kind: "pump"`, the ledger records it | MET | `ManualFillUpView.swift:453`; backend `LlmCallRepository.cs:19,88-94` (`kind` column) |
| the locator is automatic; no tap-to-frame | MET | decision 8; `PumpRowDetector` first, Vision + classical fallback (`PumpReader.candidates(for:)`, decision 10) |
| "as reliable as J3 or not exist" | **MISSING** | the honest numbers: heldout live path 22/175 cells, 5/64 photos (`PumpReaderPipelineTests` floors); J3's receipt arm reads 286/355 cells. The build ships the reading as alpha (decision 7) - the framing is honest, the bar is not met. `PU.5`, `PU.34`, `PU.6` |

## Sequence trace - one user, one fill, no receipt

1. Opens capture, points at the pump. No hint that a pump is a target (caption: receipts only) - they must know. *(the → tip, unowned)*
2. Shoots. `CapturePipeline.process` classifies: the detector finds ≥ 2 rows, ≤ 30 text lines → the reader runs (2.4 s on the Mac; **device latency never measured** - `PU.6` / `RV.295`).
3. Confirm opens as `.pumpPhoto` with the law's committed fields and the alpha notice. On the heldout split that is all three fields on 5 of 64 photos, some fields on 9, nothing on 55 - most users see an empty form with the notice. Honest (hard rules 13, 15); not J3-grade.
4. The user types the rest, picks the suggested station, saves. Attachment `pipeline: pump-reader v1`, entry `provenance: .pumpPhoto`, gateway `kind: pump`, ledger row. **Carried.**
5. Later, in the Log or the entry: nothing shows the entry came from a pump display; re-attaching a photo re-classifies (MET). **The fact is stored and never shown** - the one place the sequence drops it. Whether it should be shown is a product question (F2's "scan recognised wrong data" would want it: a pump-read entry is the one to double-check).

## Proposed rows

| row | deliverable | stage | consequence today | severity | check | scenario |
|---|---|---|---|---|---|---|
| PJ.new-a | The first-use tip the journey names ("no receipt? Shoot the pump") - shown once, on the capture screen, only while the pump path is offered (gate on or alpha), EN + RU | 1 | a user who skipped the receipt does not know the pump is a target; the feature is invisible | gap (v1.1 marker - file under [v1.1] unless the owner promotes it) | L4 `CaptureUITests`: tip on first launch, gone on the second; screenshots EN/RU | J4 |
| PJ.new-b | The pump provenance surfaced where the entry lives: a small "read from the pump display" mark on the Log row / entry header for `.pumpPhoto` entries (and `pipeline: pump-reader v1` in the attachment viewer's detail) | 5 | the kind is written and read by nothing on the device; F2's "double-check this one" has no handle | polish now, gap once the reader commits more | L1 on the row view model; L4 on the Log row | J4 (and F2) |
| (existing) PU.6 | reconcile `PumpPhotoGate`'s denominators with the reader's arms (rules arm 611; reader heldout 175) before any status line | 3 | the gate's coverage floor is against a number the reader never scores | gap | `PumpPhotoGateTests` asserts against the arm that runs | J4 |

Nothing else to file: `PU.5`, `PU.19`, `PU.34` already own the reading quality; `RV.295` owns the
device measurement; `RV.289/290` own the cloud pump prompt.

## Not settled

- **Device latency and the 3 s budget** (`docs/EXTRACTION.md` P4.12): every timing is a Mac
  harness number. Settled by one run on an iPhone 12 with the detector in the bundle (`RV.295`).
- **Whether the pump provenance should be visible** (PJ.new-b) is the owner's call; the review only
  records that it is stored and unread.

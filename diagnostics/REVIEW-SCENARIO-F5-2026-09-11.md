# REVIEW-SCENARIO F5 – 2026-09-11

## Verdict

**NOT IMPLEMENTED** – F5's total is delivered; F5's date is not. The QR date is
parsed, carried on the anchor to the Confirm sheet, and even written to the
attachment's `extractedTimestamp`, but it never reaches the Confirm form's date
field in production. The one function that would apply it (`composeQR`) is dead
code in the shipped path, exercised only by tests and the corpus scorer.

## Ticked rows found to be untrue

None. The only row naming F5, **PJ.47**, is a doc-reconciliation row and its tick
is accurate: the "fiscal service isn't answering" copy is gone and no user-facing
string names the QR (confirmed – no QR/fiscal key in `Localizable.xcstrings`,
VISION.md's 2026-08-30 decision holds). The gap below is a promise with **no row
at all** – the PJ.23 shape.

## Promise-to-code map

| F5 text | Verdict | Evidence |
|---|---|---|
| "Parse locally what the QR string itself carries (total, date-time, fiscal IDs)" | **MET** | `FiscalQRParser.parse` parses `s`/`t`/`fn`/`i`/`fp`/`n` – `FiscalQR.swift:141`, fields at `:24-31`. Offline, no networking – `FiscalQR.swift:17-18`. Detection wired: `CaptureQRDetector.detectPayload` `CapturePipeline.swift:104`, called from `recognize` `CapturePipeline.swift:64`. |
| "card pre-fills total … instantly" | **MET** | `ManualFillUpView.apply` → `ConfirmQRTotal.resolve` (`ManualFillUpView.swift:377-389`) → `applyTotal`. QR total authoritative on disagreement, fuel line stands on mixed – `ConfirmPrefill.swift:165-188`. |
| "card pre-fills … date instantly" | **MISSING** | `form.date` is set only from `extraction.date` (OCR) – `ManualFillUpView.swift:402-404`. The QR date on `prefill.qrAnchor` is never applied. `composeQR` (which overrides the date – `FuelExtractorTotalFinder.swift:18-31`) is only called from `extract(lines:source:qrAnchor:)` (`FuelExtractor.swift:108`), and the production assembler calls `extract` **without** the anchor: `ExtractionAssembler.swift:54-55`. |
| "liters/price are the user's, from OCR and editable" | **MET** | `FiscalQRAnchor.liters/unitPrice/fuelKind` always `nil` – `FiscalQR.swift:256-258,268-273`. Form litres/price from the extraction, editable – `ManualFillUpView.swift:396-397`. |
| "No copy: nothing failed, and the QR is not named" | **MET** | No user-facing QR/fiscal string; PJ.47 removed the failure copy. |
| "shows the anchored total … as verified" | **MET** | `.qrAuthoritative`/`.ocrConfirmed` applied without `resolvedByExtraction.insert(.total)`, so never dimmed – `ManualFillUpView.swift:382-389`. |
| "shows the anchored … date as verified" | **MISSING** | The QR date never lands, so there is nothing to show as verified; the date shown is OCR's (or the form default). |
| "Metric: ≥95% anchored total" | **PARTIAL** | Total half supported; the date half of the metric is unsupported by the shipped path. |

## Sequence trace (one user, one RU receipt with a decodable QR)

1. Scan the receipt → `CapturePipeline.recognize` returns OCR lines + `qrPayload` (`CapturePipeline.swift:61-68`).
2. `ExtractionAssembler.assemble` runs `extract` **without** the anchor (OCR-only total/date) and parses the QR into a separate `qrAnchor` (`ExtractionAssembler.swift:54-58`).
3. `ConfirmPrefill` carries both `extraction` and `qrAnchor` (`CapturePipeline.swift:43-49`).
4. `apply`: total ← `ConfirmQRTotal.resolve` (QR wins – carried ✓); date ← `extraction.date` only (**the QR date is dropped here**, `ManualFillUpView.swift:402-404`).
5. Save: `buildFillUp` writes `FillUp.date = form.date` (OCR date or default) – `ManualFillUpView.swift:649-658`. `fiscalIdentity` is never set (`:649-658`, no argument).
6. `writeReceiptPhoto` writes the attachment's `extractedTimestamp` = OCR date **else** QR date (`ManualFillUpReceiptSave.swift:237-238`).

**The fact that stops being carried:** the QR date rides `qrAnchor` all the way to
step 4, then is applied to the *attachment's* timestamp (`:237-238`) but not to
the *entry's* date. The entry saves with OCR's date (or today), while its
attachment records the correct QR date – two facts about the same receipt.

The divergence is test-visible: `RV56ExtractionTests.qrDateFillsOcrAbsence`
(`RV56ExtractionTests.swift:233-240`) asserts the QR date overrides the OCR date
– but it exercises `extract(..., qrAnchor:)`, which production never calls
(`ExtractionAssembler.swift:54-55`). RV.129's "tested decisions production does
not use" shape, on an output rather than a field.

## Proposed rows

| Row | Deliverable | Closes | Consequence today | Severity | Check | Scenario |
|---|---|---|---|---|---|---|
| **F5.1** | Apply the QR date to the Confirm form's date field when present – either the assembler passes the anchor into `extract` (so `composeQR` runs, `ExtractionAssembler.swift:54-55`) or `ManualFillUpView.apply` sets `form.date` from `prefill.qrAnchor.date` (`ManualFillUpView.swift:402-404`). The QR date outranks an absent or garbled OCR date (`SCHEMA.md` FISCAL QR). | "card pre-fills … date instantly" / "shows the anchored … date as verified" | A RU receipt whose QR decodes but whose date OCR missed saves with the wrong/default date, poisoning date-grouped stats; the authoritative QR date is currently discarded. | **bug** | L4 `ConfirmManualUITests`: a QR prefill with a date and no OCR date asserts the date field shows the QR date (fixture must differ from today). L1: the resolve/compose path receives the anchor on the production call. EN+RU screenshot. | F5 |

## Adjacent, already filed (do not re-file)

- **`FillUp.fiscalIdentity` has no production writer** – the QR identity is decoded
  and compared by `DuplicateDetector` (`DuplicateDetector.swift:100`) but never
  written on save (`buildFillUp`, `ManualFillUpView.swift:649-658`). Already
  documented as a reasoned exception with the open product-owner decision in
  `SchemaFieldWriterGuardTests.swift:28-32` (filed by RV.196). This is
  SCHEMA.md's FISCAL QR / duplicate-detection promise, not F5's own – noted, not
  re-filed.

## Could not settle

Nothing. Both findings are confirmed by reading the production call path end to
end (`ExtractionAssembler` → `ConfirmPrefill` → `ManualFillUpView.apply` →
`buildFillUp`) against the extractor's `composeQR`, which only tests and the
corpus scorer invoke.

# REVIEW-SCENARIO run: J5 - 2026-09-11

- **Scenario:** `J5` - The RU/KZ receipt (P3) - the fiscal QR as an anchor, never a feature
- **Run id:** REVIEW-SCENARIO-J5-2026-09-11
- **Rows naming it:** 1 closed - `PJ.1` (claims "J5 Scan" only)
- **Adjacent:** J3 (scan), F5 (QR decodes - the normal path)

## Verdict

**NOT IMPLEMENTED** - the QR total anchors and outranks OCR, but the QR **date** the journey promises ("Total and date land exact from the QR") never fills the entry's date field: the mechanism that would carry it (`FuelExtractor.composeQR`) exists and is unit-tested, but the production assembler never passes the anchor to the extractor, so it is dead in production.

## Ticked rows found to be untrue

None. `PJ.1` is true for what it claims. It explicitly closes **"J5 Scan"** only (`docs/TASKS-DONE.md:319`) and that stage is genuinely built. The gap is not a ticked-but-untrue row; it is an **unowned promise**: the J5 **Anchor** and **Confirm** stages name no row at all, and the date half of "Anchor" is written nowhere.

## Promise-to-code map

| Journey promise (J5 / F5) | Status | Citation |
|---|---|---|
| QR decoded as part of the same receipt scan; no mode/chip/mention | MET | `CapturePipeline.swift:64` (`CaptureQRDetector.detectPayload` inside the same `recognize` that runs OCR); zero "QR"/"fiscal" strings in `Localizable.xcstrings` |
| Parse locally what the QR carries (total, date-time, fiscal ids); no networking | MET | `FiscalQR.swift:141` (`FiscalQRParser.parse`, pure/offline); `FiscalQR.swift:24-30` (all six fields parsed) |
| Total lands exact from the QR; outranks OCR; confirms/corrects it | MET | `ManualFillUpView.swift:377-395` (`ConfirmQRTotal.resolve` -> `applyTotal`); `ConfirmPrefill.swift:163-188` (core); `FiscalQR.swift:340-346` (`classify`) |
| **Date lands exact from the QR** | **MISSING** | `ManualFillUpView.swift:402-404` sets `form.date` from `extraction.date` (OCR) only; the QR date reaches only `qrAnchor.date` (`FiscalQR.swift:262`) |
| Litres / price / fuel kind still from OCR and stay editable | MET | `ManualFillUpView.swift:396-401` (form fields from `extraction`, editable); `FiscalQRAnchor` litres/price/fuelKind always nil (`FiscalQR.swift:253-266`) |
| QR total above the fuel line = mixed-receipt signal (hard rule 4) | MET | `ConfirmPrefill.swift:177-187` (`.fuelLineStands`); `MixedReceipt.swift:85-89` (QR signal 1) |
| Never claim "exact" for a field the QR cannot carry | MET | `FiscalQR.swift:248-252` (anchor carries no volume/price/kind); no "exact/verified/anchor" UI copy in `Localizable.xcstrings` |
| F5: no copy names the QR, nothing "failed" | MET | zero QR strings in `Localizable.xcstrings`; `ConfirmEmptyScanCaption` (`ConfirmPrefill.swift:239-254`) treats a QR-authoritative total as "the scan DID read something", never a failure |

## Sequence trace (one RU receipt with a QR)

1. User scans -> `CapturePipeline.process` -> OCR + `VNDetectBarcodesRequest` in one pass (`CapturePipeline.swift:64`). **QR payload and OCR lines both captured.**
2. `ExtractionAssembler.assemble` (`ExtractionAssembler.swift:47-62`) runs `FuelExtractor.extract(lines:source:)` **without** `qrAnchor` (`:54-55`), then parses the anchor **afterwards** (`:56-58`). So `extraction.date` is OCR-only, and `composeQR` (`FuelExtractor.swift:108`, `FuelExtractorTotalFinder.swift:18-31`) never runs. **The QR date stops being carried here.**
3. `ManualFillUpView.apply` (`ManualFillUpView.swift:368-410`): total resolved from QR (`:377-395`) -> `form.total` exact. **Date** resolved from `extraction.date` only (`:402-404`) -> `form.date` is the OCR date, never the QR's `t`.
4. Mixed receipt: `detectMixedReceipt` (`:421-429`) uses `qrAnchor` -> fuel line stands, non-fuel lines offered. **Correct.**
5. Save: `ScannedSavePlanner.plan` (`ScannedSavePlan.swift:124,137`) sets provenance `.fiscalQR` and records the QR-resolved total proposal. The **entry's `date`** is `form.date` (OCR), so the QR date never reaches `FillUp.date`.
6. The QR date survives only as metadata: `Attachment.extractedTimestamp` fallback (`ManualFillUpReceiptSave.swift:237-238`) and the F9a `receiptEvidence` (`:131-132`). The entry itself keeps the OCR date.

**Where the fact stops being carried:** step 2. `qrAnchor.date` exists from step 1 onward and is used as attachment/F9a metadata in steps 5-6, but the one field the journey names it for - the entry's date - is filled from OCR at step 3 and never corrected.

## Proposed rows

| id | Deliverable (one line) | Closes | Consequence today | Severity | Done check | Scenario |
|---|---|---|---|---|---|---|
| *(new)* | Wire the fiscal-QR date into the confirm form: parse the anchor first and pass it to `FuelExtractor.extract(lines:source:qrAnchor:)` in `ExtractionAssembler.assemble` so `composeQR` runs and `extraction.date` outranks OCR (`ExtractionAssembler.swift:54-58`) | J5 Anchor ("date lands exact from the QR"), F5 ("card pre-fills total and date instantly") | A RU/KZ receipt whose OCR date is garbled, absent or wrong-zone keeps the wrong/empty date even though the QR carries the exact timestamp; the total is anchored but the date is not, and the user corrects it by hand. The `FuelExtractor.extract` comment (`FuelExtractor.swift:101-107`) already claims "the scored extraction is the extraction the app actually produces" - which is false in production, and the corpus ratchet (`AccuracyRatchetTests`, `CorpusCompressionTests`) scores a stronger extraction than the app ships | bug | L1: `ExtractionAssembler.assemble` on a QR-bearing fixture yields `extraction.date` equal to the QR's `t` (a garbled-OCR-date fixture so the assertion would fail today); L4 `ConfirmManualUITests`: `-seedConfirmPrefillQR` asserts the date field shows the QR's date, not the OCR date. `-seedConfirmPrefillQR` already carries `qrAnchor.date` (`ConfirmPrefill.swift:153-158`) so the assertion is reachable | J5 |

## Not settled

- Whether `FillUp.fiscalIdentity` (the `fn`+`i`+`fp` identity `SCHEMA.md:583-587` says is stored) is in scope for J5. It is already filed as a dead field under `RV.196` and its writer/duplicate-detection belongs to `P2.4b` (F2), not this journey's anchor promise - so it is left to that row rather than re-filed here.
- Whether the date should "always" outrank OCR or only "override an absent or garbled OCR date". `composeQR`'s code overrides unconditionally (`FuelExtractorTotalFinder.swift:28-30`) while its own comment says "overrides an absent or garbled OCR date". The product intent (J5/F5: "date lands exact from the QR") reads as unconditional-outrank, but a settled reading of that one line should accompany the fix.

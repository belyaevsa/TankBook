# REVIEW-SCENARIO F5 – 2026-09-11b (second walk, after RV.219)

## Verdict

**IMPLEMENTED** – RV.219 closed the one gap the first walk found: the QR date now
lands in production, through the single path. `ExtractionAssembler.assemble`
decodes the anchor first and passes it into `extract`, so `composeQR` runs and
the QR timestamp reaches `extraction.date`, which `ManualFillUpView.apply` writes
into `form.date` and `buildFillUp` saves. No promise in F5 remains unowned.

## Ticked rows found to be untrue

None. RV.219 is ticked and its tick is true: the mutation gate ("drop the anchor
argument and the new L1 goes red") is backed by
`ExtractionAssemblerTests.qrDateOverridesAConfidentlyWrongOcrDate`
(`ExtractionAssemblerTests.swift:77-90`), which asserts `25.11.2024` where the
OCR read `16.11.2024`.

## Promise-to-code map

| F5 text | Verdict | Evidence |
|---|---|---|
| "Parse locally what the QR string itself carries (total, date-time, fiscal IDs)" | **MET** | `FiscalQRParser.parse` decodes `s`/`t`/`fn`/`i`/`fp`/`n` offline (`FiscalQR.swift:141`, fields `:24-31`; no networking `:16-18`). Detection wired: `CaptureQRDetector.detectPayload` from `recognize` (`CapturePipeline.swift:64`). |
| "card pre-fills total … instantly" | **MET** | Anchor decoded first, then composed: `ExtractionAssembler.assemble` parses the QR before `extract` (`ExtractionAssembler.swift:60-64`); `composeQR` sets `result.total` via `ConfirmQRTotal.resolve` (`FuelExtractorTotalFinder.swift:24-33`). `apply` confirms idempotently (`ManualFillUpView.swift:377-396`). |
| "card pre-fills … date instantly" | **MET** (was MISSING) | `composeQR` sets `result.date` from the QR timestamp, overriding an absent/garbled/differing OCR date and leaving an agreeing one (`FuelExtractorTotalFinder.swift:34-42`). `apply` reads `extraction.date` into `form.date` (`ManualFillUpView.swift:403-405`); `buildFillUp` writes it (`ManualFillUpView.swift:652`). |
| "liters/price are the user's, from OCR and editable as always … the anchor never pretends to know the volume" | **MET** | `FiscalQRAnchor.liters/unitPrice/fuelKind` always nil (`FiscalQR.swift:256-258, 268-273`); litres/price come from the extraction and stay editable (`ManualFillUpView.swift:397-398`). |
| "No copy: nothing failed, and the QR is not named" | **MET** | No user-facing QR/fiscal string; PJ.47 removed the failure copy. |
| "The Confirm sheet simply shows the anchored total … as verified" | **MET** | QR-authoritative total applied without `resolvedByExtraction.insert(.total)`, never dimmed (`ManualFillUpView.swift:383-395`). |
| "… and date as verified" | **MET** (was MISSING) | `ManualFillUpMath.Field` has no `.date` case (`ManualFillUpMath.swift:19-23`), so the date is never dimmed; `form.date` now carries the QR date (`ManualFillUpView.swift:403-405`). |
| "Metric: ≥95% anchored total" | **MET** | The total half is supported end to end; the date half is now supported too. The metric itself is a product measurement, not a code promise. |

## Sequence trace (one user, one RU receipt with a decodable QR and a garbled printed date)

1. Scan → `CapturePipeline.recognize` returns OCR lines + `qrPayload` (`CapturePipeline.swift:61-64`).
2. `ExtractionAssembler.assemble` decodes the anchor **first**, passes it into `extract` (`ExtractionAssembler.swift:60-64`), and `composeQR` composes total and date into `extraction` (`FuelExtractor.swift:108`).
3. `ConfirmPrefill` carries both `extraction` (already QR-composed) and `qrAnchor` (`CapturePipeline.swift:43-49`).
4. `apply`: total ← `ConfirmQRTotal.resolve` (QR wins, never dimmed); date ← `extraction.date`, which is now the QR's (`ManualFillUpView.swift:377-405`).
5. Save: `buildFillUp` writes `date: form.date` (`ManualFillUpView.swift:652`); `writeReceiptPhoto` records the attachment `extractedTimestamp` from the same `extraction.date` (`ManualFillUpReceiptSave.swift:237-238`).

**No fact stops being carried.** The first walk's divergence (entry saved with OCR/default date while its
attachment recorded the QR date) is gone: entry and attachment now derive the date from the same
QR-composed `extraction.date`.

## Proposed rows

None.

## Adjacent, already found (do not re-file)

- **`FillUp.fiscalIdentity` has no production writer** – unchanged from the first
  walk; a reasoned exception under `SchemaFieldWriterGuardTests.swift:28-32`
  (RV.196), SCHEMA.md's duplicate-detection promise, not F5's.
- Two nuances RV.219's own DONE note names as "found and not fixed, no row owns
  them": (a) a QR-supplied total can attach an OCR total-label crop on a receipt
  with no matching OCR total (verify-affordance nuance); (b) `qrDateString`
  compares in `.current` while the anchor may carry an injected zone (no
  production impact). Neither is an F5 journey promise; both are already
  surfaced in `docs/TASKS.md` RV.219. Not re-filed.

## Could not settle

Nothing. The path was confirmed end to end by reading the production call chain
(`CapturePipeline.recognize` → `ExtractionAssembler.assemble` → `composeQR` →
`ManualFillUpView.apply` → `buildFillUp` / `writeReceiptPhoto`), and the L1
round-trip (`qrDateString` emits `dd.MM.yyyy`, `ConfirmDate.parse` accepts it,
`ConfirmPrefill.swift:198-219`) is pinned by `ExtractionAssemblerTests.swift:77-105`.

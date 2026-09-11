# REVIEW-SCENARIO run: J5 – 2026-09-11b (second walk, after RV.219)

- **Scenario:** `J5` (`docs/JOURNEYS.md`)
- **Run id:** REVIEW-SCENARIO-J5-2026-09-11b
- **First walk:** `REVIEW-SCENARIO-J5-2026-09-11` (NOT IMPLEMENTED - the QR date never filled the entry's date field)
- **What changed:** `RV.219` (commit 96d05ae2) - `ExtractionAssembler.assemble` now parses the QR anchor first and passes it into `extract`, so `composeQR` runs in production and the QR date lands.

## Verdict

**IMPLEMENTED** - the one MISSING promise the first walk found ("date lands exact from the QR") is now MET by RV.219: the QR timestamp reaches the entry's date field through the same path the total always used, with a production caller and L1 coverage.

## Ticked rows found to be untrue

None. The only closed row naming this scenario (`PJ.1`) remains true for what it claims. RV.219's own tick is accurate and independently verified against the tree (below).

## Promise-to-code map

| Journey promise (J5 / F5) | Status | Citation |
|---|---|---|
| QR decoded as part of the same receipt scan; no mode/chip/mention | MET | `CapturePipeline.swift:64-68` (`CaptureQRDetector.detectPayload` inside the same `recognize` that runs OCR, payload handed to the assembler) |
| Parse locally what the QR carries; no networking | MET | `FiscalQR.swift:141-145` (`FiscalQRParser.parse`, pure/offline) |
| Total lands exact from the QR; outranks OCR | MET | `ExtractionAssembler.swift:60-64` -> `FuelExtractor.swift:108` -> `FuelExtractorTotalFinder.swift:24-43` (composed into the extraction in production) |
| **Date lands exact from the QR** (was MISSING) | **MET** | `FuelExtractorTotalFinder.swift:39-42` (QR date overrides absent/garbled/differing OCR date); `ManualFillUpView.swift:403-405` (form.date from the composed `extraction.date`) |
| Litres / price / fuel kind still from OCR and stay editable | MET | `ManualFillUpView.swift:397-402` (from `extraction`, editable); `FiscalQR.swift:256-265` (anchor litres/price/fuelKind always nil) |
| QR total above the fuel line = mixed-receipt signal (hard rule 4) | MET | `FuelExtractorTotalFinder.swift:26-33` (`.fuelLineStands`); `ConfirmPrefill.swift:172-187` (core) |
| Never claim "exact" for a field the QR cannot carry | MET | `FiscalQR.swift:245-266` (anchor carries no volume/price/kind) |
| F5: no copy names the QR, nothing "failed" | MET | unchanged from first walk; zero QR/fiscal strings in `Localizable.xcstrings` |

## Sequence trace (one RU receipt with a QR) - re-walked

1. Scan -> `CapturePipeline.process` -> `recognize` runs OCR + `VNDetectBarcodesRequest` in one pass and passes the payload to the assembler (`CapturePipeline.swift:64-68`). **QR payload and OCR lines both captured.**
2. `ExtractionAssembler.assemble` now decodes the anchor **first** (`ExtractionAssembler.swift:60-62`) and passes it into `extract(lines:source:qrAnchor:)` (`:63-64`), so `composeQR` runs on the same pass (`FuelExtractor.swift:108`). **The QR total AND date are now composed into the extraction here.** This is the step where the date used to stop carrying.
3. `ManualFillUpView.apply`: total resolved (`:378-396`, a confirm-step guard over the already-composed extraction), date resolved from `extraction.date` (`:403-405`), which now carries the QR's date when the QR is authoritative.
4. Mixed receipt: `detectMixedReceipt` (`:422-429`) uses `qrAnchor` -> fuel line stands, non-fuel lines offered. Correct.
5. Save: `ScannedSavePlanner.plan` records provenance `.fiscalQR` and the QR-resolved total; the entry's `date` is `form.date`, so the QR date reaches `FillUp.date`.
6. The QR date also still survives as attachment/F9a metadata, unchanged.

**Where the fact used to stop:** step 2 - now closed. `qrAnchor.date` and `extraction.date` are the same value from step 2 onward; the confirm form, the entry, and the metadata all carry it. No second writer exists (`ManualFillUpView.swift:377` comment confirms the view's `ConfirmQRTotal.resolve` is a guard, not a writer).

## Proposed rows

None. Every stage and fallback of J5/F5 is MET; the two residual notes below are below the bar of a journey promise.

## Not settled

- **`FillUp.fiscalIdentity`** (`fn`+`i`+`fp`) remains out of J5 scope, as in the first walk: filed under `RV.196`, its writer/duplicate-detection belongs to `P2.4b` (F2), not J5's anchor promise.
- **The "always vs override-only" date question is settled by RV.219's implementation**: `composeQR` overrides an absent, garbled or *differing-day* OCR date and leaves an OCR date naming the QR's own day unchanged (`FuelExtractorTotalFinder.swift:34-42`), and the code comment now matches the code. This satisfies "date lands exact" (the QR's day always wins; only the cosmetic string format is kept when they agree).
- **Two residuals RV.219 itself recorded as "no row owns them"**, both below the journey bar and neither re-filed here: (a) the QR-supplied total can attach an OCR total-label crop on a receipt whose OCR total was nil (tap-to-verify shows the label the value did not come from - a verify-affordance polish nuance); (b) `qrDateString` compares in `.current` while `FiscalQRParser.parse` accepts an injected `timeZone` - no production impact, because the production caller `CapturePipeline.recognize` uses the assembler's `.current` default end to end. Settled by a real capture of a QR-bearing receipt (`receipt-010`): the form rendered the QR date in EN and RU, so the production path is visually confirmed.

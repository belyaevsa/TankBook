# REVIEW-SCENARIO run: J10 · Cross-border trip – 2026-09-12 (first walk)

**Run id:** REVIEW-SCENARIO-J10-2026-09-12
**Scenario:** J10 (`docs/JOURNEYS.md:488`)
**Verdict:** IMPLEMENTED

## Ticked rows found to be untrue

None. RV.140 (originating-device re-home), RV.143 (sync-arrival re-home), RV.144 (edit re-home) and RV.136 (Vehicle field-merge) were each walked to code, not to the tick. RV.143's guard is not vacuous: `SyncVehicleCurrencyRehomeTests` covers all three apply arms (`.remote`, `.fieldMerge`, conflict) and the idempotence case, and its snapshotted-row assertion is the discriminating one (see map below).

## Promise-to-code map

| # | Promise (JOURNEYS.md:490) | Verdict | Evidence |
|---|---|---|---|
| 1 | "scan as always" – capture is the entry path | MET | `CapturePipeline.process` (`ios/App/Sources/Capture/CapturePipeline.swift:25`) → `ExtractionAssembler.assemble` (`ios/Sources/TankbookCore/Extraction/ExtractionAssembler.swift:47-64`) → `FuelExtractor.extract`. An all-nil extraction renders as the ordinary empty manual form, never an error (`CapturePipeline.swift:21-23`, hard rule 15). |
| 2 | "currency auto-detected as PLN from the receipt" | MET | `CurrencyDetection.detect` carries `("PLN","PLN")`, `("ZŁ","PLN")` in the explicit-marker tier (`ios/Sources/TankbookCore/Extraction/CurrencyDetection.swift:49`), matched case-folded so lowercase `zł` resolves. `FuelExtractor` assigns `result.currency` from it (`FuelExtractor.swift:26`). The detected currency is applied to the form: `form.currency = extraction.currency ?? vehicle.homeCurrency` (`ios/App/Sources/ConfirmManual/ManualFillUpView.swift:400`). |
| 3 | "card shows both" – original and converted | MET | Original total renders under the entry currency's own symbol: `figureRow(... unit: currencySymbol)` (`ios/App/Sources/ConfirmManual/ManualFillUpSections.swift:176`), symbol `zł` for PLN (`ios/App/Sources/AddVehicle/AddVehicleForm.swift:155`). Converted home figure renders in the `ForeignCurrencyCard`: `"≈ X €"` (`ios/App/Sources/ConfirmManual/CurrencyConversionCard.swift:85-103`). |
| 4 | "converted at the entry-date rate … never today" | MET | `Money.converted(using:)` takes `rateDate` from the snapshot and is fill-blanks-only (`ios/Sources/TankbookCore/Domain/Money.swift:128-138`). The snapshot is looked up `on: date` (the form's entry date) in `conversionState` (`ios/App/Sources/ConfirmManual/ManualFillUpCurrencySupport.swift:385-388`). `MoneyBackfillService.convertLog` converts "at that entry's OWN date – never today" (`ios/Sources/TankbookCore/Rates/MoneyBackfillService.swift:255-269`). |
| 5 | "saved with the historical rate snapshot" | MET | `Money` stores `amount`/`currency` (original) plus `homeAmount`/`homeCurrency`/`rate`/`rateDate`/`rateSource` (`Money.swift:92-99`). Save routes through `convertForSave` → `converted(using:)` / `applyingManualRate` (`ManualFillUpCurrencySupport.swift:419-429`). |
| 6 | "trends stay in the car's home currency" | MET | Home is home-denominated: "every money figure on this screen is home-denominated – a foreign fill is converted by its own immutable rate snapshot" (`ios/App/Sources/Home/HomeSections.swift:253-263`). Trends: "the tile's figure is the converted-home value (RV.29)" (`ios/App/Sources/Trends/TrendsView.swift:160-170`); the spend tile carries the figure's own currency, never a cross-currency sum (`TrendsView.swift:175-182`). |
| 7 | "original always preserved on the entry" | MET | The receipt pair (`amount` + `currency`) is never mutated by any conversion: `converted`/`rehomed`/`applyingManualRate` all only write the derived half (`Money.swift:128-198`). Exported: the ORIGINAL currency is present in CSV export (`ios/Tests/TankbookCoreTests/CarCSVExportTests.swift:200`). |
| 8 | "No settings visited at any point" / "zero manual currency picks" | MET | Detection is automatic (map #2); the confirm card offers an in-place manual-rate row as the next step, never a settings hop (`CurrencyConversionCard.swift:190-208`); the F9 "Check for rates" door is on Home, not settings. No step in the sequence opens a settings screen. |
| 9 | Manual door – typing is a peer path | MET | "Type it" is the sibling button to scan (`ios/App/Sources/Home/HomeSections.swift:212`, `HomeView.swift:427`). The typed path is `ManualFillUpView` with nil prefill; a foreign currency is picked from the chip row, whose offer always contains the code (`CurrencyOfferBuilder.defaultCurrencies` includes PLN, `ios/Sources/TankbookCore/Catalog/CurrencyOffer.swift:24-26`). |
| 10 | Sync, originating device (currency typed) | MET | RV.140: `VehicleDetailView.commit` runs `MoneyBackfillService.rehome` when the home currency changed (`ios/App/Sources/VehicleDetail/VehicleDetailView.swift:395-404`). |
| 11 | Sync, receiving device (currency arrives) | MET | RV.143: `SyncEngine.homeCurrencyRehomer` seam (`ios/Sources/TankbookCore/Sync/SyncEngine.swift:98, 120, 133`); `arrivingHomeCurrency` compares decoded content (never payload bytes) and only for a live Vehicle (`SyncEngine.swift:357-372`); `rehomeAfterCurrencyChange` invokes the SAME `HomeCurrencyRehomer` pass in all three apply arms – `.remote` (`:302, 311`), `.fieldMerge` (`:343, 347`), and conflict resolution (`:589, 600`). The seam (`ios/Sources/TankbookCore/Rates/HomeCurrencyRehomer.swift:11-15`) has `MoneyBackfillService` as its one conformer (`MoneyBackfillService.swift:384`); `rehome` is idempotent and never rewrites a snapshotted pair (`MoneyBackfillService.swift:237-253`). |

Fallbacks in the journey text: none beyond the single sentence (there is no stage table for J10). The F9 rate-pending branch is the only off-happy-path state and is documented as its own journey, not promised by J10.

## Sequence trace – one user, one foreign fill-up

1. User fills up in Poland, scans the receipt. `CapturePipeline.process` (`CapturePipeline.swift:25`) runs Vision OCR + QR and `ExtractionAssembler.assemble` (`ExtractionAssembler.swift:47-64`), producing a `FuelExtraction` whose `currency` is the detected code.
2. The Confirm sheet opens (`ManualFillUpView`). `apply(_:vehicle:)` sets `form.currency = extraction.currency ?? vehicle.homeCurrency` (`ManualFillUpView.swift:400`); the on-device-resolved boundary records `.currency` as resolved (`ManualFillUpView+Prefill.swift:43`), so a later gateway answer cannot refill it (`ManualFillUpView.swift:486-512`, RV.57 boundary).
3. The total field shows the original amount under the entry currency's symbol (`ManualFillUpSections.swift:176`); the `ForeignCurrencyCard` shows the converted home figure with rate + source + date (`CurrencyConversionCard.swift:85-165`). The card and the save share `conversionState`, so the displayed figure is "the exact same decision, never a separately-rounded figure" (`ManualFillUpCurrencySupport.swift:394-412`).
4. Save routes through `convertForSave` (`ManualFillUpCurrencySupport.swift:419-429`) → `Money.converted(using:)` at the entry's own date (`Money.swift:128-138`). The stored row carries the original pair and the immutable snapshot.
5. Home and Trends recompute from `homeAmount` in the car's home currency (`HomeSections.swift:253-263`, `TrendsView.swift:160-182`); the original pair survives untouched for edit and export.
6. A later home-currency change re-homes pending entries on the typing device (RV.140, `VehicleDetailView.swift:395-404`) and, when the new currency arrives on a second device, re-homes there through the same pass (RV.143, `SyncEngine.swift:302/343/589` → `rehomeAfterCurrencyChange` → `HomeCurrencyRehomer.rehome`).

No fact stops being carried between steps: the currency detected at step 1 is the currency saved at step 4 and the currency the snapshot preserves at step 5.

## Proposed rows

None.

## Unsettled / boundary observations

- **The "converted" card is conditional on a rate existing for the entry date.** The journey's happy path assumes the rate is present; when the cache/feed cannot serve the entry's date, the card renders "≈ –" and the entry saves rate-pending (F9, `CurrencyConversionCard.swift:18-21`, `MoneyBackfillService`). This is F9's documented miss, not a J10 promise breach – the sequence still holds and the original is still exact. No row proposed.
- **Currency detection for Polish receipts depends on a readable `PLN`/`zł` marker.** A Polish fiscal receipt whose marker OCR cannot read returns `nil` and falls back to the car's home currency (with the low-confidence "Which currency is this?" prompt). That is parser-accuracy territory governed by the corpus gate (`docs/EXTRACTION.md`), not a J10 gap. No row proposed; it is cited here so it is not mistaken for a J10 finding.

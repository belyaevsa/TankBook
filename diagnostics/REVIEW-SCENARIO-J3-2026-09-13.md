# REVIEW-SCENARIO run: J3 · The 5-second fill-up (receipt) - 2026-09-13 (fourth walk, after RV.272)

**Run id:** REVIEW-SCENARIO-J3-2026-09-13 · **Walked by:** the orchestrator (product owner, 2026-09-12: walks are not dispatched) · **Tree:** `156cf565`

## Verdict

**IMPLEMENTED.** The third walk (`REVIEW-SCENARIO-J3-2026-09-12c.md`) found every promise MET; the
status line was cleared on 2026-09-13 when `RV.272` surfaced while gating `RV.271`: on an imperial
car a scanned receipt's litres were pre-filled as-is under a *Gallons* label and saved as ~3.8× the
real volume - a confident-wrong pre-fill on the Confirm stage, the F2 shape inside J3. `RV.272` is
shipped; the Confirm stage is re-walked below. Nothing else in the journey text changed.

## Ticked rows found to be untrue

None. `RV.272` walked to code: every pre-fill of a volume or a unit price goes through ONE
function, `ManualFillUpFormState.applyPrefilledVolumes(liters:unitPrice:volumeUnit:)`
(`ManualFillUpFormState.swift:162-170`), which converts litres with `ManualFillUpMath.displayVolume`
and the per-litre price with the inverse `displayUnitPrice`; its callers are the scan pre-fill
(`ManualFillUpView.swift:398`), the gateway answer (`:498,503`) and the attach path
(`ReceiptAttachSupport.swift:179`). The orchestrator's mutation (litres written unconverted) went
red on the pre-fill AND the save-back L1s. `RV.273`: the six stored-volume readers render converted
(`VolumeDisplay.text`); walked in its tick.

## Promise-to-code map (the Confirm stage; the rest stands from the third walk)

| Promise (J3) | Status | Evidence |
|---|---|---|
| the pre-fill is a default input in the car's own units, editable at the moment it is offered (hard rule 13) | MET | `applyPrefilledVolumes` converts at the boundary; frame `RV.272-confirm-imperial-scan` (opened): a 40 L receipt reads *10.57 гал* under *Галлоны*, *5.678 €* under *Цена / гал*, cross-check verified |
| the saved entry is what the receipt said, whatever the car's display unit | MET | `testAPrefilledImperialFormSavesTheExtractionsLitres` - the form's display figure saves back as 40 L; `derived(volumeUnit:)` keeps the math in litres |
| the cross-check locks on the pre-filled triple (litres × price = total) | MET | the price crosses through the inverse converter so *10.57 gal × 5.678 €/gal = 60.00 €* still verifies (`mathFields` / `derivedDisplay` made coherent; L1 `testExtractionPricePrefillsPerDisplayUnit`) |
| a metric car is unchanged | MET | `testMetricPrefillIsUnchanged` |
| the fiscal QR anchor (J5) is not a second volume writer | MET | the anchor writes only the total (`ExtractionAssembler`), stated in RV.272's tick |

## Sequence trace (an imperial car, a 40 L receipt scanned)

1. Capture → extraction: `liters = 40`, `unitPrice = 1.50 €/L`, `total = 60` (litres by contract,
   `SCHEMA.md` → `GatewayExtraction.volume`).
2. Confirm opens; `applyPrefilledVolumes` writes *10.57* gal and *5.678* €/gal; the labels read
   *Gallons* / *Price / gal* (RV.234); the cross-check line verifies.
3. The user edits nothing (or corrects a field - both stay in gallons); Save.
4. `derived(volumeUnit:)` converts back: `FillUp.volumeL = 40`, price per litre 1.50.
5. Home's log row renders *10.6 gal* through `VolumeDisplay.text` (RV.273); Trends' *Price / gal*
   through the same converter (RV.234).

The receipt's litres are the fact carried end to end: converted for the eye at 2 and 5, stored as
read at 4.

## Proposed rows

None. `RV.274` (two per-litre prices under a *Price/gal* label on the recognised page and the
inbox) is open under J3b, in flight, and touches readers after the save - not J3's promise.

## Not settled

- The price converter's rounding: *5.678* €/gal is the display of 1.50 €/L × 3.785; a user who
  retypes the displayed figure saves 1.4999 €/L. Three decimals is the form's existing precision
  for a per-litre price; a fourth is not worth a row.

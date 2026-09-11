# REVIEW-SCENARIO F2 – 2026-09-11

## Verdict

**NOT IMPLEMENTED** – F2's primary defence is fully built and shipped: the
cross-check refuses to lock, the amber underline + copy surface, and the source
crop opens on tap. The gap is in **"The residue"**, the one stage that guards the
case F2 calls "the most dangerous failure": of its two named mitigations, the
odometer delta is done (PJ.14) but the **"consumption outlier check on save"
does not exist** – no row, no code, no doc. When all three numbers are wrong
*consistently*, the cross-check passes falsely, the entry saves, and nothing
flags the absurd consumption.

## Ticked rows found to be untrue

None. The only row naming F2, **PJ.1** (its first cell carries "F2 real crops"),
delivers exactly what it claims: the crops are real, derived from the OCR
bounding box per resolved field (`ExtractionAssembler.cropRects`
`ExtractionAssembler.swift:73-87`), converted to pixel space against the source
image (`CapturePipeline.cropEvidence` `CapturePipeline.swift:78-96`). The
hardcoded `CGRect(x: 250, …)` at `ConfirmPrefill.swift:275-284` is a `#if DEBUG`
seed, not the production path.

The gap below is a promise with **no row at all** – the PJ.23 shape. Note also
that F2's detection/surfacing/odometer stages were built under rows that named
other scenarios (P1.3, P2.1, P2.3, PJ.14), so the scenario index's "1 row" for F2
understates what exists and hides that the residue mitigation was never filed.

## Promise-to-code map

| F2 text | Verdict | Evidence |
|---|---|---|
| "The cross-check line refuses to lock: liters × price ≠ total" | **MET** | `ManualFillUpMath.crossChecked` → `TimelineValidator.crossCheck` returns `.verified` or `.mismatch(field: .total)` (`ManualFillUpMath.swift:118-126`, `TimelineValidator.swift:138-145`). The confirm sheet's `checkLine` renders the amber branch on `.mismatch` and only draws the lock on `.verified` (`ManualFillUpSections.swift:266-319`). |
| "The arithmetic check is the safety net – this is why it exists" | **MET** | Tolerance is one shared constant `ConfirmConfidenceGate.crossCheckTolerance` (`Extraction/ConfirmPrefill.swift:43-45`), so validator and sheet cannot disagree; four-outcome version `ExtractionCrossCheck.evaluate` (`CrossCheck.swift:42-101`). |
| "Mismatched field gets a warn amber underline + 'these don't multiply up – check the amber field'" | **MET** | Copy + warn rule at `ManualFillUpSections.swift:268-277`; `isSuspect` maps the `.mismatch` suspect to a field and feeds `fieldUnderline(warn:)` (`ManualFillUpSections.swift:354-362`, applied `:219`). L4 asserts the string: `ConfirmManualUITests.swift:127`. |
| "Never auto-'fix' by recomputing one field silently; the app doesn't know which one is wrong" | **MET** | With all three typed, `ManualFillUpMath.derive` returns `crossChecked` without modifying any field (`ManualFillUpMath.swift:64-70, 118-126`); the confirm sheet's mismatch branch renders the warn and writes nothing back (`ManualFillUpSections.swift:266-277`). The third value only derives when exactly two are typed, never to "fix" a triple. The suspect is always `.total` (the field the trigger case most often gets wrong), which is the honest consequence of "the app doesn't know which one". |
| "User taps the amber field, sees a crop of the receipt region it was read from, corrects it" | **MET** (affordance deviation) | The magnifier button beside a cropped field opens `VerifyCropSheet` (`ManualFillUpSections.swift:244-256`, `ManualFillUpView.swift:190,230-232`). The crop is real, per-field, from the OCR line the value came from (`ExtractionAssembler.swift:73-87`). Deviation: the tap target is a small magnifier beside the field, not "the field" itself, and it appears for any cropped field, not specifically the amber one. Functionally the recovery is reachable. |
| Residue: "odometer delta ('+3,407 km since last?' flags the absurd)" | **MET** | Live `OdometerDelta.evaluate` caption with warn states on backwards and pace (`ManualFillUpSections.swift:399-434`); the same timeline is enforced on save by `TimelineValidator` CHECK 1/2 (`TimelineValidator.swift:106-131`, `ManualFillUpView.buildFillUp:659-661`). |
| Residue: "consumption outlier check on save" | **MISSING** | No such check. Save runs only `TimelineValidator.validate` (order/pace/cross-check – `TimelineValidator.swift:106-131`, `ManualFillUpView.swift:659-661`). No consumption (L/100km) computation is consulted on save anywhere in `ConfirmManual` or `EditEntry`. The closest thing, `AnomalyEngine` (J9), is a 90-day drift requiring a full prior year (`AnomalyEngine.swift:120-250`) and is a Home-time trend card, not an on-save outlier flag. |

## Sequence trace (one user, one scan that misreads all three numbers)

1. Scan → `CapturePipeline.process` → `ConfirmPrefill` with the wrong extraction (`CapturePipeline.swift:25-50`).
2. `ManualFillUpView.apply` pre-fills total/liters/price, dimmed, all editable (`ManualFillUpView.swift:368-410`).
3. The numbers card derives the cross-check live from the three values (`ManualFillUpMath.derive`): a single misread digit → `.mismatch` → amber line, lock withheld (`ManualFillUpSections.swift:266-319`).
4. The suspect (total) underlines amber; copy names the next step (`ManualFillUpSections.swift:354-362`).
5. Tap the magnifier → `VerifyCropSheet` shows the source crop → user corrects → the cross-check re-derives live and locks (`ManualFillUpSections.swift:138, 278-319`).
6. Save: `buildFillUp` writes `crossCheck: derived.crossCheck` and `conflict` from `TimelineValidator` (`ManualFillUpView.swift:649-662`); the entry always saves (save is gated on two fields, never on a verified cross-check – `ManualFillUpView.swift:533-536, 683`).

**The case F2 names, end to end:** all three numbers wrong *consistently*
(e.g. liters and price both shifted so the product still matches the shifted
total). Step 3's cross-check fires `.verified` and locks – a **false pass**. The
only remaining guard is the odometer delta caption (step 4's field), which is a
different number and may not move. The entry saves with `crossCheck = .verified`
and no flag. **The fact that stops being carried:** the consumption the entry
implies – which a consistent misread corrupts by the same factor the swapped-pair
table in `SCHEMA.md:920-924` warns about – is never computed against the previous
fill and never flagged.

Secondary, non-blocking observation: a saved `.mismatch` is persisted
(`crossCheck` column `Migrations.swift:257`, CSV `CarCSVExport.swift:160`, sync
`SyncedEntities.swift:104`) but the Home/Log badge reads only the TimelineValidator
conflict (`LogStream.swift:593` `isConflicted = entry.conflict != .none`). The
mismatch is re-surfaced only when the entry is reopened in Edit (cross-check
re-derives, `EditEntryFormState.swift:76`). The journey's own text does not
promise a passive post-save badge, so this is not a F2 gap, but it is the reason
a cross-check the user ignores becomes silent after the sheet closes.

## Proposed rows

| Row | Deliverable | Closes | Consequence today | Severity | Check | Scenario |
|---|---|---|---|---|---|---|
| **F2.1** | On save, compute the consumption the new fill-up implies against the previous fill-up (the same `ConsumptionEngine` the Trends/Home figures use) and, when it lands absurdly outside a conservative band, show a non-blocking `warn` with a next step ("check liters / check odometer"). Never veto the save – `SCHEMA.md:947-950` already rules that an outlier must still save, so this is a flag, not a gate (hard rule 13). | F2 "The residue" – "consumption outlier check on save" | When OCR misreads all three numbers consistently, the cross-check passes falsely and the entry saves silent, corrupting the consumption figure around it (the exact case F2 calls "the most dangerous failure"). | **gap** | L1: a validator/engine function returns a flag for an absurd implied segment and nil for a plausible one, over the golden D1–D4 vectors; mutation drops the check and the flag case goes green-while-empty. L4 `ConfirmManualUITests`: a seeded prefill whose three values are consistently shifted renders the on-save warn and still saves. | F2 |

## Could not settle

Nothing. The primary finding is confirmed by reading the production save path
(`ManualFillUpView.save` / `buildFillUp` → `TimelineValidator.validate`) against
every consumption-related type in the tree (`ConsumptionEngine`, `AnomalyEngine`,
`HomeStats`, `EditConsumptionDelta`) – none is consulted at save time. A
conservative-band threshold for "absurd consumption" would need the corpus to
pick, which is product-owner work, not something this read-only review can
resolve.

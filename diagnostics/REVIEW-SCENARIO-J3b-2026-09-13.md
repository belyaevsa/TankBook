# REVIEW-SCENARIO run: J3b · Type it (the peer path, every locale) - 2026-09-13 (first walk)

**Run id:** REVIEW-SCENARIO-J3b-2026-09-13 · **Walked by:** the orchestrator (product owner, 2026-09-12: walks are not dispatched) · **Tree:** `d0a452e3`

## Verdict

**IMPLEMENTED.** Every v1 row naming J3b is closed - `RV.134`, `RV.234`, `RV.271`, `RV.273`,
`RV.274` (the unit-in-sentence seam, four passes) and the door rows before them (`RV.5`, `RV.12`,
`PJ.6`, `PJ.100`). `PJ.48` (attach a receipt to a typed entry) is `[v1.1]` by the journey's own
text and N/A for v1. Every stage walks to code below.

## Ticked rows found to be untrue

None. The four unit rows were each gated with the orchestrator's own mutation (labels, values,
pre-fill boundary, prices) and their imperial frames opened; `PJ.100` (the guest Type-it menu)
was walked for J1.

## Promise-to-code map

| Promise (J3b) | Status | Evidence |
|---|---|---|
| Reach it: *Type it* next to capture on Home, both empty states, the guest layout, inside Capture and on the capture review step - never behind a failed scan | MET | `HomeTypeItControl` is one shared view rendered by the signed-in and guest Home (`HomeControls.swift:60,81`, `PJ.100`); the no-car layout (`HomeEmptyStates.swift:25,88`); Capture's overlay (`CaptureView.swift:573,598`, id `captureTypeItButton`); the review step's *Type it* beside *Re-take* at equal weight (`CaptureReviewView.swift:107-112`, `testTypeItIsAPeerOnTheReviewStep`); `testBothDoorsSideBySideFromHome`, `testTypeItStillOpensFillUpInOneTap` |
| inside Capture, *Type it* opens the form for the selected mode (PJ.6) | MET | `typeItAfterReview` → `mode.manualEntryForm` (`CaptureView.swift:354-361`); `testTypeItInFillUpModeOpensTheFillUpForm`, `…InServiceMode…`, `…InExpenseMode…`, `testDeniedPermissionTypeItOpensTheFormForTheSelectedMode` |
| Fill: types total and litres, price derives, odometer pre-filled from last known - the same `ConfirmManual` sheet the capture paths land in | MET | `ManualFillUpFormState.derived(volumeUnit:)` (`:136`) derives the third value; the sheet is `ManualFillUpView` for both doors (`activeSheet = .manualForm`); the volume row, hint and price label read the car's unit (`ManualFillUpUnitCopy`, `RV.234`) - frames `RV.234-confirm-imperial` EN + RU opened |
| every locale: units in the sentence, never composed | MET | `RV234UnitCopyTests` (per sentence, metric and imperial, EN and RU); `ManualFillUpUnitCopy` full phrases; 897 keys, 100% RU |
| Save: the cross-check locks as for a scan; typed inside capture, Save leaves the capture modal (RV.12) | MET | `CaptureView.swift:70,365`, `ManualFillUpView.swift:101,627`; `testSavingFromTheTypeItDoorLeavesCapture` |
| a typed entry is a peer everywhere it is read - Home, Trends, the inbox, the recognised page, Recently deleted - in the car's unit | MET | `VolumeDisplay.text` and `displayUnitPrice` at every reader (`RV.271`, `RV.273`, `RV.274`); imperial frames of Home, the inbox and the pace limit opened |
| Later: attach the receipt to a typed entry (PJ.48) | N/A | `[v1.1]` in the journey text |
| Success metric: one tap from Home in every state; median save under 20 s; no growth in abandoned captures | N/A / MET | one tap is pinned by the Home tests above; the timings are metrics |

## Sequence trace (an imperial car, typed at a dark forecourt)

1. Home → *Type it* (one tap; the menu's fill-up item on the signed-in and guest Home alike).
2. `ManualFillUpView` opens with the odometer pre-filled from last known, the volume row
   labelled *Gallons*, the price *Price / gal*, the hint *Enter total and gallons to save*.
3. The user types 60.00 and 10.57; the price derives as 5.678 €/gal; the cross-check line
   verifies.
4. Save: `derived(volumeUnit:)` stores 40 L and 1.50 €/L - the receipt's truth, whatever the
   display unit.
5. Home's log reads *10.6 gal · 5.3 MPG*; Trends' *Price / gal*; a later inbox comparison shows
   both columns in gallons.

The car's units are the fact carried end to end: chosen once on the car, applied at every
boundary, never baked into a sentence.

## Proposed rows

None.

## Not settled

- `RV.272`'s tick notes the price converter's rounding (a retyped *5.678* €/gal saves 1.4999
  €/L); three decimals is the form's existing per-litre precision. Not a row.

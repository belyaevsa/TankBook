# REVIEW-SCENARIO: F9a · second walk

- **Run:** REVIEW-SCENARIO-F9a-2026-09-11c
- **Scenario:** `F9a` (`docs/JOURNEYS.md:661`)
- **Previous run:** `REVIEW-SCENARIO-F9a-2026-09-11b` (NOT IMPLEMENTED on RV.230 + "move entry")
- **Verdict: IMPLEMENTED**

## Ticked rows found to be untrue

None. `RV.230` and `RV.231` are both `[x]` and true as walked. `RV.235` is OPEN (polish, filed by the RV.230 agent) - it is not a ticked row, so it cannot be "ticked but untrue".

## Promise-to-code map (re-check of the first walk's PARTIAL rows and "not settled" items)

| Journey promise | Status | Evidence |
|---|---|---|
| Discrepancy shown inline for a non-fill EDIT (was PARTIAL: no warn at all) | **MET** | `EditEntryNonFillView` renders the shared warn via `odometerCard` → `F9aWarningRow` (`ios/App/Sources/EditEntry/EditEntryNonFillView+Odometer.swift:17-40`); the warn is derived from the form exactly as the save stamps it (`EditEntryNonFillConflict.swift:17-31`); passed down from the parent (`EditEntryView.swift:217-241`, `EditEntryView+Neighbourhood.swift:53-72`); the save stamps `.flagged` (`EditEntryView+NonFillSave.swift:44-51`) |
| Non-fill single odometer fix, all three kinds (was "charge outside RV.230's text") | **MET** | `F9aFixPresentation.fixes` returns `[.fixOdometer]` for `.service`, `.expense` AND `.charge` (`ios/Sources/TankbookCore/Validation/F9aFixPresentation.swift`); `presentationKind` maps charge to `.charge` (`EditEntryNonFillConflict.swift:45-51`); L1 pins all three (`RV230NonFillConflictTests.swift`) |
| Neighbourhood chart behind the non-fill warn | **MET** | `EditEntryNonFillConflict.swift:35-41` → `TimelineNeighbourhood.derive`; rendered as `TimelineNeighbourhoodCard` (`EditEntryNonFillView.swift`) |
| Ranked suggestions "fix odometer · fix date · keep as is" (was PARTIAL: "move entry" absent) | **MET** | `RV.231` struck *move entry*, now *keep as is* (`docs/JOURNEYS.md:665`). fix odometer + fix date render via `F9aFixRow` (`ios/App/Sources/ConfirmManual/F9aFixRow.swift:60-77`); "keep as is" = the never-blocked Save (`EditEntryView.swift:291-295`, `saveEnabled` returns `true` for non-fill). See note below on the accept door |
| Accept with a reason, persisted, synced, undoable | **MET** | `Repository+FlagAcceptance.swift:21-50` (`acceptFlag` clears flag + stores `FlagAcceptance` with reason, rides the payload; `undoFlagAcceptance` re-derives); accept-with-reason surface `FlaggedEntriesView.swift:97-103, 221-231`; record shown + reversible on Edit entry `EditEntryView+Acceptance.swift:21-51` |
| Service conflict quote uses the vehicle's own unit (first walk "not settled" #1: hardcoded km) | **MET (fixed in RV.230)** | `ServiceEntryFormState.odometerConflict` now delegates to the shared builder `OdometerConflict.from(…distanceUnit:)` (`ServiceEntryFormState.swift:259-269`), which calls `OdometerConflict.quote` switching km/mi (`ManualFillUpFormState.swift:273-282`). The hardcoded-km branch the first walk flagged is gone |

## Sequence trace (the one that failed the first walk)

One user, one thing: editing a service odometer into a value that contradicts its date.

1. Open the service in Edit entry → `EditEntryNonFillView` renders the odometer card with the shared amber warn row and single Fix (`EditEntryNonFillView+Odometer.swift:17-40`).
2. Save → `writeNonFill` stamps `.flagged` (`EditEntryView+NonFillSave.swift:44-51`); Save is never blocked (`EditEntryView.swift:291-295`).
3. Home reloads; the row carries the amber badge (`HomeSections.swift` conflict badge).
4. Tap the badge → `Route.editEntry` → the non-fill edit renders the warn + Fix again, because the conflict is derived from the form the same way the save stamps it.
5. Fix odometer focuses the field; or "keep as is" = save anyway; or accept with a reason from Settings → Needs a look (`FlaggedEntriesView.swift:97-103`).

The fact that stopped being carried at the first walk (the flag stamped at step 2 never surfaced at step 4) is now carried end to end. No fact is dropped between the badge and the form.

## RV.235 - does it block?

No. `RV.235` (`[ ]`, polish, filed by the RV.230 agent): on the long service form the F9a *Fix* chip renders under the pinned save bar at rest (`EditEntryView.swift:241` `safeAreaInset { saveBar }`, bar at `:446-482`). The form scrolls and the chip is reachable, and the warn row itself (amber + quote sentence) is visible; only the affordance sits half-hidden at the moment it first appears. It is filed, it is polish, and it does not strand a user - so it does not block IMPLEMENTED. It pairs with `RV.227` (same fix, two screens).

## Proposed rows

| Finding | Deliverable | Journey stage | Consequence today | Severity | Check | Scenario |
|---|---|---|---|---|---|---|
| The "keep as is" clause names the wrong door for the accept | `docs/JOURNEYS.md:665` says "on Edit entry the flag can be **accepted** with a reason"; the accept-with-reason ACTION lives in Settings → Needs a look (`FlaggedEntriesView.swift:97-103, 221-231`), while Edit entry only shows the RECORD of an acceptance already made (banner + Undo, `EditEntryView+Acceptance.swift:21-51`). One-line doc fix: name Needs a look as the accept door and Edit entry as where the record is shown/undone | "keep as is" (third ranked suggestion) | None today - the substance (accept with reason, persisted, synced, undoable) exists and is reachable, and "keep as is" = "save anyway" IS on Edit entry; a user reading the spec only is mildly misdirected | **polish** | doc-only; make the journey sentence and `ERRORS.md` agree on the door (no L1/L4) | F9a |

## Not settled

None. Both first-walk "not settled" items are resolved: the km/mi hardcode is fixed by RV.230's shared builder, and the charge is now an explicit third non-fill kind in `F9aFixPresentation` and the tests rather than an invisible flag.

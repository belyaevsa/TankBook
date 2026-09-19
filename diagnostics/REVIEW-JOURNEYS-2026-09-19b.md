# REVIEW-JOURNEYS run, 2026-09-19 (second walk) - Groups A, B, C, D (the rows since the morning walk)

**Walked by:** the orchestrator · **Tree:** `942406b1` · **Since:** the 2026-09-19 walk (`787cda7a`); **7 rows** in six commits - `RV.296` + `RV.297` (a MPG / km/L car reads its own unit), `RV.298` (the expense reminder's scan door), `PR.37` (cut: the sender existed), `PJ.44` (the parse deleted on every wizard exit), `PJ.40` (the real S5 card), `RV.300` (the flaky-under-load tests). Triggered early - below the 10-row floor - because `PJ.40` fired two of the four event shapes at once: a reader of a NEW entity (`vehicleReturn`) and copy naming a destination ("stays archived", "Delete again").

## 1. Re-check of what the previous run left open

| Item | Then | Now |
|---|---|---|
| `RV.296` (a MPG car prints L-based figures) | owner's priority call | **closed** - `ConsumptionDisplay` in core; every `per100` render site in the app converts (grep: `HomeMonthGlance:43`, `HomeSections:474`, `ManualFillUpFormState:429`, `AfterSaveInsightMessage`, `AnomalyInsightCard`, `TrendsView`); no residual `L/100` literal outside the catalog and the seeds |
| `PR.37` (the nudge sender) | filed at ship | **cut, verified** - `SyncService.cs:185` calls `NudgeSiblingsAsync` after a push; `NudgeRepository.cs:41` reads `devices.push_token`. PR.20's token is read by production code |
| J8 without a status line (`RV.118`-`RV.120`, now `RV.296`/`RV.297`) | scenario review due | unchanged - still owed once the owner ranks nothing else for J8 |
| J4 (`RV.114`, `RV.179`, `RV.288`-`RV.290`), J8b/J13 (`RV.181`), `PJ.300` | open | unchanged |

## 2. Ticked rows whose behaviour the code does not have

**None.** All 7 re-checked by grep against the shipped seams: `ConsumptionDisplay.value(per100:unit:)` at the sites above; `CaptureView(initialMode: .expense …)` presented from `ReminderCompleteSheet`'s `.fullScreenCover` with `initialMode` honoured only when `offeredModes` contains it (`CaptureView.swift:228`); `ImportWizardView.onDisappear` → `cancelImport()` guarded on `!didConfirm && !parseFiles.isEmpty`; `vehicleReturn` (migration v11) written inside `resurrectArchivedIfTombstoned`, read by `VehicleReturnNotices.items` from `HomeView.load` and `GarageView.load`; `PostgresFixture.ClearIssuedPools` and the named `waitCeiling`.

## 3. The four event shapes over the 7 rows

| Shape | Rows it applies to | Finding |
|---|---|---|
| 1 · a screen or route ships | `RV.298` (the Capture screen over the completion sheet, Expense mode), `PJ.40` (a card on two tab roots, not a screen) | `RV.298`'s two edges are in `SCREENMAP.md` (`ReminderComplete -->|Scan receipt| Capture`, `-->|Type amount| ExpenseEntry`). **`PJ.40`'s card was in neither the Home nor the Garage inventory row - fixed in this walk** (both rows name it, with the Garage's copy pointed at Home's). Nothing new under `#if DEBUG` but the seed and the DELETE-count marker |
| 2 · a reader of an entity ships | `PJ.40` reads `vehicleReturn` - its ONLY writer is the sync resurrect, and a user reaches it for real (delete a car on device A, log to it on device B while offline, sync both); the seed goes through the same function rather than inserting a row. `RV.296` reads `Vehicle.units.consumption` (Add car / Vehicle detail write it, editable again - hard rule 13). `PR.37`'s cut confirms `devices.push_token` has its reader | No entity without a creator. The `vehicleReturn` row is device-local and NOT in `syncedTables` - deliberate, written in `SCHEMA.md` |
| 3 · copy naming a destination or outcome ships | "stays archived" (→ the Garage's archived row, J13, exists and lists the car - the RU capture shows both), "Delete again" (→ the tombstone: the car appears in **Recently deleted** with its rows - `RecentlyDeletedView.deletedVehicles`, `restoreVehicle` brings the arriving entry back with it because `softDeleteVehicle` stamps them together), "Keep" (→ the archived car stays), "Scan receipt" (→ Capture in Expense mode), `RV.297`'s "no move" price caption | Every phrase names something that exists |
| 4 · a row ships PARTIALLY | `PJ.44` - the row's "swipe-down" was a sheet the wizard is not (it is pushed with its bar hidden), so that exit does not exist rather than being unbuilt; the two exits that exist (Back → Close; a presenter popping) are covered. `RV.300` - fixed both tiers, the iOS half by bounding the false red rather than removing the contention (the main actor and pool are the process's, not the test's); said so in the row | No remainder to file |

## 4. Pass 1 - reachability from a cold launch, no debug flag

- The S5 card: `VehicleReturnNotices.items` runs inside both roots' `load()`; the answers go through the repository and bump `AppToastCenter.revision`, which both mounted roots already observe - no flag, no route.
- The expense scan door: a `Button` on the production completion sheet for every `.expense` reminder; the cover is a `.fullScreenCover` on the same sheet.
- The wizard's delete-on-exit: `.onDisappear` on the production `ImportWizardView`; the stub-count marker is DEBUG-only and gates nothing.
- The unit conversion: pure functions at render time, no state.

## 5. Pass 2 - sequence

| Chain | Status | Evidence |
|---|---|---|
| delete a car → an entry arrives → Delete again → the second tombstone pushes → a later entry arrives | MET | `deleteReturnedVehicleAgain` = `softDeleteVehicle` (dirty) + consume; a further arriving entry resurrects again and opens a fresh notice (`VehicleReturnNoticeTests`: the resurrect is what writes the row) |
| Delete again → Recently deleted → Restore | MET | the car and the arriving entry share the tombstone stamp; `restoreVehicle` restores both (`Repository.swift:82`) |
| Keep → a further entry arrives for the (live, archived) car | MET | `resurrectArchivedIfTombstoned` is a no-op for a live car with no open notice (`aLiveCarWithNoNoticeIsNeverNoticed`) |
| answer on Garage → Home's copy | MET | one revision bump, both roots reload (`HomeReturnedCarUITests`, `GarageUITests` - the first cut of the L4 failed exactly here, on the OTHER root's stale copy, before the bump was added) |
| the S5 vehicle merge on the OTHER device (B logged the entry, A archived the car) | MET, by S5's own design | B pulls an archived car; the field-level merge (S9) keeps B's other edits; no card on B - the notice is device-local and `SYNC.md` now says so |
| wizard: pick a file → preview → sheet (target car / not supported / send file) → back to the wizard | MET | sheets and `fileImporter` do not fire the presenter's `onDisappear`; the wizard pushes no route of its own (grep: no `NavigationLink`/`onNavigate` in `Import/`); the tab roots hide by `.opacity` (`TabRoots.swift:223`), so a tab switch does not fire it either |
| wizard: confirm → pop | MET | `didConfirm` guards the cancel; the commit's own delete already ran |
| expense reminder: Scan → save → completion → the reminder's next cycle | MET | `RemindersUITests.testAnExpenseReminderOffersTheScanDoor…` lands the seeded title in the expense form; the completion is the same `ReminderCompletionSession.Pending` the typed door uses |
| expense reminder: Scan → close the cover without saving | MET | `captureClosed()` clears `completionSession.pending` (RV.298 row) |
| a MPG car: Confirm quote → Home hero → Trends arrow → the month divider → the anomaly card | MET | one conversion (`ConsumptionDisplay`), the arrow and percent follow the DISPLAYED figure (`HeadlineChange.displayedPercent(in:)`), `ConsumptionUnitUITests` |

## 6. Proposed rows

None new. One doc drift fixed in the walk (the S5 card missing from `SCREENMAP.md`'s Home and Garage rows).

## 7. Cited, not re-filed

`RV.299` (the iOS 27 share-sheet test - the one red in every `ImportUITests` run this tranche) · `RV.181` (J8b, J13) · `RV.114`, `RV.179`, `RV.288`-`RV.290` (J4) · `PJ.300` (owner) · `RV.295` (iOS 27 OCR measurement) · `PJ.39` (the interrupted-restore row, next in the batch).

## 8. Could not settle

- J8's `REVIEW-SCENARIO` is still owed (status cleared by `RV.118`; `RV.296`/`RV.297` changed the story again). Not run here: a scenario review is the other brief.
- F10's status line (`implemented 2026-09-12`) was kept: `PJ.40` did not change what F10 promises - it made the promised S5 notice real. The journey text carries the date it became real.

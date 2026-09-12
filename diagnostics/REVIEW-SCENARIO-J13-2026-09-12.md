# REVIEW-SCENARIO run: J13 - 2026-09-12 (first walk)

- **Scenario:** `J13` - Selling the car (`docs/JOURNEYS.md:529-533`)
- **Run id:** REVIEW-SCENARIO-J13-2026-09-12
- **Report path:** `diagnostics/REVIEW-SCENARIO-J13-2026-09-12.md`
- **Context:** Never walked. Every v1 row naming J13 is closed; deferred and N/A: `PJ.37` [v1.1] (PDF dossier), `RV.123` [v2] (transfer). Related shipped today: `RV.260` (restore from a Tankbook backup). Walked sell -> export -> archive/delete -> undo -> the other car's Trends. Read-only except this report and the status line.

## Verdict

**Orchestrator hold (2026-09-12):** the status line this verdict wrote was reverted. `RV.181` is `[~]` because the product owner reported the RELEASE build cannot share a photo or export data - and per-car export IS J13's exit path. Owner evidence outranks a code walk; the line is written after the device step in `RV.181` proves a share, as for J8b.

**IMPLEMENTED** - every v1 promise in the journey text is MET in code or reasoned N/A (the PDF dossier is `PJ.37`, deferred in the journey's own text). The one open row naming J13, `RV.181` (`[~]`, the share-sheet destination dispatch), is a cross-cutting share-layer concern owned by `F13`, does not represent a J13 code gap, and does not block the status line - the same conclusion the J8b walk (`REVIEW-SCENARIO-J8b-2026-09-12b`) reached for the same seam.

## Ticked rows found to be untrue

None. Every `[x]` row naming J13 was walked against code:

- **PJ.38** (CSV per car) - true: `CarCSVExport.render` (`ios/Sources/TankbookCore/Backup/CarCSVExport.swift:38-49`) emits four per-type files with SCHEMA.md names, the money pair (`moneyFields:133-146`) and ISO dates, tombstones included (`fillUpsIncludingDeleted:39`).
- **PJ.36** (whole-account archive) - true, not J13's path: `ExportBuilder.buildAccountArchive` (`Export/ExportBuilder.swift:17-23`); the per-car row uses `buildCarExport` (`:28-37`).
- **RV.98** (deleted car reaches Recently deleted) - true: `deletedVehicles()` (`Persistence/Repository+RecentlyDeleted.swift:100-120`) queries tombstoned vehicles; `RecentlyDeletedView` renders `DeletedVehicleRow` with a Restore (`RecentlyDeletedView.swift:97-102,441-480`).
- **RV.99** (delete confirmation names the car) - true: `deleteConfirmTitle` composes the name (`VehicleDetailView.swift:484-487`), alert at `:77-83`.
- **RV.100/RV.101** (last-car stats / delete cascade) - true by inspection of `softDeleteVehicle` (`Persistence/Repository.swift:69-77`, one stamp across the vehicle and every vehicle-scoped table) and `restoreVehicle` (`:82-95`); the last-car Home state is fixed upstream (`RV.100` closed).
- **RV.81** (archiving strips reminders) - true: `toggleArchive` reconciles on both directions (`VehicleDetailView.swift:451-471`), the Reminders row is hidden on an archived car (`:214-233`).

**One dispatch premise is not what it was stated to be:** the run brief says "every v1 row naming J13 is closed." `RV.181`'s first cell literally reads "(J13 export - and J8b sharing a receipt)" (`docs/TASKS.md` -> RV section), and it is `[~]`, not `[x]`. It is the export's destination-dispatch defect. This does not change the verdict (see Not settled) but it is why "all closed" is not literally true.

## Promise-to-code map

| Journey promise (J13) | Status | Citation |
|---|---|---|
| Garage -> vehicle -> "Export history" | MET | `GarageView.swift:142` and `:216` (`NavigationLink(value: Route.vehicleDetail(...))` for live and archived rows); `CarSwitcherView.swift:176` (archived row -> detail); the export row renders unconditionally in `VehicleDetailView.formContent` (`VehicleDetailView.swift:165-167`) |
| Per-car export: CSV + JSON | MET | `VehicleExportRow.buildExport` (`VehicleExportRow.swift:54-65`) -> `ExportBuilder.buildCarExport` (`ExportBuilder.swift:28-37`) writes the per-car archive (`VehicleArchiveWriter.writeArchive`, `Backup/VehicleArchiveWriter.swift:33-43`, manifest + data JSON) plus the four CSVs (`CarCSVExport.write:56-65`); share items = `csvURLs + [directory]` (`ExportBuilder.swift:36`) |
| Export is per-car (only the sold car, never the others) | MET | `writeArchive(vehicleID:)` collects that car's entries/reminders/attachments only (`VehicleArchiveWriter.swift:3-8`); CSVs rendered per `vehicleID` (`CarCSVExport.render:38-49`) |
| Export "always free", works with no account | MET | local-only build, no network, no account gate; row subtitle states "always free" (`VehicleExportRow.swift:29`) |
| Archive the car: history retained, out of active stats | MET | `archiveVehicle` sets `archived`/`archivedAt`, never touches rows (`Repository+VehicleArchive.swift:14-23`); `VehicleSelection.resolve` drops archived from the selection fallback (`Consumption/VehicleSelection.swift:21-27`); switcher/garage render archived cars dimmed with no vitals (`CarSwitcherView.swift:323`, `GarageView.swift:420`); archived banner states "history is kept" (`VehicleDetailSections.swift:146-165`) |
| "Archived · sold <when>" honest label | MET | `L10n.archivedSubtitle(archivedAt:)` (`L10n.swift:103-109`); `archivedAt` stamped on archive, cleared on unarchive (`Repository+VehicleArchive.swift:14-35`) |
| Archive is reversible (Unarchive) | MET | `unarchiveVehicle` (`Repository+VehicleArchive.swift:26-35`); header flips Archive/Unarchive (`VehicleDetailSections.swift:39`) |
| Delete is a tombstone with 30-day undo (spine) | MET | `softDeleteVehicle` (`Repository.swift:69-77`); Recently deleted car row + Restore (`RecentlyDeletedView.swift:97-102,327-339`); purge on a 30-day window |
| Undo restores the whole group (spine) | MET | `restoreVehicle` restores the car and exactly the rows sharing its stamp (`Repository.swift:82-95`); `DeletedVehicleRow` title counts entries restored together (`RecentlyDeletedView.swift:119-123`) |
| The other car's Trends recompute (spine) | MET | `VehicleSelection.resolve` falls back to the first live car when the selection is archived/gone (`Consumption/VehicleSelection.swift:21-27`); stats are derived, so the remaining garage re-derives (hard rule 2) |
| PDF service-and-fuel dossier (resale value) | N/A | `PJ.37` [v1.1], deferred in the journey's own text (`docs/JOURNEYS.md:531`, `docs/TASKS.md` PJ.37) |
| Dossier as marketing artifact (app name in the buyer's hands) | N/A | same `PJ.37` deferral; QR-on-PDF tracking is part of the dossier |
| Transfer the car to the buyer's account | N/A | `RV.123` [v2] (`docs/TASKS.md` RV.123) |

## Sequence trace (one user selling the Volvo)

1. Garage -> tap the Volvo card -> `Route.vehicleDetail` (`GarageView.swift:142`); archived cars reach the same detail (`:216`), so export-after-archive also works.
2. "Your data" -> `VehicleExportRow` -> `buildCarExport` writes the per-car archive + four CSVs into a temp dir and hands `csvURLs + [directory]` to `SharePresenter.present` (`ExportFlow.swift:26-29`, top-most controller `ActivityView.swift:36-52`).
3. Archive -> `toggleArchive` -> `archiveVehicle` (flag + stamp) -> reconcile cancels the sold car's reminders -> the switcher/garage re-render it dimmed, out of stats, and the selection resolves to the first remaining live car (`VehicleSelection.resolve`).
4. Delete instead -> confirmation names the car -> `softDeleteVehicle` tombstones the car and every vehicle-scoped row at one stamp -> the Recently deleted screen shows one car row whose Restore (`restoreVehicle`) brings the whole group back.
5. The other car's Home/Trends re-derive from the remaining live car; nothing from the sold car leaks into active stats.

**Where a fact stops being carried:** nowhere in the local sequence. The one crossing that can stop carrying a fact is the share sheet's destination on a physical device, and that crossing is `RV.181`/`F13`, not J13 code.

## Proposed rows

None. Every J13 promise is MET or N/A; the one open row naming J13 (`RV.181`) is already filed and owned by `F13`, and re-filing it would duplicate it. No field-nothing-writes, entity-nothing-creates, or doc-names-behaviour-without-a-call-site shape was found on the J13 path (the archive/export writer and reader round-trip is pinned by `VehicleArchiveTests`/`CarCSVExportTests`, and the reader now has a production caller via `RV.260`).

## Not settled

- **`RV.181` (`[~]`) names J13 and is open, and it is the one place the spine's "the history leaves with the car" could break on a physical device.** I do not block the status line on it, for the same reason the J8b walk did not: the J13 export promise is that the app *builds and hands off* the car's history as CSV + the Tankbook archive, and that is MET in code (`ExportBuilder.buildCarExport` -> `SharePresenter.present` from the top-most controller). The open tail of `RV.181` - out-of-process share destinations (Mail, Messages) unconfirmed on a physical device, in-process Save to Files working - is a cross-cutting share-layer concern whose journey is `F13` (explicitly "OPEN", `docs/JOURNEYS.md:752`), not a J13 code gap. `F13`'s own text ("J13's promise depends on it") is the strongest reason to be careful here, and a future reader should re-open this status line if `RV.181` is found to break the export specifically rather than the share seam generally. The `ShareOutcome` log (`ActivityView.swift:138-150`) now makes that next device report answerable, so the residual is tracked, not hidden.
- **The dispatch premise "every v1 row naming J13 is closed" is false by one row** - `RV.181` is `[~]`. `scripts/scenario-index.py` treats `[~]` as neither open nor closed (its readiness filter only counts `[ ]` and `[!]`, `scenario-index.py:102`), which is how a partially-landed row naming the scenario was invisible to the readiness gate. This is a tooling gap, not a J13 code gap, and is worth its own `no-scenario` row outside this walk.
- **"Export history" is the journey's word; the shipped label is "Export this car's data"** (`VehicleExportRow.swift:26`). Copy, not behaviour - the affordance is the same and the row is reachable. Flagged for the next change touching the copy glossary, not filed.

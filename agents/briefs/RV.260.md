# RV.260 - the restore-from-export door does not exist

**Scenarios: J11 · new phone ("the local file export always available as the user-held
fallback"), F7 · restore fails or comes back empty (source 3, "import a file you exported
yourself").** `[!]` - the hole that held J11's review; a dead end on the screen that exists to
prevent data loss.

`VehicleArchiveReader.importArchive` (`ios/Sources/TankbookCore/Backup/VehicleArchiveReader.swift:51`)
has zero callers in `ios/App/Sources`. The export side is real: `ExportBuilder.buildAccountArchive`
and `buildCarExport` (`ios/App/Sources/Export/ExportBuilder.swift:17,28`) write the `docs/SCHEMA.md`
-> Backup format archive. Both restore-failure rows (`RestoreFailureViews.swift:72,194`, RV.239) link
`Route.importWizard`, whose picker sends the file to `/import/parse` for MFM/Drivvo - it rejects a
Tankbook archive. Hard rules 7, 8, and 1 (this path is LOCAL: no network at all).

## Build

1. **A local restore-from-backup flow**: `.fileImporter` for the archive (what does the export
   hand the share sheet - a directory, a zip, or the CSVs? Read `ExportBuilder` and
   `ExportShareable`; accept exactly what the export produces, and say what that is), then
   `VehicleArchiveReader.importArchive` with the right `VehicleArchiveImportMode`. `guardScope`
   (`:191`) stays the guard: a `vehicle` archive is never treated as an account restore - surface
   its refusal with the named next step (`docs/ERRORS.md`, add the row).
2. **Doors**: both restore-failure rows become this door (the third-party wizard keeps a door of
   its own beside it or one step in - one way, say why), and Settings gets it beside Export.
   `docs/SCREENMAP.md` gains the screen; `docs/JOURNEYS.md` J11 and F7 say the fallback is a
   Tankbook backup, not a foreign file.
3. Nothing network: no `/import/parse`, no session required. A guest can restore a backup.

**Sibling check (`docs/DEFECT-PATTERNS.md`)**: is there any OTHER reader in `TankbookCore` with
no app caller (the "feature built on an entity nothing creates / reader with no writer" shapes)?
Grep the `Backup/` and `Export/` directories' public entry points against `ios/App/Sources` and
list them - a list is a deliverable, fixing them is not.

## Tests

- **L4 `SignInUITests` (or a new `RestoreFromBackupUITests`), FAILS TODAY, EN + RU**: a backup
  archive built by `ExportBuilder` (not hand-made in the test) is seeded into a reachable
  location, the empty-restore row is tapped, the archive's car and its entries appear on Home -
  never the third-party source picker.
- **L1**: a `vehicle`-scope archive offered as an account restore is refused with the named
  reason (extend `VehicleArchiveProtectionTests` if it does not already cover the mode).
- `VehicleArchiveTests` stay green.

Run the named UI suite in its own invocation; count non-zero. Screenshots EN + RU of the new
screen and of the empty-restore screen with its two doors:
`design/screenshots/RV.260-restore-from-backup.png`, `-ru.png`,
`RV.260-empty-restore-doors.png`, `-ru.png`, dark.

## Mutation - named

Point the empty-restore row back at `Route.importWizard`; the L4 goes red on the source picker
appearing. Verbatim.

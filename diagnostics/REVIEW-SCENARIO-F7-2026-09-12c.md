# REVIEW-SCENARIO run: F7 - 2026-09-12c (re-walk, after RV.260)

- **Scenario:** `F7` - Restore fails or comes back empty (`docs/JOURNEYS.md:697-705`)
- **Run id:** REVIEW-SCENARIO-F7-2026-09-12c
- **Report path:** `diagnostics/REVIEW-SCENARIO-F7-2026-09-12c.md`
- **What changed:** `RV.260` shipped (`d99824fb`), `RV.261` shipped (`24a7683a`). Re-checked only what the 12b walk gated on, plus the RV.256/RV.257 decision. Read-only; no code, no build, no commit.

## Verdict

**IMPLEMENTED** - RV.260's local restore-from-backup door is live end to end, and RV.261's recency + [v2] reconciliation is done. The source-3 dead door that held the 12b verdict is closed.

## Ticked rows found to be untrue

None. RV.260 and RV.261 hold against the tree.

## Promise-to-code map (only what the 12b walk gated on)

| Journey promise (F7) | Status | Citation |
|---|---|---|
| **Source 3 - "import a file you exported yourself" is a local Tankbook backup** (no account, no network, hard rule 1) | MET | `Route.restoreFromBackup` (`Routes.swift:81`) -> `RestoreFromBackupView` (`Destinations.swift:46`); `RestoreFromBackupModel.importBackup` calls `VehicleArchiveReader.importArchive(at: mode: .singleCar)` (`RestoreFromBackupModel.swift:76-96`), so the reader now has its production caller. Model built over the app repository + `FileBackedBlobStore` with no session (`:65-71`). The picker accepts a folder only (`RestoreFromBackupView.swift:46`) |
| **A full-account export is refused locally with its named next step** | MET | `VehicleArchiveReader.guardScope` throws `.scopeMismatch` for `.singleCar` + `.account` (`VehicleArchiveReader.swift:195-196`); the view renders "This is a full-account backup, not a single car." with next step "Sign in with the same account to restore everything, or export a single car and restore that here." (`RestoreFromBackupView.swift:148-149,169-170`) |
| **The third-party importer is a door BESIDE the backup one, not the fallback** | MET | both failure screens carry two rows: `Route.restoreFromBackup` ("Import a file you exported yourself") above `Route.importWizard` ("Import from another app") - empty at `RestoreFailureViews.swift:76-87`, unreachable at `:207-218` |
| **The door is reachable from both restore-failure screens** | MET | `NavigationLink(value: Route.restoreFromBackup)` in the `.empty` recovery card (`RestoreFailureViews.swift:76`) and the `.unreachable` actions card (`:207`) |
| **The door is reachable from Settings, beside Export** | MET | `SettingsView.swift:329` (`exportRow`) then `:331-332` `NavigationLink(value: Route.restoreFromBackup)` "Restore from backup" |
| **A successful import from a failure screen lands on Home (sheet closes, not just pops)** | MET | `SignInFlowHost` injects `backupFlow` and sets `backupFlow.onImported = { dismiss() }` in `.onAppear` (`SignInView.swift:24,69-71`); `RestoreFromBackupView.handleOutcome` calls it, else plain `dismiss()` for the Settings path (`RestoreFromBackupView.swift:187-196`) |
| **The Restoring screen renders last-odometer recency (RV.261)** | MET | `RestoringView.lastOdometerLine` appends `recencySuffix` (`RestoringView.swift:115-131`); `lastOdometerDaysAgo` is derived in core (`Restore.swift:74`) and carried through `RestoreSnapshot` -> `SignInFlow` (`SignInFlow.swift:17,33`), not a dead field |
| **J11's source-device clause marked [v2]** | MET | `docs/JOURNEYS.md:518` now reads "the source device - from your Android phone - is **[v2]**"; the never-set `lastOdometerDeviceName` and dead `L10n.lastOdometerSource` are gone from `ios/App/Sources/` (grep: NONE FOUND) |

All other F7 promises (sources tried honestly, backend-down copy, empty-before-logging-new, provider-switch loop, post-restore stats) were MET in the prior walks and are unchanged by RV.260/RV.261 - not re-walked.

## Sequence trace (the one user, the one thing)

**Restore-door user with an exported archive, backend down:** new phone -> "Already use Tankbook? Restore your garage." -> sign in -> pull fails -> `.restoreUnreachable` ("Sync service unreachable - ... You can import an export file ...") -> tap "Import a file you exported yourself" -> `Route.restoreFromBackup` pushes `RestoreFromBackupView` inside the sign-in sheet -> "Choose backup folder" -> system folder picker -> `importBackup` -> `VehicleArchiveReader.importArchive(.singleCar)` -> per-car archive lands as a car and its entries -> `handleOutcome` -> `backupFlow.onImported` closes the whole sheet -> Home shows the restored car. **The fact "I exported this myself" now reaches the reader that can honour it** - the 12b dead end is closed.

**The same user holds a full-account export instead:** picker -> `guardScope(.singleCar, .account)` throws -> "This is a full-account backup, not a single car." + "Sign in with the same account to restore everything..." - refused locally with the sync path named, never silently treated as one car.

## Proposed rows

None. The 12b walk's only missing piece was RV.260, which shipped; no new gap found.

## Not settled

- **RV.256 (open) does not touch F7.** It is the `UserDefaultsSyncStateStore` one-key display bleed (`docs/TASKS.md:816`) - account A's last sync success/failure rendering on B's account card until B's first cycle. That is J11/J11a account-card display state; none of F7's four promises (sources, backend-down copy, empty-before-logging, post-restore stats) reads that store. Attaches to J11/J11a, not this scenario.
- **RV.257 (open) does not change F7's verdict.** It is `no-scenario: test determinism` (`docs/TASKS.md:817`) - the `testEmptyRestoreShowsRecoveryBeforeAddCarIsUsable` L4 is nondeterministic because the stub-auth scenario does not seed the sync transport. The promise that test exercises (empty restore shows recovery before add-car) is implemented and otherwise verified; the row is a flaky-test fix, not a missing or wrong promise. F7 is IMPLEMENTED regardless.

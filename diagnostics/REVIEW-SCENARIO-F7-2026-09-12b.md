# REVIEW-SCENARIO run: F7 - 2026-09-12b (second walk, after RV.259)

- **Scenario:** `F7` - Restore fails or comes back empty (`docs/JOURNEYS.md:697-705`)
- **Run id:** REVIEW-SCENARIO-F7-2026-09-12b
- **Report path:** `diagnostics/REVIEW-SCENARIO-F7-2026-09-12b.md`
- **First walk:** `diagnostics/REVIEW-SCENARIO-F7-2026-09-12.md` (verdict NOT IMPLEMENTED, one sequence hole)
- **What changed:** `RV.259` shipped (`1cf79ac8`). Re-checked only what the first walk gated on, plus the RV.260 source-3 question the first walk did not see. Deferred rows N/A. Read-only; no code, no build, no commit.

## Verdict

**NOT IMPLEMENTED** - RV.259 is shipped and the both-providers-empty loop is closed (the first walk's one hole), but F7 source 3 ("import a file you exported yourself") is still a dead door: the reachable row opens the third-party importer, which cannot read a Tankbook backup. That is exactly RV.260, which is open (`[!]`) and being built now - so F7's source-3 promise does **not** survive with that row open, and it is not re-filed.

## Ticked rows found to be untrue

None. RV.259 holds against the tree: `didSwitchProvider` is set in `switchProvider` after its `signOutLocally()` (which resets it), read in the `.empty` arm, so a second empty account resolves to `.emptyRestore` and never a second `.wrongProvider`.

## Promise-to-code map (only what the first walk gated on)

| Journey promise (F7) | Status | Citation |
|---|---|---|
| **"truly nothing found ... includes after a provider switch (RV.259)"** - a second empty account lands on the recovery screen, never the reverse question | MET | `SignInFlow.didSwitchProvider` declared `SignInFlow.swift:136`; `switchProvider` sets it after `signOutLocally()` (`:191-198`, reset at `:207`); the `.empty` arm routes `.wrongProvider` only when `arrivedViaRestore && offersGoogle && !didSwitchProvider`, else `.emptyRestore` (`:319-340`). Tests: `SignInFlowTests.swift:85-88,100-102` assert `.emptyRestore` after a switch, `:118-126` pins the `.unreachable` sibling |
| **The `.unreachable` sibling** - reachability says nothing about which account holds the data, so no wrong-provider question after a switch | MET | `.unreachable` arm always `.restoreUnreachable` (`SignInFlow.swift:341-346`); pinned by `SignInFlowTests.swift:110-126` |
| **The recovery entry point is reachable 100%** (metric) | MET | both failure screens carry the row (`RestoreFailureViews.swift:72` empty, `:194` unreachable); the loop that could route away is closed by RV.259 |
| **Source 3 - "import a file you exported yourself"** | PARTIAL | the row is present and reachable (`RestoreFailureViews.swift:72-76,194-198` -> `Route.importWizard`), but `Route.importWizard` maps to `ImportWizardView` (`Destinations.swift:46`), the third-party importer driven by `GET /import/formats` + `/import/parse` (`ImportSourceView.swift:131-164`; `ImportWizardView.swift:80,109`). `VehicleArchiveReader.importArchive` (`Backup/VehicleArchiveReader.swift:51`) has **zero callers in `ios/App/Sources`** - its only callers are `ios/Tests/TankbookCoreTests/*`. The export side is real (`ExportBuilder.buildAccountArchive`/`buildCarExport`, `ExportBuilder.swift:17-28`), so a user whose sync restore failed and who exported taps the fallback and lands on a wizard that rejects their own file. **This is RV.260, open and in flight - not re-filed** |

All other F7 promises (sources tried honestly, backend-down copy, empty-before-logging-new, post-restore stats, honest outcome routing) were MET in the first walk and are unchanged by RV.259 - not re-walked.

## Sequence trace (the one user, the one thing)

**Restore-door user whose account is empty on both providers:** Welcome -> "Already use Tankbook? Restore your garage." -> sign in (Apple) -> pull -> `.empty` -> `arrivedViaRestore && offersGoogle && !didSwitchProvider` -> wrong-provider question (`SignInFlow.swift:328`) -> "switch" -> `switchProvider` sets `didSwitchProvider` -> Google account created empty -> `.empty` -> now `didSwitchProvider` is true -> `.emptyRestore` (`:339`) -> "No data found" + "Expecting your data?" recovery card + "Start fresh". **The fact "no data under either provider" is now carried to a terminal state** - the loop is closed; RV.259's fix carries `didSwitchProvider` through the sign-out that would otherwise reset it, by setting it after the reset.

**The remaining sequence hole (RV.260, in flight):** on that `.emptyRestore` screen the user taps "Import a file you exported yourself" -> `NavigationLink(value: Route.importWizard)` -> `ImportWizardView` -> the third-party source picker (MFM/Drivvo). The user's own Tankbook backup archive is not a parseable third-party source, so the tap is a dead end on the screen that exists to prevent data loss. This is the one fact that stops being carried: "you exported this yourself" is promised by the copy and not honoured by the door.

## Proposed rows

None. The only missing piece is RV.260, already filed (`TASKS.md:820`, `[!]`, in flight). Re-filing it would duplicate an open row; the brief forbids it.

## Not settled

- **Verdict timing.** F7 cannot be IMPLEMENTED until RV.260 lands: its check (`L4 SignInUITests`: a seeded backup archive, tap the row, the car and entries appear on Home - not the source picker) is the one test that would currently fail. A third F7 walk should re-verify RV.260 and then set the status line. RV.260 is being built by a build agent in this checkout at the time of this walk - this report did not read its in-progress tree, only committed HEAD (`1cf79ac8`).

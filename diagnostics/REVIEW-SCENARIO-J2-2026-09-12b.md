# REVIEW-SCENARIO run: J2 - 2026-09-12b (second walk, after RV.255)

- **Scenario:** `J2` (`docs/JOURNEYS.md:64-80`)
- **Run id:** REVIEW-SCENARIO-J2-2026-09-12b
- **Report path:** `diagnostics/REVIEW-SCENARIO-J2-2026-09-12b.md`
- **Scope:** re-check ONLY what the first walk gated on (the **Commit** stage's *"garage now shows full history"*) plus the two doc drifts it named. `RV.255` (`0286bed3`) shipped the selection write; `a966618a` reconciled the Verify wording and the F6 "one source" drift. Everything else the first walk found MET/N/A is out of scope and unchanged. Read-only walk; no code, no build, no commit.

## Verdict

**IMPLEMENTED**

## Ticked rows found to be untrue

None. The one row the first walk proposed (RV.255, "select the car the import created") is shipped and walks to code end to end.

## Promise-to-code map (Commit stage + the two drifts)

| Promise (J2 text) | Status | Citation |
|---|---|---|
| Commit *"garage now shows full history"* - the car the import **created** is selected, so Home shows the imported history, not the old car | MET | `createdVehicle` reset per commit (`ImportFlowModel+Wizard.swift:352`), set to the single new target (`:364-368`) or the first new lane of the gate in displayed order (`:377-382`); the wizard selects it through the one `AppCarSelection` write before dismissing (`ImportWizardView.swift:186-205`); `AppCarSelection.select` persists `Preferences.defaultVehicleId` and mirrors `selectedID` so Home reloads in place (`AppCarSelection.swift:28-32`) |
| Commit - an import into an **existing** car leaves the user's chosen car selected | MET | `createdVehicle` stays nil (no new car upserted), so `selectCreatedCar` returns without writing (`ImportWizardView.swift:200`); `selectExistingVehicle` → `targetCar = .existing` (`ImportFlowModel.swift:320-322`) |
| Commit - the multi-car gate's selected car is the **first new lane in displayed order** | MET | `carPlan` is built in file order of first appearance (`ImportFlowModel+Cars.swift:22-35`) and `ImportCarsView` renders `ForEach` in that same order (`ImportCarsView.swift:31`); the loop sets `createdVehicle` only for the first contributing new lane (`ImportFlowModel+Wizard.swift:377-382`) |
| Verify *"check it against the number they remember"* (was *"next to the old app's"*) | MET (doc drift reconciled) | `JOURNEYS.md:74` now reads the F6a "from memory" reframing; the derived consumption still ships (`ImportPreviewView.swift:85-112`) |
| F6 *"the guide covers each shipping source"* (was "one source") | MET (doc drift reconciled) | `JOURNEYS.md:602` now names My Fuel Manager and Drivvo carrying the same `helpUrl`; `ImportFormats.cs` populates both |

## Sequence trace (existing-car user, import into a NEW car - the case the first walk gated)

1. Signed-in Home → `Route.importWizard`; the wizard is under `TabRoots`, which injects `carSelection` into the environment (`TabRoots.swift:304`), so the selection write is reachable from every door (Welcome, Settings, Home-guest - all under `TabRoots.swift:280-283`).
2. Source picker → file picker → `POST /import/parse`; a single-car file with an existing garage car lands on `ImportTargetCarSheet`, where the user takes the "New car" door (`selectNewCar` → `targetCar = .new`, `ImportFlowModel.swift:324-326`).
3. Preview/mapping gate → `confirmImport`: `carPlan.isEmpty` → `upsertVehicle(newCar)` → `createdVehicle = newCar` (`ImportFlowModel+Wizard.swift:363-368`). The multi-car gate takes the same shape through the loop (`:377-382`).
4. Wizard `confirm`: `ok == true` → `selectCreatedCar` → `carSelection.select(created)` persists the durable selection and mirrors `selectedID` (`ImportWizardView.swift:186-205` → `AppCarSelection.swift:28-32`) → toast → `dismiss`.
5. Home (already presented behind the sheet) observes `selectedID` and re-resolves to the created car; RV.103's `onChange(of: vehicle.id)` resets the log reveal to the new car's history (`HomeSections.swift:374-378`).

**Fact carried end to end:** the created car's identity now survives the commit→selection boundary. On the guest path, `WelcomeRootView.reevaluate()` swaps to tabs once `liveVehicles()` is non-empty (`WelcomeRootView.swift:65-72`), and the tabs' Home reads the same persisted selection. No step drops the "which car did I just import" fact.

## Proposed rows

None.

## Could not settle / non-blocking observations (carried from the first walk, unchanged)

- **The "complete migration" journey test** for import still does not exist as a cold-launch, seed-free navigation walk (RV.110/RV.165's `ColdLaunchJourneyUITests` ships four OTHER journeys). RV.255's `ImportRV255UITests.testImportIntoNewCarSelectsItOnReturnHome` is a seeded journey test that asserts the exact landing (switcher label + a log row with no switcher tap), so the gated defect is covered. Testing-coverage observation only, not a J2 promise gap.
- **`uploadedFileData`** remains a field nothing reads in production (dead state; noted, not filed - not a schema entity, not user-visible).

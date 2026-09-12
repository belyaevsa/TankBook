# REVIEW-SCENARIO run: J2 - 2026-09-12 (first walk)

- **Scenario:** `J2` (`docs/JOURNEYS.md:64-80`)
- **Run id:** REVIEW-SCENARIO-J2-2026-09-12
- **Report path:** `diagnostics/REVIEW-SCENARIO-J2-2026-09-12.md`
- **Context:** First walk. Closed today for this scenario: PJ.58 (`ed2d401b`). Closed earlier and naming J2: RV.185, RV.187, RV.176, RV.86, RV.93, RV.103, RV.113, RV.190, RV.221, RV.142, RV.88, PJ.9, PJ.10, PJ.33, PR.28. Deferred and cited-not-re-filed: PJ.21 (`[v1.1]`), P5.4b (`[v1.1]`). Read-only walk; no code, no build, no commit.

## Verdict

**NOT IMPLEMENTED** - every stage of J2's walk is MET or reasoned N/A in code except one: the **Commit** stage's *"garage now shows full history"* is false on the first render when the import creates a **new** car while the garage already has one - the write selects nothing, so the user lands back on their previous car and the imported history is off-screen until a manual switch. One proposed row below; the Verify stage's *"next to the old app's"* is a doc drift, not a code gap (F6a, the more specific authority, reframes it as *"from memory"*).

## Ticked rows found to be untrue

None. Each closed row naming J2 was walked against the tree and holds:

- **RV.185** (currency + name): `TargetCar.newCar` now REQUIRES `homeCurrency` (`ImportService.swift:147-159`); `newCarHomeCurrency` = `effectiveCurrency ?? defaultCurrency` (`ImportFlowModel.swift:334-340`); `answerCurrency` re-homes every synthesized NEW car and leaves existing cars alone (`ImportFlowModel+Wizard.swift:70-80`); name editable at the preview (`ImportPreviewView.swift:183-195`) and the mapping gate (`ImportCarsView.swift:232-243`), id preserved by in-place rename (`ImportFlowModel.swift:346-353`). L1 `ImportRV185CurrencyTests.swift:51-107` uses a KZT fixture and asserts the STORED car, not the draft.
- **RV.187** (title chain): one function `EntryTitle` (`EntryTitle.swift:14-77`) serves the Log row (`HomeSections.swift:491-493`), the duplicate card (`HomeDuplicateCard.swift:63,118-120`), excluded (`ExcludedEntriesView.swift:202`), flagged (`FlaggedEntriesView.swift:297`) and Recently deleted (`RecentlyDeletedView.swift:249-250`). L1 `RV187EntryTitleTests.swift:38-88` asserts the value, the fallbacks, and that the two entry points agree.
- **PJ.58** (service item hardcode): `ImportConversion.makeItem` takes `homeCurrency` and passes `vehicle.homeCurrency` (`ImportConversion.swift:140-150`); `makeService`/`makeExpense`/`makeFill` all home in the car's currency (`:101-102,121,44-45`). L1 `PJ58ImportCarItemCurrencyTests.swift:30-43` asserts car, record and item agree on a KZT fixture. Production grep: no third `homeCurrency:` literal in import code - only `ImportFlowModel+Wizard.swift:111` (documented rule-13 default) and `ImportReviewView.swift:125` (symbol fallback when no car is loaded).
- **RV.86** (multi-car mapping): `hasMultipleCars` gates the `.cars` step (`ImportFlowModel+Cars.swift:16-18`); a single-name file keeps the single `targetCar` flow (`routeAfterParse:31-40`); Continue disabled until every lane decided (`carsGateIsReady:45-47`); per-lane odometer/duplicate figures never cross cars (`carFigures:121-130`, `mergeDuplicateCount:137-147`).
- **RV.93** (whole-export pick): `allowsMultipleSelection` + one staged copy and one `/import/parse` per file (`ImportWizardView.swift:60-119`); per-file failures survive the run (`fileFailures`, `ImportFlowModel+Wizard.swift:606-684`); ONE `commitImport` for all files (`confirmImport:346-394`).
- **RV.103** (reveal): whole-month pages with a load-more row and a hidden-count (`HomeSections+LogStream.swift:23-92`), reset on car switch via `onChange(of: vehicle.id)` (`HomeSections.swift:374-378`), survives a same-car reload (state, no reset path).
- **RV.190** (not-yet chips derived): `notYetBlock` filters roadmap names against the live list (`ImportSourceView.swift:241-254`); `ImportRoadmapImporters.swift`.
- **RV.113 / RV.221 / RV.142 / RV.88 / PJ.9 / PJ.10 / PJ.33 / PR.28**: each walked and unchanged from its recorded DONE; citations in the map below.

## Promise-to-code map

| Journey promise (J2) | Status | Citation |
|---|---|---|
| **Export** - in-app illustrated guide per source app | MET | `helpUrl` populated for both shipping formats (`ImportFormats.cs`: mfm + drivvo); "How to export" link on the format row (`ImportSourceView.swift:207-217`) and inside the 422 card (`:626-629`) |
| **Import** - declare the source app, never the format | MET | `selectFormat` from the live `GET /import/formats` list (`ImportFlowModel.swift:217-245`, `ImportSourceView.swift:174-226`) |
| **Import** - never sniff the file; a mis-declared file is rejected, not auto-mapped | MET | parse 422 -> `.doesNotMatchDeclared` (`ImportFlowModel.swift:47,522-533`); `ParseFailure` vocabulary never guesses |
| **Import** - RV.190 chips derived, not written down | MET | `notYetBlock` filters the roadmap constant against the server list (`ImportSourceView.swift:241-254`) |
| **Import** - share sheet | N/A | `[v1.1]` PJ.21 (`TASKS.md:768`); the file picker is the v1 door |
| **Map the cars** (RV.86) - one question per source car, never guessed | MET | `.cars` gate only when `resolvedVehicleGroups.count > 1` (`ImportFlowModel+Cars.swift:16-18,31-47`); one-car file never sees it |
| **Map the cars** - leave out / new / existing, Continue disabled until all decided | MET | `ImportCarsView.swift:221-297`, `carsGateIsReady` (`ImportFlowModel+Cars.swift:45-47`) |
| **Map the cars** - per-car figures, never cross-car | MET | `carFigures` filters by the group's own rows (`ImportFlowModel+Cars.swift:121-130`) |
| **Name it** (RV.185) - new car's name pre-filled and typed over, id preserved | MET | `newCarName` = file's vehicle else neutral default (`ImportFlowModel.swift:329-332`); editable field (`ImportPreviewView.swift:183-195`, `ImportCarsView.swift:236-243`); in-place rename (`renameNewCar:88-93`) |
| **Verify** - fill count, date range, odometer span, currency/units, total spend, derived consumption | MET | `ImportSummary.compute` over the exact fills the commit writes (`ImportConversion.swift:493-525`); rendered in `figuresCard` + `headlineCard` (`ImportPreviewView.swift:85-166`) |
| **Verify** - *their lifetime average "next to the old app's"* | PARTIAL | the derived consumption ships (`ImportPreviewView.swift:85-112`); the old app's own number is never shown - no importer returns it, and F6a (`JOURNEYS.md:614-618`) reframes it as *"check against their own memory"*. Doc drift, not a code gap |
| **Commit** - flag ambiguous rows for review instead of guessing | MET | `ImportReviewClassifier.partition` (`ImportConversion.swift:308-384`); `.timelineConflict`/`.crossCheckMismatch`/`.missingOdometer` review rows |
| **Commit** - the declared currency becomes the new car's home currency (RV.185) | MET | `newCarHomeCurrency` (`ImportFlowModel.swift:334-340`); re-home on answer (`ImportFlowModel+Wizard.swift:70-80`); upsert the synthesized car before commit (`:360-377`) |
| **Commit** - garage now shows full history | **PARTIAL** | the write lands every row (`commitImport`, `Repository+ArchiveImport.swift:198-205`) but **selects nothing**; see sequence trace |
| **Read the log** (RV.187) - service/expense rows named | MET | `EntryTitle` chain (`EntryTitle.swift:14-77`) across all five surfaces |
| **RV.103** - "see my imported history" works in place | MET | `HomeLogReveal` + `loadMoreRow` (`HomeSections+LogStream.swift:23-92`); reset on car switch (`HomeSections.swift:374-378`) |
| **Success metric** (completion rate, tickets) | N/A | metric, not code |

## Sequence trace (one user, non-EUR history, file pick to Home)

1. Welcome / Settings / Home-guest -> `Route.importWizard` (`WelcomeRootView.swift:37`, `SettingsView.swift:323`, `HomeGuestLayout.swift:246`).
2. Source picker loads `GET /import/formats`; user declares the app (`ImportFlowModel.loadFormats`, `ImportSourceView.formatRow`).
3. File picker (multi-select) -> staged copy -> `POST /import/parse` per file (`ImportWizardView.swift:60-119`).
4. `routeAfterParse`: multi-car -> `.cars` mapping; single-car -> `ensureTargetCar` (`ImportFlowModel+Cars.swift:31-40`).
5. Preview/mapping gate: derived consumption, figures, editable name (new car), currency question (no-currency file), date-format question (`ImportPreviewView.swift`, `ImportCarsView.swift`).
6. Currency answer -> `applyHomeCurrencyToNewCars` -> `rebuildClassification`; name edit -> in-place rename preserving id.
7. `confirmImport`: `upsertVehicle(newCar)` for each new destination -> one `commitImport(records + stations)` -> `deleteStoredParses` -> `AppRates.scheduleDrainAfterImport` (`ImportFlowModel+Wizard.swift:346-394`).
8. Toast -> `dismiss()` (`ImportWizardView.swift:176-184`). From Welcome, `reevaluate()` sees the new car and swaps to tabs (`WelcomeRootView.swift:65-72`).

**Where a fact stops being carried: exactly one - the imported car's identity is dropped at the selection boundary.** `confirmImport` writes the new `Vehicle` and its rows but never calls `selectVehicle`/`carSelection.select`, and the wizard's `confirm` only toasts and dismisses. `AppCarSelection` resolves the persisted `defaultVehicleId` or falls back to the first non-archived vehicle (`VehicleSelection.swift:21-27`). For the canonical J2 switcher (fresh install, the import is the first car) the first-non-archived fallback lands on the imported car and the walk is clean. For a user who already has a car and imports a **second** history into a **new** car - the `ImportTargetCarSheet` "New car" door and every new lane of the multi-car gate - the persisted selection still points at the old car, so the first Home render shows the old car and the imported history is off-screen until a manual switch. Every screen is right; the "which car did I just import" fact is lost between the commit and the first Home render (the `RV.185`/`RV.189` sequence shape).

## Proposed rows

| # | Deliverable | Closes | Consequence today | Severity | Check | Scenario |
|---|---|---|---|---|---|---|
| 1 | Select the new car the import created (the single new target, or the first new lane) when the commit succeeds, so the returned Home shows the imported history | J2 Commit *"garage now shows full history"* | A user who imports a second history into a NEW car lands back on their old car; the imported rows are present (switcher, derived stats) but not on screen, so the moment reads as "my import disappeared" - the same "reads as data loss and is not" family as RV.25 | gap | L4 `ImportUITests` (or the cold-launch journey): one car seeded, import a fixture into a NEW car, assert the returned Home renders that car's log rows without a manual switcher tap; mutation = remove the selection write and the test fails | J2 |

## Not settled

- **Verify stage doc drift.** J2's Verify note (*"next to the old app's"*) promises a comparison no importer's data can supply, and F6a - the more specific authority - already reframes it as *"from memory"*. The derived-consumption figure ships, so this is wording, not a missing feature; a one-line reconcile on the next change touching either doc settles it. Not a blocking row.
- **The "complete migration" journey test for import does not exist.** RV.110 named it as a priority and was closed as a duplicate of RV.165, but RV.165's `ColdLaunchJourneyUITests` shipped four OTHER journeys (add-car, scan, delete-car, feedback) and not the Import path. The import has no cold-launch, navigation-seeded-free test. This is a testing-coverage observation, not a J2 promise gap; it folds into the same selection row's check if that is written as a journey test.
- **`uploadedFileData` is a field nothing reads in production.** Declared (`ImportFlowModel.swift:73`), cleared (`ImportFlowModel+Wizard.swift:318`), written only by a DEBUG seed (`ImportFlowModel+Seeds.swift:41`). Dead state, not a schema entity and not user-visible; noted, not filed.
- **F6's "the guide covers one source" is stale.** `JOURNEYS.md:601` says the guide covers only My Fuel Manager; both shipped formats now carry the same `helpUrl`. Doc drift, no code gap - the link exists for both.

(End of report)

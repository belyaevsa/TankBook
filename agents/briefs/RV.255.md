# RV.255 - the import selects nothing, so an existing-car user lands back on the old car

**Scenario: J2 · switching from another app.** The one stage that held J2's review at NOT
IMPLEMENTED (`diagnostics/REVIEW-SCENARIO-J2-2026-09-12.md`, Commit: *"garage now shows full
history"*).

`ImportFlowModel.confirmImport` (`ImportFlowModel+Wizard.swift:346`) upserts the synthesized
`Vehicle` for a `.new` target (`:362-363`) and for every `.new` lane of the multi-car gate
(`:372-374`), commits every row, and `ImportWizardView.confirm` (`ImportWizardView.swift:175`)
toasts and dismisses. Nothing calls `AppCarSelection.select` (`AppCarSelection.swift:28`), so the
Home the wizard returns to resolves the persisted `defaultVehicleId` - the OLD car. A fresh install
is fine (the first-non-archived fallback lands on the import); a user who already has a car and
imports into a NEW one sees their old car and reads the moment as "my import disappeared".

## Build

When `confirmImport` succeeds and the import CREATED a car, select it: the single `.new` target,
or the first `.new` lane of the multi-car gate in its displayed order. An import into an EXISTING
car changes the selection **not at all** - the user chose that car, do not yank them elsewhere.
Use the existing `AppCarSelection.select(_:)` write from the wizard view (it already holds
`carSelection` from the environment, `ImportWizardView.swift:12`); the model reports WHICH car it
created, the view selects. Do not add a second selection path.

**Sibling check (`docs/DEFECT-PATTERNS.md`)**: `WelcomeRootView.reevaluate()` swaps to tabs when
the first car appears - confirm it does not now fight the selection; and the `ImportTargetCarSheet`
"New car" door and the multi-car gate must both end selected. Fix siblings in the same change.

## Tests

- **L4, FAILS TODAY** in `ImportRV255UITests` (new file, `ios/App/UITests/`): seed one existing
  car (`-seedImportNewCar` seeds the new-car door - read `ImportRV185UITests.swift:46` and the seed
  in `ImportTestSeed.swift:83` for the arguments), import a fixture into a NEW car, assert the
  returned Home shows THAT car's name in the switcher and one of its log rows **without a switcher
  tap**.
- **L4**: an import into the EXISTING car leaves the switcher on it.
- **L1** if the model exposes "which car did I create": one for the single target, one for the
  multi-car gate, one asserting nil on an existing-car import.

Run: `xcodebuild test ... -only-testing:TankbookUITests/ImportRV255UITests` and
`-only-testing:TankbookUITests/ImportRV185UITests` (its own invocation each; check the count is
non-zero). Screenshots EN + RU of the returned Home, `design/screenshots/RV.255-home.png` and
`RV.255-home-ru.png`, dark theme.

## Mutation - named

Delete the `select` call; the new-car L4 goes red on the switcher name, the existing-car L4 stays
green. Verbatim output.

## Docs

`docs/JOURNEYS.md` J2 Commit row: add the sentence that the import lands on the car it created.
`docs/SCREENMAP.md` if the wizard's back-path text names where it returns to.

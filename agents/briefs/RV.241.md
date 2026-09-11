# RV.241 - the Welcome screen names what the build does

**Scenario: J1 · first launch, empty garage.** The only v1 row holding J1 open. Small; copy only.

`WelcomeView.swift:89` *"Fuel, charging and service - one log"* names EV charging (v2, `PJ.49`);
`:103` *"Scan receipts and pump displays"* names pump scanning, which ships off
(`PumpPhotoGate.allowsPumpPhoto == false`). `PJ.51` applied the same rule to the store listing
today. Both artboards carry the lines (`design/screens/Welcome.dc.html:25,32`,
`LightWelcome.dc.html:25,32`).

## Build

Drop *charging* from the tagline and *pump displays* from the feature row - **EN and RU**, in
`Localizable.xcstrings`, and in both artboards in the same change (`PJ.3b`'s artboard rule).
Write the replacement as a full sentence per language, not a word removed from a template: RU
*"Топливо, сервис - один журнал"* reads differently from the three-item list. Keep the tagline's
rhythm; say what you chose.

## Tests

- **L1 in `LocalizationGateTests`, FAILS TODAY**: the two Welcome keys contain neither *charging* /
  *зарядк* nor *pump* / *колон* - so re-adding them with `PJ.49` is a deliberate edit of the test.
- **L4 `WelcomeUITests` EN + RU**: frames of the Welcome screen, opened by the orchestrator;
  capture lines already exist for `PJ.3` - re-shoot them.

## Mutation - named

Restore *charging* in the EN tagline; the L1 goes red. Byte-identical restore; verbatim.

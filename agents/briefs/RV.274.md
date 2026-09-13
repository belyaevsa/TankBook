# RV.274 - two per-litre prices under a per-gallon label

**Scenario: J3b · type it (the unit in the sentence).** The price counterpart of `RV.272`/`RV.273`;
the last reader of a stored per-litre value that RV.234's per-unit labels exposed.

`AttachmentValueFormat.value`'s `.money` case for `.unitPrice` (the recognised page,
`AttachmentRecognisedView.swift`) and `InboxValueFormat.yours` / `fuelReceipt(.unitPrice)`
(`InboxComparison.swift`) print the stored price per LITRE under `FieldLabel.text(.unitPrice,
volumeUnit:)`, which reads *Price/gal* on a gallons car. `RV.272` built the converter -
`ManualFillUpMath.displayUnitPrice(perLitre:unit:)` / `unitPricePerLitre` - for the Confirm
pre-fill; these two readers do not call it.

## Build

Route both sites through `displayUnitPrice` - the one converter, never a copy - the way `RV.271`
and `RV.273` routed the volume readers through `displayVolume`. Then grep for `unitPrice` /
`pricePerL` reaching a `Text` without `displayUnitPrice`; the list is the deliverable and should
be empty.

## Tests

- **L1 per site, FAILS TODAY**, metric and imperial: a stored 1.679 €/L renders *6.356* per US
  gallon on a gallons car and *1.679* on a metric one.
- **L4 `InboxUITests`** on an imperial car (the RV.271 seed): the per-gallon price in both
  columns. EN + RU frames only if a committed frame changes.

## Mutation - named

Print per litre again at one site; its L1 goes red. Verbatim.

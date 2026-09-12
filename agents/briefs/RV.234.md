# RV.234 - the unit in the sentence: the rest of the seam

**Scenario: J3b · type it (the peer path, every locale).** The third pass over one seam: `RV.126`
scoped to a file and missed two, `RV.134` scoped to five sites and listed seven more. This row is
the seam - every sentence that bakes a unit in, except the reminders (km-only by construction, a
separate decision).

The sites `RV.134`'s audit listed, re-find each by its key: the Confirm volume row label
*Liters* over a field holding gallons (`ManualFillUpSections.swift:181`); the disabled-save hint
*Enter total and liters to save*; the VoiceOver `verifyLabel` *Check the liters on the receipt*;
`RestoringView.swift:121` hardcoding `.km`; *Check litres* (`F9aFixRow`); *check the litres or the
odometer* (RV.218's warn); *Unusual consumption - check the litres or odometer* (excluded list);
TankLevel *≈ %d of %d L* and *Set tank size in Garage to see liters*; Home/Trends *Last price/L*,
*Price / L*, *Cost / km*, *per km*; the import price cell and `FieldLabel.text(.unitPrice)`.

## Build

One full localised sentence per (sentence, unit) through `ManualFillUpUnitCopy`'s pattern - never
composed from fragments (the P1.4 RU lesson). Derive the unit from the car's units, the same
source `RV.134` reads. **Then grep the catalogue for every remaining `L`, `km`, `liter`, `litre`,
`гал`, `л`, `км`, `миль` inside a sentence and list what is left** - the list is a deliverable.
The reminders' km-only keys are out of scope: list them under "reminders, separate decision".

## Tests

- **L1 per sentence**, metric and imperial, EN and RU - a table-driven test, not one test per key.
- **L4 RU on an imperial car** (`ManualFillUpUITests` or RV.134's file): the Confirm volume row
  reads *гал* and the hint reads *галлоны*. Screenshots EN + RU imperial:
  `RV.234-confirm-imperial` and `RV.234-home-imperial`, dark - the frames the orchestrator opens.

## Mutation - named

Hardcode the volume row label back to *Liters*; the imperial L1 and the RU L4 go red. Verbatim.

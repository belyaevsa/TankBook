# PJ.58 - a second hardcoded `.eur` in the import, on service line items

**Scenario: J2 · switching from another app.** `[!]`. The only v1 row holding J2 open.

`ImportConversion.makeItem` (`:145` on 2026-09-10; re-find by the `.eur` literal) builds every
service line-item cost as `Money(amount:currency:homeCurrency: .eur)` - the car's home currency
is never consulted. Sibling of `RV.185`'s `TargetCar.newCar` hardcode, fenced out of that row, so a
KZT car imported today has service items homed in euros. `RV.167`'s money guard is blind to a plain
assignment by its own stated limit.

## Build

Pass the vehicle's home currency into `makeItem` exactly as `RV.185` does for the car. **Then grep
the whole tree for `.eur` literals outside tests and seeds** - the list is a deliverable; each hit
is either a fixture, a documented default, or a third instance of this bug. **Then say whether
`RV.167`'s guard should widen** to catch a `homeCurrency:` literal outside the accumulator; if the
widening is one clause and the calibration holds (no false positive on the seed files), do it here.

## Tests

- **L1, FAILS TODAY**: importing a service row for a KZT car yields items homed in KZT.
- **L1**: the car and its items agree on home currency for every converted row.
- If the guard widened: **L1** red on a scratch literal, green on the tree.

## Mutation - named

Restore the `.eur` literal; the KZT L1 goes red. Verbatim.

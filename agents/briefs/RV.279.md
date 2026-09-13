# RV.279 - the Expense and Service capture forms are missing the fields Edit entry has

**Scenarios: J7b · the shop receipt, J7 · the invoice, J10 · a foreign receipt, J3b · the peer
path.** `[!]`. Reported by the product owner 2026-09-13: after capturing an expense the form has
no odometer and no currency; both are there on Edit entry. Two doors to one entry must be the
same screen.

- `ExpenseEntryView` renders Category / Title / Amount only; saves `odometer: nil` (`:242`) and
  `Money(amount:currency: vehicle.homeCurrency, homeCurrency: vehicle.homeCurrency)` (`:243-244`);
  the home symbol is a fixed label (`:214`).
- `ServiceEntryView` has the date/odometer card (`ServiceEntrySections.swift:195`) but no currency;
  every line item is minted in the home currency (`ServiceEntryFormState.serviceItem(homeCurrency:)`,
  `:77-85`).
- `EditEntryNonFillView` carries the odometer card (`EditEntryNonFillView+Odometer.swift:15`) and
  `CurrencyChipRow` with the car's currency offer (`:308-309`) for both kinds.
- The RV.200 boundary (`JOURNEYS.md:384`: a foreign total is never offered *"because the expense
  form cannot express one"*) is the consequence of the missing field, not a rule.

## Build

1. **The same components, not copies**: the capture forms render Edit entry's odometer card and
   `CurrencyChipRow` (the car's offer, `docs/SCHEMA.md` → Currency offer) in the same positions
   Edit entry has them. If the odometer card is bound to `EditEntryNonFillView`'s form state,
   lift it the way `CurrencyChipRow` was lifted - one view, two form states.
2. **Save what the user chose**: `odometer` when typed (nil stays nil - an expense away from the
   car has none; hard rule 13, never the "last known" as a fact); `Money(amount, currency: chosen,
   homeCurrency: car)` with the rate snapshot at the entry's date, through the same conversion the
   fill-up path uses (`ManualFillUpCurrencySupport.convertForSave` or its shared core) - rate
   pending when no rate, never today's rate (hard rule 3). Service line items: the chosen currency
   applies to the record and its items alike (the record and items agree - `PJ.58`, `PJ.300`).
3. **The RV.200 boundary relaxes**: a scanned foreign total is offered WITH its currency
   (`ExpensePrefill.currency` already carries it, `Extraction/ExpensePrefill.swift:34`); the
   `currencyFitsForm` gate (`ExpenseEntryView.swift:364-366`) goes.
4. `docs/JOURNEYS.md` J7b: rewrite the *cannot express a foreign total* sentence to what ships;
   `docs/SCREENMAP.md` if the form rows are listed; `docs/ERRORS.md` if a rate-pending expense
   needs its line (the fill-up one may already cover it - say).

## Tests

- **L4 `ExpenseCaptureUITests` and `ServiceEntryUITests`, EN + RU, FAIL TODAY**: the odometer and
  currency rows are present with Edit entry's identifiers; picking a foreign currency and saving
  stores a pair whose `currency` is the pick and whose home side is pending or snapshotted.
- **L1**: a scanned foreign total pre-fills amount AND currency; the save carries a snapshot at
  the entry's date; a typed odometer lands on the record, an empty one stays nil.
- Screenshots `RV.279-expense-capture` and `RV.279-service-capture`, EN + RU, dark; open the
  existing Edit-entry frames side by side and say the rows match.

## Mutation - named

Save the home currency regardless of the chip; the foreign-currency L4 goes red. Verbatim.

## Vacuous trap

Rendering the chips and saving home anyway; pre-filling the "last known" odometer as if typed.

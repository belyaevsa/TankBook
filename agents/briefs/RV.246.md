# RV.246 - a late expense read carries the receipt's date

**Scenarios: J7b · the shop receipt, J3 · the receipt catches up with you.** Decided by the product
owner 2026-09-12: add `date` to the expense read (option "do"), one shape with `RV.244`'s service
date.

`ExpenseRecognition` (`InboxRecognition.swift:79-87`) carries `total` and `category` only -
`RV.200`'s deliberate field set - while `Expense` has a date and the receipt prints one.
`ExpensePrefill` (`Extraction/ExpensePrefill.swift:34`) already carries the printed date into the
FORM at capture time (`RV.62`); the LATE read, which lands in the Inbox after the user saved with
today's date, has no field to offer. A parking ticket dated last week, saved as today, stays wrong.

## Build

Mirror `RV.244` exactly: `ExpenseRecognition.date: GatewayFieldValue<Date>?`, filled where the
expense read is built (`CaptureExpenseScan.swift:96`, from the same parse `ExpensePrefill` reads),
and offered through `GatewayInboxPolicy`'s existing `dateOffer` the way the service branch does
(`GatewayInboxPolicy.swift:241`) - one `dateOffer`, not a copy. `userChangedDate` (`RV.244`'s
rule) applies: a date the user set by hand is never overwritten, only offered. `InboxTestSeed`
seeds a differing date so the Inbox row can be seen.

## Tests

- **L1, FAILS TODAY**: a late expense read whose receipt date differs from the entry's offers
  `.date`; one that agrees offers nothing; one where the user changed the date offers it as a
  suggestion, never applies it.
- `InboxUITests` (own invocation, count reported) EN + RU on the seeded expense: the date offer
  renders on the same line as its label with the amber caption below (the layout rule the owner
  set on 2026-09-12 - never stacked). Screenshots `RV.246-inbox-expense-date` EN + RU, dark.

## Mutation - named

Stop filling `date` on the expense read; the differing-date L1 goes red. Verbatim.

## Docs

`docs/EXTRACTION.md` if it lists the expense read's fields; `docs/SCHEMA.md` `ExpenseRecognition`
shape if it is spelled there.

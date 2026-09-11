# RV.244 - a late service reading never offers a differing invoice date

**Scenario: J7 · the invoice in your hand.** Small. Filed from `RV.215`'s report.

`InvoiceSplitResult` returns a parsed `Date`; `ServiceRecognition.date` wants the original string
(`GatewayFieldValue<String>`, matching the fuel extraction's raw date). The real scanner's
recognition therefore carries no date, so the Inbox can never offer a differing invoice date for a
service. The merge handles `.date` already; the producer never fills it.

## Build

**One shape for both producers.** Decide: either the recognition carries a `Date` (change
`ServiceRecognition.date` and the merge's date branch for `.service`, keep the fuel branch string-
based because that is what the gateway returns), or `ServiceInvoiceScanner` formats the parsed date
back to the string form `ConfirmDate.parse` accepts. The first is honest - a parsed date is a date;
the second re-encodes what was already decoded. Say which and why; `RV.201`'s `merged` is the one
function that must keep working for all three kinds.

## Tests

- **L1, FAILS TODAY**: a service recognition built from the real `ServiceInvoiceScanner` output
  with an invoice date that differs from the saved record offers `.date`.
- **L1**: one that agrees offers nothing (the `RV.215` policy test's shape).
- No UI change; no frames.

## Mutation - named

Drop the date from the scanner's recognition again; the first L1 goes red. Verbatim.

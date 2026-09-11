# RV.243 - a deferred expense read that lands after the save loses the receipt photo

**Scenarios: J3 · the receipt catches up with you, J7b · the shop receipt.** `[!]` - hard rule 8.
Filed from `RV.215`'s own report; J3 cannot be marked implemented while a photograph can vanish.

`RV.215` made the expense and service reads deferrable. The photo is attached only when `scan` is
set at load, so a read that finishes **after** `markSaved` leaves `attachments` nil: the inbox item
carries amount and category, and the photograph the user took is gone. `PJ.28`'s photo crossing
`RV.215`'s deferral; nothing owned the combination.

## Build

**Persist the photo at SAVE, whether or not the read has finished.** The fill-up path already does
this - `writeReceiptPhoto` runs on save with whatever the plan holds - and the non-fill saves have
`attemptReceiptPhotoWrite` (`RV.204` made it the one seam for every kind). Make the expense and
service saves call it with the captured image regardless of the read's state; the late read then
only offers values through the Inbox, exactly as it does now. One seam; no second write path.

Check the service invoice too (`ServiceInvoiceSession`): a multi-page invoice read that lands after
the save must not drop its pages.

## Tests

- **L1, FAILS TODAY**: an expense saved while its read is pending has its photo on disk and in
  `attachments` after the read lands; the inbox item still exists for the values.
- **L1**: the same for a service invoice.
- **L4 `ExpenseCaptureUITests`** with `-seedExpenseScanDelay`: save before the read finishes, open
  the entry from the Log, the receipt card is there and opens the photo. EN + RU frames of the
  entry with its receipt after a deferred save; capture lines.

## Mutation - named

Gate the photo write on the read having finished again; the pending-save L1 goes red. Byte-identical
restore; verbatim.

## Vacuous traps

- Asserting the inbox item exists rather than that the photo is on disk.
- Writing the photo twice (once at save, again when the read lands).

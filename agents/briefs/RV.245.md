# RV.245 - a cancelled service scan leaves orphaned invoice pages

**Scenario: J7 · the invoice in your hand.** Hygiene; disk, not user-visible.

Since `RV.243` invoice pages are written to `InvoicePageStore` (rows + files) at scan START, so a
deferred read cannot lose them. Dismissing the ServiceEntry sheet without saving leaves those rows
and files with no record; the server-side orphan sweep (P4.3) never reaches the device.

## Build

One mechanism, and say which: (a) delete the staged pages when the sheet is dismissed without a
save - find the one dismiss path (`ServiceEntryView`'s cancel and the sheet's swipe-down must share
it; RV.204's `EditEntryView+FillReceiptSave` shows the shape for fills), or (b) sweep pages with no
owning record at launch, bounded and shape-only logged. (a) is precise, (b) is resilient to a
crash mid-scan; if you pick (a), say what a crash leaves behind and whether (b) is still needed
as a backstop. Hard rule 12: log counts only.

## Tests

- **L1, FAILS TODAY**: cancel after a staged scan leaves no page rows and no files.
- **L1**: a saved record keeps its pages; a second record's pages are untouched by the first's
  cancel.
- If (b): **L1** the sweep removes only orphans and reports a count.

## Mutation - named

Remove the cleanup call; the cancel L1 goes red on the row count. Verbatim. No UI change.

# REVIEW-SCENARIO run: J7b · Parts, tires, consumables - 2026-09-12b (third walk, after RV.246)

**Run id:** REVIEW-SCENARIO-J7b-2026-09-12b · **Walked by:** the orchestrator (product owner, 2026-09-12: walks are not dispatched) · **Tree:** `38e03031`

## Verdict

**IMPLEMENTED.** The second walk (`REVIEW-SCENARIO-J7b-2026-09-12.md`) found every promise MET;
its status line was cleared when `RV.246` redefined one sentence - the late shop-receipt offer
now carries the receipt's printed date. That sentence is re-walked to code below; nothing else in
the journey text changed. `RV.267` (a cancelled expense scan is discarded) also shipped since;
it touches the scan door's abandon path, which the journey does not promise beyond "opens the
empty form with no error" - cited, MET.

## Ticked rows found to be untrue

None. `RV.246` walked to code, not to the tick (below). `RV.267`: `ExpenseEntrySession.discard()`
(`ExpenseEntrySession.swift:116`) is called from `ExpenseEntryView.onDisappear` unless `didSave`
(`ExpenseEntryView+DiscardScan.swift`); `RV267CancelledExpenseScanTests` 3/3, the orchestrator's
mutation went red on the cancel test.

## Promise-to-code map (the changed sentence only; the rest stands from the second walk)

| Promise (J7b, "A late shop-receipt reading reaches the inbox") | Status | Evidence |
|---|---|---|
| the inbox offers the amount, the category **and the receipt's printed date** | MET | `ExpenseRecognition.date: GatewayFieldValue<Date>?` (`InboxRecognition.swift`); `GatewayInboxPolicy.expenseOffers` appends `dateOffer(current: entry.date, read: recognition.date?.value)` (`GatewayInboxPolicy.swift:268`) - the same helper the service (`:241`) and fill-up (`:224`) branches use |
| the date is the same parse the form's pre-fill reads | MET | `ExpenseScanOutcome.recognition(from:preset:)` builds the read's `date` from `prefill.date` (`ExpenseEntrySession.swift:48`), i.e. `ExpensePrefill.date` (`Extraction/ExpensePrefill.swift:34`); one parse, two consumers |
| a differing date is offered, never applied on its own | MET | offered only when it differs (`dateOffer`, `:412-414`); applied only when the tick is in `fields` (`mergedExpense`, `:375-376`); a user-changed date is offered, never overwritten - `testAUserChangedDateIsOfferedAsASuggestionAndNeverApplied` |
| the same merge function serves the three kinds | MET | `mergedExpense` mirrors `mergedService` (`:334-335`) and the fill-up merge (`:290-291`) on `.date` |
| rendered per field, label beside the value | MET | `InboxComparison.swift:51,98` renders `.date` in both columns; frames `RV.246-inbox-expense-date` EN + RU opened by the orchestrator: "Date · Sep 12, 2026 · Sep 5, 2026" on one row |

## Sequence trace (one user, a parking ticket dated last week, saved today)

1. Expense-mode scan → `acceptExpenseScan` starts the deferred read (`RV.215`); the form opens
   with the pre-fill, including the printed date when the parse had it (`ExpensePrefill.date`).
2. User saves with today's date before the read lands (or the pre-fill had no date).
3. The read finishes after the save → `onSavedAnswer` → `AppInbox.recordLate…` with
   `ExpenseRecognition(total:category:date:)` built from the same parse.
4. `GatewayInboxPolicy.expenseOffers` compares the saved entry to the read: date differs → a
   `.date` offer joins `.total` / `.category` (`:268`).
5. Inbox renders three rows; "Leave it as it is" is the default; ticking date and "Update from
   the receipt" → `mergedExpense` applies exactly the ticked fields (`:375`).
6. A date the user set by hand stays; the offer is a suggestion (hard rule 13).

The fact carried end to end is the receipt's printed date: parsed once, offered once, applied
only on a tick.

## Proposed rows

None. The coverage limit `RV.246`'s tick states (the L1 exercises the builder, not the one-line
call site in `CaptureExpenseScan`) is the same shape `RV.244` has on the service side; it is a
test-coverage note, not a promise gap, and the `InboxUITests` pair drives the call site end to
end (16/16 in the orchestrator's hands).

## Not settled

- The RU frame wraps the "You entered" date value to two lines inside its own column; the label
  stays beside it and nothing truncates. Noted, not filed - the layout rule is about labels.

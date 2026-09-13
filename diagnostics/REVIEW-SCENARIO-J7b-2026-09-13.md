# REVIEW-SCENARIO run: J7b · Parts, tires, consumables - 2026-09-13 (fourth walk, after RV.279)

**Run id:** REVIEW-SCENARIO-J7b-2026-09-13 · **Walked by:** the orchestrator · **Tree:** `ccf509dc`

## Verdict

**NOT IMPLEMENTED.** The third walk (`REVIEW-SCENARIO-J7b-2026-09-12b.md`) found every promise
MET; its status line was cleared when `RV.279` redefined the Expense capture door's sentence - a
foreign total is now offered WITH its currency, and the form carries the odometer card and the
currency chip row. Those sentences re-walk to code below and are MET. The gap is one step later in
the same story: **the late shop-receipt reading carries no currency**, while the fill-up and service
late reads do. A foreign receipt whose read lands after the save offers its foreign figure as an
amount in the entry's saved currency. One proposed row (`RV.280`), then re-walk.

## Ticked rows found to be untrue

None. `RV.279` walked to code (below), not to the tick. One doc line it left stale is fixed in the
same commit as this report: J7b's Purchase stage said *"Odometer not asked"*, and the form now
offers the odometer card (never required, blank stays nil) - the note now says so.

## Promise-to-code map (the sentences RV.279 changed; the rest stands from the second and third walks)

| Promise (J7b) | Status | Evidence |
|---|---|---|
| Purchase: odometer never required on an expense; a blank stays nil, never the last known as a fact | MET | `ExpenseEntryFormState.odometerValue` (`ExpenseEntryFormState.swift`) blank → nil; `canSave` is the amount alone; no `lastKnown` read anywhere in `ExpenseEntryView.swift` / `ExpenseEntryFormState.swift` (grep); `RV279CaptureCurrencyOdometerTests` typed-lands / blank-stays-nil |
| the expense form carries the same currency chip row and odometer card Edit entry renders | MET | `EntryOdometerCard` (`Shared/EntryOdometerCard.swift`) rendered by `EditEntryNonFillView+Odometer.swift` and `ExpenseEntryView.swift:412-419` with Edit entry's identifiers; `CurrencyChipRow` at `ExpenseEntryView.swift:448` and `EditEntryNonFillView.swift:309`, both fed by `CurrencyOfferBuilder.offer` (`ExpenseEntryView.swift:403`, `EditEntryView.swift:208`) |
| a foreign total pre-fills the amount and its currency together | MET | `ExpenseEntryFormState.apply(_:)` sets `currency` before `amount`; `ExpensePrefill.currency` (`Extraction/ExpensePrefill.swift:34`); the `currencyFitsForm` gate is gone (grep: no hits) |
| the save snapshots the pair at the entry's own date; a rate miss stays rate-pending | MET | `ExpenseEntrySave.swift:46-49` → `EntryCurrencyConversion.convertForSave` (`ManualFillUpCurrencySupport.swift`) → `RateStore.resolve(on: date)`; mutation re-minting the pair in the home currency turned the L4 red |
| the service record and its items agree on the chosen currency | MET | `ServiceEntryFormState.serviceItem(currency:homeCurrency:)`; `ServiceEntryDraft.build(currency:)`; `ServiceEntryView.swift:445-456` converts record and items through the same call |
| the late read offers **the amount** the receipt printed | **PARTIAL** | `ExpenseRecognition` (`Inbox/InboxRecognition.swift:84-87`) has `total`, `category`, `date` and **no `currency`**; `ServiceRecognition` (`:39-44`) and the fuel extraction both carry one and `GatewayInboxPolicy` offers/merges it (`:230`, `:257`, `:310`, `:358`). `ExpenseScanOutcome.recognition(from:preset:)` (`ExpenseEntrySession.swift:42-49`) maps `extraction.total` unconditionally and drops `extraction.currency`, so `expenseOffers` (`GatewayInboxPolicy.swift:269-270`) compares a foreign figure to the home amount and `mergedExpense` (`:379-380`) applies it with `replacingAmount` - the pair keeps the saved currency. `InboxComparison.expenseReceipt` renders the read total with `receiptSymbol(entry:read: nil)` (the entry's own symbol) - a PLN figure under a € sign |

## Sequence trace (one user, a foreign shop receipt, the read lands after the save)

1. Expense-mode scan → `acceptExpenseScan` starts the deferred read (`CaptureExpenseScan.swift:42-53`);
   the form opens **without** a pre-fill because the read has not landed.
2. User types the amount; the chip row defaults to the car's home currency (hard rule 13); saves.
   The pair is home/home. Correct so far.
3. The read finishes → `inbox.recordLateGatewayAnswer(.expense(outcome.recognition))` with
   `ExpenseRecognition(total:category:date:)` - the receipt's currency is **dropped here**
   (`ExpenseEntrySession.swift:46`).
4. `expenseOffers` sees the read total differ from the typed amount and offers `.total`
   (`GatewayInboxPolicy.swift:269`). The Inbox row shows the foreign figure with the **home**
   symbol (`InboxComparison.expenseReceipt`, `read: nil`).
5. Ticking it and "Update from the receipt" → `mergedExpense` → `money.replacingAmount(total)`:
   the entry now states the foreign figure **in the home currency** - a wrong fact created by the
   app from a right reading (hard rule 13: a wrong fact is worse than none).

The fact that stops being carried is the receipt's currency, at step 3. It is carried on the
fill-up and service paths through the same policy.

Before `RV.279` this was the `RV.200` boundary's blind spot: the pre-fill withheld a foreign total,
the late read never did. `RV.279` did not create it, it made the fix expressible - the entry can
now hold the currency the read should offer.

## Proposed rows

| Row | Deliverable | Stage | Consequence today | Severity | Check | Scenario |
|---|---|---|---|---|---|---|
| `RV.280` | `ExpenseRecognition` gains `currency`, built from `extraction.currency` in `ExpenseScanOutcome.recognition(from:preset:)`; `expenseOffers` offers `.currency` and `mergedExpense` applies it with `replacingCurrency`, mirroring the service branch; `InboxComparison.expenseReceipt` renders the read total with the read's symbol; a foreign total is never offered without its currency | the late shop-receipt reading | a late foreign read offers its figure as home money and one tick makes the entry state it | **bug** | L1 `GatewayInboxPolicyTests` / a `RV280` file: a foreign late read offers `.total` and `.currency`, taking both yields a pair in the read's currency; L4 `InboxUITests`: the expense inbox row shows the read's own symbol | J7b (also J3 "the receipt catches up with you", J10) |

## Not settled

- Whether a late read whose currency differs should offer the total **only together with** the
  currency (one tick, the way the pre-fill applies them as a unit) or as two ticks the way the
  fill-up branch does today. The brief takes the fill-up shape - two offers, both defaulting to
  "leave it" - so the three kinds stay one policy; the owner may prefer the coupled form.

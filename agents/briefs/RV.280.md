# RV.280 - the late expense read drops the receipt's currency

**Scenarios: J7b · the shop receipt (the late reading reaches the inbox), J3 · the receipt catches
up with you, J10 · a foreign receipt.** `[!]`. Found by the orchestrator's J7b walk after `RV.279`
(`diagnostics/REVIEW-SCENARIO-J7b-2026-09-13.md`).

## The defect, pinned

- `ExpenseRecognition` (`ios/Sources/TankbookCore/Inbox/InboxRecognition.swift:84-87`) carries
  `total`, `category`, `date` - **no `currency`**. `ServiceRecognition` (`:39-44`) and the fuel
  `GatewayExtraction` both carry one.
- `ExpenseScanOutcome.recognition(from:preset:)` (`ios/App/Sources/ServiceEntry/ExpenseEntrySession.swift:42-49`)
  maps `extraction.total` unconditionally and never reads `extraction.currency`.
- `GatewayInboxPolicy.expenseOffers` (`ios/Sources/TankbookCore/Inbox/GatewayInboxPolicy.swift:269-270`)
  therefore compares a foreign figure to the home amount and offers `.total`; `mergedExpense`
  (`:379-380`) applies it with `replacingAmount`, keeping the saved currency. The fuel branch
  (`:230`, `:310`) and the service branch (`:257`, `:358`) offer and merge `.currency` too.
- `InboxComparison.expenseReceipt` (`ios/App/Sources/Inbox/InboxComparison.swift`, the `.total`
  case) renders the read figure with `receiptSymbol(entry:read: nil)` - the ENTRY's symbol, so a
  PLN figure sits under a € sign. The fuel case passes `extraction.currency?.value`.

**Consequence**: scan a foreign shop receipt, the read lands after the save (the form opened
empty, the user typed the amount in the home currency), the Inbox offers the foreign figure as home
money, one tick makes the entry state it (hard rule 13: a wrong fact is worse than none; hard
rule 3: money is a pair).

**This brief's diagnosis is a hypothesis - confirm it before you change anything.** Ruled out:
the pre-fill path (`ExpensePrefill.currency` rides with the total since `RV.279`); the fill-up and
service late reads (both carry currency end to end).

## Siblings (Part A.1 - the inventory)

The three late-read kinds share one policy. Fuel and service carry currency; expense is the one
that does not. There is no fourth kind. The **rendering** sibling is inside `InboxComparison`:
`fuelReceipt` passes the read currency, `expenseReceipt` passes nil - fix both ends in this row.

## Build

1. `ExpenseRecognition` gains `currency: GatewayFieldValue<CurrencyCode>?` (Codable, so an inbox
   row persisted before this change decodes with nil - say in a comment that nil means "the read
   said nothing", never "home").
2. `ExpenseScanOutcome.recognition(from:preset:)` fills it from `extraction.currency` at the same
   confidence the total gets.
3. `expenseOffers` offers `.currency` when the read's differs from the pair's - the same
   `offer(.currency, current:read:)` line the service branch has; `mergedExpense` applies it with
   `replacingCurrency`, after the amount, mirroring `mergedService`. **Both offers default to
   "leave it as it is"** (hard rule 13); the user ticks what they take.
4. `InboxComparison.expenseReceipt` renders the read total with the read's symbol
   (`receiptSymbol(entry:read: recognition.currency?.value)`) and the `.currency` row the way the
   fuel/service kinds do; the "You entered" column stays the entry's.
5. `docs/JOURNEYS.md` J7b "A late shop-receipt reading reaches the inbox": the offered set becomes
   amount, **currency**, category, date; say the currency is the same parse the form's pre-fill
   reads. `docs/ERRORS.md` Inbox rows if they list the expense fields.

Out of scope: coupling the total and currency into one tick (owner question, in the walk report);
`PJ.300`.

## Tests

- **L1, fails today**: `ios/Tests/TankbookCoreTests/RV280LateExpenseCurrencyTests.swift` (the
  `RV246LateExpenseDateTests` shape): a late read with a foreign currency against a home pair
  offers `.total` AND `.currency`; taking both yields a pair whose `currency` is the read's and
  whose snapshot is reset (rate-pending until the pass); taking the total alone keeps the entry's
  currency; a read that agrees offers no `.currency`. **Oracle**: the service branch's behaviour on
  the same inputs (`GatewayInboxPolicyTests`), which this must match line for line.
- **L4** `InboxUITests`, EN + RU: the expense inbox row for a foreign late read shows the read's
  symbol on the receipt side and the entry's on the "You entered" side; ticking currency and
  updating leaves the entry in the read's currency. Seed through `InboxTestSeed` (`:363` builds the
  expense recognition today).
- Screenshots `RV.280-inbox-expense-currency` EN + RU, dark; capture lines added to
  `scripts/capture-screenshots.sh`.

## Mutation - named

In `ExpenseScanOutcome.recognition(from:preset:)`, pass `currency: nil` instead of the read's; the
foreign-read L1 (`offers .currency`) goes red. Verbatim output.

## Vacuous trap

Adding the field and the offer but rendering the receipt total with the entry's symbol still; or
asserting `.total` is offered (already true today) without asserting `.currency`.

## Environment axes

Locale (RU strings on the inbox row); an inbox row persisted before the field existed (decode with
nil). Signed UI runs only - never `CODE_SIGNING_ALLOWED=NO` on `TankbookUITests`.

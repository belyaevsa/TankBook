# REVIEW-SCENARIO run: J7b · Parts, tires, consumables - 2026-09-13b (fifth walk, after RV.280 and PJ.29)

**Run id:** REVIEW-SCENARIO-J7b-2026-09-13b · **Walked by:** the orchestrator · **Tree:** `0fdb1f88`

## Verdict

**IMPLEMENTED.** The fourth walk (`REVIEW-SCENARIO-J7b-2026-09-13.md`) found one PARTIAL promise -
the late shop-receipt reading dropped the receipt's currency - and filed `RV.280`. It shipped, and
`PJ.29` (the product owner's same-day decision) added a sentence to this journey: an Expense-mode
scan now reaches the cloud gateway. Both sentences re-walk to code below; every other promise
stands from the second, third and fourth walks (each cited there to `file:line`).

## Ticked rows found to be untrue

None. Both rows were verified by the orchestrator's own mutation before their tick (`RV.280`:
`currency: nil` in the producer, 4 of 5 L1 red; `PJ.29`: an early `return` before the gateway
start, the L4 red).

## Promise-to-code map (the two sentences that changed)

| Promise (J7b) | Status | Evidence |
|---|---|---|
| the late reading offers the amount **with its currency**, the same parse the pre-fill reads | MET | `ExpenseRecognition.currency` (`Inbox/InboxRecognition.swift`); `ExpenseScanOutcome.recognition(from:preset:)` fills it from `extraction.currency` (`ExpenseEntrySession.swift:47`); `expenseOffers` offers `.currency` and `mergedExpense` applies it with `replacingCurrency` (`GatewayInboxPolicy.swift`); `InboxComparison.expenseReceipt` renders the read total under the read's symbol; frames `RV.280-inbox-expense-currency` EN + RU opened - foreign figure under its own symbol, currency row offered |
| a foreign figure is never offered as home money | MET | same lines; `RV280LateExpenseCurrencyTests` 5/5, mutation red |
| an Expense-mode scan asks `/extract` with `kind: "expense"` under the fill-up guards | MET | `CaptureExpenseScan.startExpenseGatewayIfAvailable` (guards: `allowsServerBacked`, transport, JPEG); `ExpenseEntrySession.startGateway` (`:165-190`, `kind: "expense"`); backend `ExtractKinds.Valid` + `LlmPrompts.AllowedFields("expense")`; `PJ29ExpenseGatewayTests` asserts the kind and hints |
| the provider is asked for the expense's own fields, never fuel fields | MET | `LlmPrompts.cs` `AllowedFields` / `Document`; `LlmPromptsTests` 3/3 |
| a within-budget answer fills blank AND untouched fields only; a late one reaches the inbox | MET | `ExpenseEntryGateway.applyGatewayAnswer` via `GatewaySuggestionPolicy.fillableFields`; `onSavedAnswer` → `inbox.recordLateGatewayAnswer(.expense(...))`; `GatewayCaptureUITests` 15/15 incl. `testALateExpenseAnswerDoesNotChangeTheOpenEditor`, `testASignedOutExpenseScanShowsNoNote`, `testADeadSessionShowsTheSignInNextStepOnTheExpenseForm` |
| one decode feeds the form and the inbox | MET | `ExpensePrefillBuilder.reading(fromGateway:)` (core); `ExpenseGatewayMappingTests` 6/6 |
| the proceed note on the expense form names the next step | MET | `ExpenseEntryView.swift:100-105`; frames `PJ.29-expense-gateway-note` EN + RU opened |

## Sequence trace (one user, a foreign parking ticket, signed in, cloud answer late)

1. Expense-mode scan → local read (fast) → the form opens on it; the gateway request starts with
   `kind: "expense"` the moment the local outcome exists (`CaptureExpenseScan`).
2. The proceed note says a better reading may still arrive; the user types the amount, picks the
   currency on the chip row (`RV.279`), saves. `markSaved` records the entry.
3. The cloud answer lands after the save → `onSavedAnswer` → `ExpensePrefillBuilder.reading(fromGateway:)`
   → `inbox.recordLateGatewayAnswer(.expense(recognition))` with total, currency, category, date.
4. `expenseOffers` compares each; the inbox row shows the read figure under its own symbol
   (`RV.280`); "Leave it as it is" is the default.
5. Ticking total and currency and updating → `mergedExpense` → the pair is in the read's currency
   with its snapshot reset; the next rates pass converts it at the entry's date.

Every fact is carried: the currency from the parse to the offer to the pair; the answer from the
gateway to the inbox, never to the open editor.

## Proposed rows

None for J7b. `PJ.29a` (the service half) belongs to J7 and is briefed
(`agents/briefs/PJ.29a.md`). `RV.205` (owner photographs) is the measurement dependency the second
walk already cited; it does not hold the story.

## Not settled

- Coupling total + currency into one inbox tick - the owner question from the fourth walk stands.

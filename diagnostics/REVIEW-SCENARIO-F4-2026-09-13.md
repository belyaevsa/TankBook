# REVIEW-SCENARIO run: F4 · Cloud LLM fallback unavailable - 2026-09-13 (re-walk after PJ.29 and PJ.29a)

**Run id:** REVIEW-SCENARIO-F4-2026-09-13 · **Walked by:** the orchestrator · **Tree:** `d71309a9`

## Verdict

**IMPLEMENTED.** The prior walk (`REVIEW-SCENARIO-F4-2026-09-11c`) found every promise MET; the
status line was cleared today because `PJ.29` and `PJ.29a` added one bullet - the gateway is no
longer fuel-only - and every existing F4 promise now has to hold on three forms instead of one.
The new bullet and the three-form reach of the old ones re-walk to code below.

## Ticked rows found to be untrue

None.

## Promise-to-code map

| Promise (F4) | Fill-up (unchanged) | Expense (`PJ.29`) | Service (`PJ.29a`) |
|---|---|---|---|
| never waits on the gateway to show the card | MET (prior walk) | MET - the form opens on the local outcome, the gateway starts after it (`CaptureExpenseScan.expenseScanOutcome`) | MET - same order in `CaptureServiceScan.serviceScanOutcome` |
| 3 s budget, proceed note names the next step, late answer never applied to the open editor, lands in the inbox | MET (prior walk) | MET - `ExpenseEntryView.swift:100-105`; `testALateExpenseAnswerDoesNotChangeTheOpenEditor`; late → `.expense` inbox item | MET - `ServiceEntryView.swift:109-114`; `testALateServiceAnswerDoesNotChangeTheOpenEditor`; late → `.service` inbox item |
| within-budget answer fills blank untouched fields only | MET (prior walk) | MET - `ExpenseEntryGateway.applyGatewayAnswer` through `GatewaySuggestionPolicy.fillableFields` | MET - `ServiceEntryGateway.applyGatewayAnswer`, same policy |
| the gateway is not fuel-only: `expense` and `invoice` kinds, own field vocabularies | n/a | MET - backend `ExtractKinds.Valid` + `LlmPrompts`; `LlmPromptsTests` 3/3; `PJ29ExpenseGatewayTests` asserts the kind | MET - `LlmPrompts.AllowedFields("invoice")` header-only; `PJ29aServiceGatewayTests` asserts the kind |
| a guest gets no gateway, on-device still runs (RV.26) | MET (prior walk) | MET - `GatewayScanStarter.makeTransport()` nil → no call; `testASignedOutExpenseScanShowsNoNote` | MET - same guard; `testASignedOutServiceScanShowsNoNote` |
| a dead session says "sign in again" on the capture surface, the entry still saves (RV.65) | MET (prior walk) | MET - `GatewayAuthExpiredNoticeView` on the expense sheet; `testADeadSessionShowsTheSignInNextStepOnTheExpenseForm` | MET - same card on the service sheet; `testADeadSessionShowsTheSignInNextStepOnTheServiceForm` |
| upload compressed on device | MET (prior walk) | MET - `GatewayRendition.jpegData` in `ExpenseEntrySession.startGateway` | MET - same in `ServiceInvoiceSession.startGateway` |
| `.required` config withholds the call (P6.18b) | MET (prior walk) | MET - `guard config.allowsServerBacked` | MET - same guard |
| unreachable hint ("enhanced reading unavailable right now") | N/A - `PJ.18` `[v2]`, stated in the journey text | same | same |
| quota spent → quiet note in Settings, never mid-capture | MET (prior walk; server-side 429 → client falls back) | MET - the same `GatewayScanSession` phases | MET - same |

## Sequence trace

The same three-step story on each form: local result first, note while the cloud runs, late
answer to the inbox. The fact carried is the answer's destination - the open editor before save,
never; the inbox after save, always - and it is one `GatewayScanSession` and one
`GatewayInboxPolicy` for all three kinds, so a fourth kind cannot drift.

## Proposed rows

None. `PJ.18` stands `[v2]`.

## Not settled

- Nothing new.

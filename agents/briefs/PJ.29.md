# PJ.29 - every scanned document reaches the cloud gateway, not only the fill-up receipt

**Scenarios: J7b · the shop receipt (Expense mode), J7 · the invoice in your hand (Service mode),
F4 · cloud fallback unavailable, J3 · the receipt catches up with you.** Pulled from `[v1.x]` into
v1 by the product owner, 2026-09-13: *"why not call the LLM gateway for all kinds of receipt today?
Expenses are a smaller share of the receipts in the log, so the cost won't be big."* The trigger was
a parking receipt that read nothing locally (fixed, `RV.277`) **and nothing in the cloud** - because
the cloud was never asked.

## The gap, pinned

- **Device, expense**: `CaptureExpenseScan.expenseCapture` (`ios/App/Sources/Capture/CaptureExpenseScan.swift:106-114`)
  runs `CapturePipeline.process` alone. The only `/extract` caller in the app is
  `ManualFillUpView.startGatewayReading` (`ios/App/Sources/ConfirmManual/ManualFillUpView.swift:437-462`)
  through `GatewayScanSession`, with `kind: "receipt"`.
- **Device, service**: `ServiceInvoiceScanner` splits lines locally; no gateway call either.
- **Backend**: `ExtractKinds.Valid` (`backend/src/Tankbook.Api/Llm/ExtractModels.cs:15`) is
  `receipt | pump | chargeScreenshot | invoice` - there is no expense kind; the provider's user
  message says *"Extract the fuel fields"* for every kind and `SystemPrompt` allows `total, volume,
  unitPrice, date, station, fuelKind, energy, currency, vendor`
  (`OpenAiCompatibleLlmProvider.cs:79,132`). `llm_settings` is seeded per kind (migration 018).
- **Already there, reuse it**: the deferred boundary (`DeferredRecognition`, RV.215) that decides
  "on time → the open form, late → the inbox"; `GatewayInboxPolicy.item/merged` over `.expense` and
  `.service`; `AppInbox.recordLateGatewayAnswer`; `GatewaySuggestionPolicy.fillableFields` (blank
  AND untouched, unsaved); `GatewayScanStarter.makeTransport()` (nil for a guest - a guest gets no
  gateway, on-device still runs, F4); `GatewayRendition.jpegData`; `config.allowsServerBacked`
  (P6.18b withholds under `.required`); the 3 s budget and the proceed note (`GatewayProceedNote`).

**This brief's diagnosis is a hypothesis - confirm it before you change anything.**

## Siblings (Part A.1)

Three scan kinds, one gateway. Fill-up has it; expense and service do not. This row ships both
non-fill kinds through the SAME closure shape, or ships expense and files the service half with the
seam named - never expense alone silently.

## Build

**Backend**
1. `ExtractKinds.Valid` gains `"expense"`; `ExtractEndpoints` error text lists it; `docs/API.md`
   `/extract` kind list gains it (breaking-change review: additive, say so).
2. Per-kind prompt: the user message names the document (a fuel receipt / a pump display / a
   charging screenshot / a service invoice / a shop or parking receipt); the allowed field names
   for `expense` are `total, date, currency, vendor, category` where `category` is one of the
   `ExpenseCategory` raw values the device knows (`parking, toll, wash, insurance, tax, fine,
   accessory, parts, other`) - the server still reads no meaning, it forwards a name list (rule 9).
   `invoice` keeps `vendor, total, date, currency`. A migration `022_llm_expense_kind.up/down.sql`
   seeds the `expense` row in `llm_settings` the way 018 seeds the four.
3. `ExtractEndpointTests`: `expense` is accepted, an unknown kind is still 400; the prompt for
   `expense` never mentions fuel fields (assert on the recorded provider request).

**Device**
4. `CaptureExpenseScan.expenseScanOutcome`: after the local read has produced the outcome (the
   form opens on it immediately - F4: never wait on the gateway), start `/extract` with
   `kind: "expense"`, the same rendition, hints (currency = the car's home, locale) and
   `captureId` = the session's generation or the entry id, **under the same guards the fill-up
   path uses** (`allowsServerBacked`, a transport, a JPEG). Route the answer through the SAME
   `DeferredRecognition` closure: on time → the open expense form fills **blank AND untouched**
   fields only (amount, currency, date, category) - add the touched set to `ExpenseEntryView` the
   way `ManualFillUpView.markTouched` does; late → `inbox.recordLateGatewayAnswer(.expense(...))`
   with an `ExpenseRecognition` carrying total, currency (`RV.280` adds the field - build on that
   tree), date and category.
5. Map `GatewayExtraction` → `ExpensePrefill`/`ExpenseRecognition` in ONE core function
   (`ExpensePrefillBuilder.prefill(fromGateway:)` or similar) so the on-time and late routes cannot
   drift; `category` decodes to `ExpenseCategory` by raw value, an unknown string is dropped.
6. Service: the same shape with `kind: "invoice"` - the gateway's header fields (vendor, total,
   currency, date) fill blank untouched header fields on time or reach the inbox late through
   `.service(ServiceRecognition)`; line items stay the local split's. If this half does not fit the
   run, ship expense, file the service half as its own row naming this brief, and say so.
7. The proceed note (RV.57) and the auth-expired card (RV.65) render on the expense and service
   forms exactly as on Confirm when the request is in flight / refused.
8. Docs: `docs/JOURNEYS.md` J7b + J7 ("the cloud half remains PJ.29's" sentences → what ships),
   F4 (the three kinds), `docs/EXTRACTION.md` "The Expense-mode hand-off", `docs/API.md`,
   `docs/ERRORS.md` if a new surface carries the note.

Out of scope: an opt-in/opt-out for cloud OCR (`RV.232`, v2 - cloud is on by default for a
signed-in user); coupling total+currency into one inbox tick; `PJ.300`.

## Environment axes

Signed-out (no transport → no call, the local read stands - assert it); backend down / 429 (F4:
the form is already open, nothing blocks, the note names the next step); locale (RU note copy);
Release (no `#if DEBUG` seam may carry the call - `RELEASE=1 scripts/gate.sh`).

## Failure visibility (Part A.5)

`TankbookLog.LlmExtract` already logs kind + outcome shape-only on the server; on the device the
existing gateway events must fire with the new kinds - assert the log event carries `kind`, never
a field value (hard rule 12).

## Tests

- **L1, fails today**: `ExpenseGatewayMappingTests` - a gateway answer with total/currency/date/
  category maps to a prefill and a recognition that agree; an unknown category is dropped; a
  blank-and-untouched amount is fillable, a typed one is not (`GatewaySuggestionPolicy`).
- **Backend**: `ExtractEndpointTests` as in step 3; `dotnet test` green, `dotnet format` 0.
- **L4** `GatewayCaptureUITests` (extend, EN + RU): in Expense mode with `-seedGatewayDelay`, the
  form opens on the local read, the proceed note shows, the late answer lands in the inbox and the
  open editor never changes (the fill-up suite's `testTheLateAnswerDoesNotChangeTheOpenEditor`
  shape); signed-out, no note and no request. `ExpenseCaptureUITests` stay green.
- Screenshots `PJ.29-expense-gateway-note` EN + RU, dark; capture lines added.

## Mutation - named

In `CaptureExpenseScan`, skip the gateway start (return after the local outcome); the L4
"late answer lands in the inbox" goes red. Verbatim output.

## Vacuous trap

Sending `kind: "receipt"` for an expense (the fuel prompt answers with volume and fuel kind, and
the mapping drops them - the test passes and the cloud never learned it was a parking ticket);
seeding the gateway answer in the test so that the request is never actually built.

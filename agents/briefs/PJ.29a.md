# PJ.29a - the invoice scan reaches the cloud gateway (the service half of PJ.29)

**Scenarios: J7 · the invoice in your hand, F4 · cloud fallback unavailable, J3 · the receipt
catches up with you.** Product owner, 2026-09-13: *every* kind of receipt goes to the gateway.
`PJ.29` shipped the expense half; this row is the service half it filed, on the same seam.

## The gap, pinned

- `ServiceInvoiceScanner.process` (`ios/App/Sources/ServiceEntry/ServiceInvoiceScanner.swift:22`)
  OCRs and splits the pages locally and never calls `/extract`. `ServiceInvoiceSession`
  (`ServiceInvoiceSession.swift:29`) owns the `DeferredRecognition` boundary but no gateway.
- The backend already accepts `kind: "invoice"` and `LlmPrompts` asks it for the header only -
  `vendor, total, date, currency` (`backend/src/Tankbook.Api/Llm/LlmPrompts.cs`). No backend
  change is expected; say so if you find one is needed.
- **The shape to mirror, line for line**: `ExpenseEntrySession.startGateway(image:hints:captureId:transport:onSavedAnswer:)`
  (`ExpenseEntrySession.swift:165-190`) - a session-owned `GatewayScanSession`, the fill-up guards
  (`allowsServerBacked`, a transport, a JPEG rendition), `pendingGatewayExtraction` +
  `gatewayRevision`, `markSaved` replay for a gateway started after the save;
  `CaptureExpenseScan.startExpenseGatewayIfAvailable` (the start, after the local outcome);
  `ExpenseEntryGateway.swift` (the sheet half: `applyPendingGatewayAnswer`, blank-AND-untouched
  through `GatewaySuggestionPolicy.fillableFields`); the proceed note and auth-expired card in
  `ExpenseEntryView.swift:100-105`; `ExpensePrefillBuilder.reading(fromGateway:)` (one decode →
  pre-fill + recognition).

**This brief's diagnosis is a hypothesis - confirm it before you change anything.**

## Build

1. `ServiceInvoiceSession` gains the gateway half of `ExpenseEntrySession` (same names, same
   one-shot consume, same `markSaved` replay). The image sent is the **first page** the document
   camera captured (an invoice may have several; the header is on the first - say this in a
   comment and in `docs/JOURNEYS.md` J7).
2. The service scan's start (where `ServiceInvoiceSession.start(work:...)` is called from the
   capture flow) fires the gateway with `kind: "invoice"`, hints = the car's home currency and the
   locale, after the local split has produced the outcome (F4: never wait on the gateway).
3. One core mapping `ServiceRecognitionBuilder.reading(fromGateway:)` (or the existing service
   recognition builder extended) produces the header pre-fill and a `ServiceRecognition` with
   `vendor, total, currency, date` and **empty `lineItems`** from one decode - the line items are
   the local split's and a cloud answer never replaces them.
4. The service sheet (`ServiceEntryView`) renders the proceed note and the auth-expired card,
   tracks touches on vendor / date / currency, and fills only blank AND untouched header fields
   on time; a late answer routes to `inbox.recordLateGatewayAnswer(.service(recognition))` where
   `serviceOffers` already offers the header fields (`GatewayInboxPolicy.swift:257`).
5. Docs: `docs/JOURNEYS.md` J7 (the sentence PJ.29 left: *"the cloud half is the invoice's own
   (PJ.29a)"* → what ships), F4 if it lists the kinds, `docs/EXTRACTION.md`, `docs/ERRORS.md` if
   the note gains a surface.

Out of scope: line items through the cloud (the split stays deterministic, J7); multi-page
stitching for the gateway; `PJ.18`.

## Environment axes

Signed-out (no transport → no call); backend down (form already open, note names the next step);
locale (RU note); Release (`RELEASE=1 scripts/gate.sh` - no `#if DEBUG` seam may carry the call).

## Tests

- **L1, fails today**: `ServiceGatewayMappingTests` (core) - a gateway invoice answer maps to a
  `ServiceRecognition` whose header agrees with the pre-fill and whose `lineItems` is empty; an
  unknown currency string is dropped. App-target `PJ29aServiceGatewayTests`: the request carries
  `kind == "invoice"` and the hints; a late answer routes to the inbox with the entry id.
  **Oracle**: the expense path's `PJ29ExpenseGatewayTests` / `ExpenseGatewayMappingTests`, which
  this must match line for line.
- **L4** `GatewayCaptureUITests` (extend, EN + RU, signed): a service scan with `-seedGatewayDelay`
  shows the proceed note on the service form, the late answer lands in the inbox and the open
  editor never changes; signed-out shows no note. `ServiceEntryUITests` stays green (21).
- Screenshots `PJ.29a-service-gateway-note` EN + RU, dark; capture lines added.

## Mutation - named

Skip the gateway start for the service scan (an early `return`); the L4 "service form shows the
proceed note" goes red. Verbatim output.

## Vacuous trap

Sending `kind: "receipt"` or `"expense"` for an invoice; letting a cloud answer's line items (there
are none - the prompt is header-only, but a model may still return some) replace the local split;
seeding the inbox so the request is never built.

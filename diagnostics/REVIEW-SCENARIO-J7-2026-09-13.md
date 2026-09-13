# REVIEW-SCENARIO run: J7 · The invoice in your hand - 2026-09-13 (re-walk after PJ.29a)

**Run id:** REVIEW-SCENARIO-J7-2026-09-13 · **Walked by:** the orchestrator · **Tree:** `d71309a9`

## Verdict

**IMPLEMENTED.** The prior walk (`REVIEW-SCENARIO-J7-2026-09-12`) found every promise MET; the
status line was cleared when `PJ.29a` rewrote one paragraph - the cloud half of the invoice scan,
which until today said "stays fuel-shaped and is PJ.29's". That paragraph re-walks to code below.
Nothing else in the journey text changed.

## Ticked rows found to be untrue

None. `PJ.29a` was verified by the orchestrator's own mutation before its tick (an early `return`
before the gateway start turned the service gateway L4 red).

## Promise-to-code map (the changed paragraph only)

| Promise (J7, "The cloud half is the invoice's own and now ships") | Status | Evidence |
|---|---|---|
| a service scan asks `/extract` with `kind: "invoice"` as soon as the local split has its outcome; the form is already open (F4) | MET | `CaptureServiceScan.serviceScanOutcome` starts the gateway after `ServiceInvoiceScanner.process` returns; `startServiceGatewayIfAvailable` (same file); `ServiceInvoiceSession.startGateway` with `kind: "invoice"`; `PJ29aServiceGatewayTests.testTheRequestCarriesTheInvoiceKindAndTheHints` |
| the image sent is the first page | MET | `startServiceGatewayIfAvailable(image: images.first)` in both the seeded and the real branch of `serviceScanOutcome` |
| the provider is asked for the header only; line items stay the local split's | MET | backend `LlmPrompts.AllowedFields("invoice")` = vendor, total, date, currency (unchanged from `PJ.29`); `ServiceRecognitionBuilder.reading(fromGateway:)` yields `lineItems: []` (`Extraction/ServiceGatewayReading.swift:65-82`); `ServiceGatewayMappingTests` 5/5 |
| both kinds run under the same guards, hints, rendition, 3 s budget | MET | `startServiceGatewayIfAvailable`: `allowsServerBacked`, `currentVehicle` home currency + locale hints; `ServiceInvoiceSession.startGateway`: `GatewayScanStarter.makeTransport()` (nil for a guest), `GatewayRendition.jpegData`; `testASignedOutServiceScanShowsNoNote` |
| a within-budget answer fills only blank AND untouched vendor, date, currency | MET | `ServiceEntryGateway.applyGatewayAnswer` via `GatewaySuggestionPolicy.fillableFields` (`:29-35`); touch tracking on the service sheet; `testALateServiceAnswerDoesNotChangeTheOpenEditor` |
| the total is offered only through the inbox | MET | `applyGatewayAnswer` has no `.total` branch (the header total derives from the line items); `serviceOffers` offers `.total` (`GatewayInboxPolicy.swift`) |
| a late answer becomes the inbox item through the one policy | MET | `onSavedAnswer` → `inbox.recordLateGatewayAnswer(.service(...))`; `PJ29aServiceGatewayTests.testALateInvoiceAnswerIsRoutedToTheInboxThroughTheOnePolicy`; L4 `testAServiceScanReachesTheGatewayAndALateAnswerLandsInTheInbox` EN + RU |
| one decode feeds the form and the inbox | MET | `ServiceRecognitionBuilder.reading(fromGateway:)` returns prefill + recognition together |
| the proceed note and the auth-expired card on the service form | MET | `ServiceEntryView.swift:109-114`; `testADeadSessionShowsTheSignInNextStepOnTheServiceForm`; frames `PJ.29a-service-gateway-note` EN + RU opened by the orchestrator |

## Sequence trace (one user, a two-page invoice, signed in, cloud answer late)

1. Document camera returns two pages → `scanServiceInvoice` stages them (`RV.243`), starts the
   local split, opens the form after the cover beat.
2. The split lands → the form shows vendor, lines, header total; in the same step the gateway
   request starts with page one and `kind: "invoice"`; the proceed note appears.
3. The user edits a line, saves → `markSaved`; the record and its pages persist.
4. The cloud answer lands → `reading(fromGateway:)` → `.service(recognition)` with header fields
   and no line items → `serviceOffers` compares vendor / total / currency / date → the inbox item.
5. "Leave it as it is" is the default; a tick applies exactly that field; the line items the user
   edited are never touched.

Every fact is carried: the pages from the shutter to the record, the header from the cloud to the
inbox, the line items from the local split to the record and nowhere else.

## Proposed rows

None. `PJ.18` (the unreachable hint, `[v2]`) stands as before.

## Not settled

- Nothing new. The "first page only" rule is stated in the journey; a multi-page invoice whose
  header is on page two gets no cloud header - by design, and the local split still runs on every
  page.

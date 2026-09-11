# RV.215 - a service or expense recognition still cannot arrive late

**Scenarios: J3 · the receipt catches up with you, J7, J7b.** The deferral half `RV.201` filed with
the seam named. **Last in J3**, after the four briefs before it, because it builds on the Inbox card
they finish.

## The gap

`RV.201` generalised the inbox MERGE: `GatewayInboxPolicy.item(recognition:entry:)` accepts a
`.service` or `.expense` recognition, `AppInbox.resolve` writes the right entity, the card offers
per-field ticks. **Nothing produces such an item in production**: `acceptExpenseScan` awaits
`CapturePipeline.process` inline (`CaptureExpenseScan.swift:32`), and `ServiceInvoiceScanner.process`
awaits OCR plus `InvoiceSplitter` before the form opens. The only items of those kinds today come
from test seeds.

## What to build - the device-local deferral, through the ONE policy

The scan returns what it has, the form opens, and a completed read that arrives **after the user
saved** becomes an inbox item through the SAME `GatewayInboxPolicy.item` the fuel path and the outbox
drain already call - **never a second producer that re-derives the boundary** (`AppInbox.
recordLateGatewayAnswer` is the fuel-shaped precedent; generalise it, do not copy it). Look at how
the fuel path decides "the user already saved, so this is late" (`markSaved()` and the session) and
give the service and expense sessions the same state.

**The cloud half is `PJ.29`'s and is OUT OF SCOPE**: the outbox wire carries `GatewayExtraction`
only. This row is the in-process late answer; do not touch `docs/API.md`.

**A read that finishes BEFORE the save is not an inbox item** - it pre-fills the open form, as today.
The boundary is the save, and the test must exercise both sides of it.

## Tests

- **L1, and it FAILS TODAY**: a service recognition completing after `markSaved()` produces an
  inbox item for that entry through `GatewayInboxPolicy.item`; one completing before it does not.
- **L1**: the same for an expense.
- **L1**: a late answer for an entry deleted in between is handled, not crashed (the `RV.201`
  behaviour, now reachable from a real producer).
- **L4 `InboxUITests` EN + RU**: an expense scan whose read is delayed (use the existing seed
  mechanism to delay, say what you added) - save, then the bell shows the item, then decline leaves
  the entry byte-identical.

## Mutation - named

Route the late service answer through a direct `insert` instead of `GatewayInboxPolicy.item`; the
"through the one policy" L1 goes red (assert on the policy's call, or on the `shouldOffer` boundary
being honoured - a late answer that merely AGREES must produce no item, and a direct insert would).

## Vacuous traps

- A second producer beside `recordLateGatewayAnswer`.
- Treating every completed read as late.
- Testing with a seeded item rather than a real delayed pipeline.

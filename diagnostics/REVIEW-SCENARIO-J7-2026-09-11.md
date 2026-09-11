# REVIEW-SCENARIO J7 – 2026-09-11

**Verdict: NOT IMPLEMENTED** – open rows PJ.29, PJ.60, RV.204, RV.212, RV.213, RV.214, RV.215, RV.216 name this scenario.

## Ticked rows found untrue

None. Every ticked row was walked against the code and holds:

| Row | Claim | Evidence |
|---|---|---|
| PJ.22 | lifetime editor + offer anchored at the record | `ServiceItemLifetimeFields.swift:10-86`; `ReminderOffer.propose` `ReminderOffer.swift:209-256`; anchor `ReminderOffer.reminder` `:309-337`; edit-path offer gated on `serviceLifetimeChanged` `EditEntryView.swift:399-406` |
| PJ.23 | edit line items (title/category/cost), `.other`→fixed preserves every field | `EditEntryServiceItemRow` `EditEntryNonFillView.swift:377-463`; `ServiceEntryItemDraft.serviceItem` keeps `partNumber ?? original?.partNumber` `ServiceEntryFormState.swift:97-99` |
| PJ.62 | `sourceEntryId` single link, `proposedReminderId` gone | no `proposedReminderId` in `ServiceEntryDraft.build` `ServiceEntryDraft.swift:111-123`; `ReminderOffer` writes `sourceEntryId` only `ReminderOffer.swift:308-337` |
| RV.198 | add + delete line items, delete-last legal | `EditEntryNonFillView.swift:151-167`; delete-last comment `:153-161` |
| RV.199 | line sum stated beside Amount, amber on mismatch, one summation | `EditEntryNonFillView.swift:268-336`; `ServiceItemSum.costSum()` `ServiceItemSum.swift:65-80`; create header same sum `ServiceEntryView.swift:156-171` |
| RV.201 | inbox merge generalised over kind | `GatewayInboxPolicy.offers/merged` switch over `.service`/`.expense` `GatewayInboxPolicy.swift:152-185`; `serviceOffers` `:239-260`; `mergedService` `:326-364` |
| RV.202 | non-fill three-way receipt branch, Add receipt | `EditEntryNonFillView.swift:86-103` |

## Promise-to-code map

| Journey promise | Status | Evidence / owner |
|---|---|---|
| Manual door: "Type it" → menu → Service opens empty `ServiceEntryView`, odometer pre-filled, editable | **MET** | `HomeView.swift:403-441` (button + `typeItMenu`); `ScannedFillUpSheet.swift:90-96` `.service`→`.serviceEntry`; `Destinations.swift:86`; pre-fill `ServiceEntryView.swift:273-275`, editable odometer card `:91-99` |
| Scan invoice (document camera, multi-page) → deterministic parser splits line items, categorised, with attachments | **MET** | Service mode shutter opens document camera `CaptureView.swift:625-632`; `ServiceInvoiceScanner.process` `ServiceInvoiceScanner.swift:22-48`; splitter `InvoiceSplitter.swift:69-99`; pages persisted as attachments `:65-82` |
| – opt-in cloud LLM (tier 3) as the only model-assisted path | **MISSING / deferred** | no `/extract` service path exists; **PJ.29** (open, [v1.x]) owns it |
| app proposes the next reminder from item lifetimes | **PARTIAL** | core offer + lifetime-driven interval MET (`ReminderOffer.swift:229-256`); but the lifetime is only settable on EDIT, not CREATE – **RV.213** (open) owns the create half |
| P3 addition: insurance (ОСАГО) first-class reminder type | **MET** | `ReminderCategory.insurance` `Enums.swift:248`; curated 12-month interval `ReminderOffer.swift:101`; expense→insurance offer `:262-277`; completion maps it `ReminderCompletion.swift:47`; form offers it `ReminderFormSections.swift:191` |
| Fallback: OCR can't split → one uncategorized item with full total | **PARTIAL** | lump sum built `InvoiceSplitter.swift:84-92`; but the item's title is `vendor ?? ""`, so a no-vendor invoice yields an untitled item and `hasTitledItem` blocks Save – **RV.214** (open) owns the gate |
| Fallback: user renames/splits by hand (lump sum "Annual service · 148 €") | **MET** | rename `EditEntryServiceItemRow` `EditEntryNonFillView.swift:384-408`; split = add/delete `:151-167` |
| Fallback: no invoice (DIY) → manual line items, parts from shelf (J7b) | **MET** | manual door (above); `ServiceEntryPartsSection` + `PartsShelf.suggested` `ServiceEntryView.swift:116-122, 192-197` |
| Fallback: unknown category → `.other` free text, promoted later without data loss | **MET** | category menu offers "Other" `ServiceEntrySections.swift:396-420`; `.other` free-text field `:376-381`; promotion preserves every field `ServiceEntryFormState.swift:97-99` |
| Odometer: pre-filled from last known; required only when km-lifetime or tire set | **PARTIAL** | rule MET `ServiceEntryDraft.requiresOdometer` `:76-78`; pre-fill `ServiceEntryView.swift:273-275`. But the rule is enforced on CREATE only – **RV.212** (open) names the edit door; the create door itself has no lifetime field – **RV.213** (open) |
| The record names itself (RV.187) | **MET** | `EntryTitle.serviceTitle` vendor→first named item+count→category→"Service" `EntryTitle.swift:58-68` |
| [v1.x] Editing the work (PJ.23 / RV.198 / PJ.22) | **MET** | see ticked-rows table |
| [v1.x] Total and lines agree (RV.199) | **MET** | see ticked-rows table |
| The receipt can be given (RV.202) | **MET** | see ticked-rows table; photo-write failure degrades, not blocks `EditEntryView.swift:366-382` |
| – one screen, two contracts for the same photo-write failure (fill-up blocks vs non-fill degrades) | **MISSING (consistency)** | **RV.204** (open) owns it; both report, neither silent |
| A late invoice reading reaches the same inbox (RV.201) | **PARTIAL** | merge generalised MET (`GatewayInboxPolicy`, above). Producing side is synchronous – a service scan awaits OCR inline `ServiceInvoiceScanner.swift:22-27`, so no late service reading can be produced today. **RV.215** (open) owns the deferral |
| – Inbox labels a service line item "Row 0" | **MISSING** | `FieldLabel.swift:28` renders `n` verbatim, not `n+1`. **RV.216** (open) owns it |

## Sequence trace – one user doing the whole thing

1. **Home → "Type it" chevron → "Service"** → `ServiceEntryView`, odometer pre-filled from last known, editable. ✓ (`HomeView.swift:419-425`, `ServiceEntryView.swift:273-275`)
2. **(or) Capture → Service mode → shutter → document camera → multi-page → split → prefill.** ✓ reachable in Release, no `#if DEBUG` gate (`CaptureView.swift:615-632`, `ServiceInvoiceScanner.swift:22-48`).
3. **Split fails → lump sum.** Item titled with the vendor. If the vendor read, Save works; the record is a titled lump sum. ✓. **If the vendor did not read, the single item is untitled and Save stays disabled with "Add a line item to save"** – the fact "the invoice has a total" stops being carried here, and the hint names a step the user may already believe they have done. Owned by **RV.214**.
4. **Save → post-save offer.** Fires on every service save at create (`ServiceEntryView.swift:423-425`), but the lifetime interval the offer promises can only be stated AFTER the first save (edit), because the create card has no lifetime field. A create-time offer is therefore category-default-only (oil/insurance); a brakes/battery/etc. service offers nothing until the user reopens it, sets a lifetime, and saves again. The fact "this item has a 30 000 km life" is carried only through the edit door. Owned by **RV.213** (with **RV.212** for the odometer rule on that same edit door).
5. **Log names the record** from vendor → first named item → category. ✓ (`EntryTitle.swift:58-68`)
6. **Edit: add/delete/rename items, set lifetime, watch line sum vs Amount, attach receipt.** All ✓; the offer re-fires here when the lifetime changed (`EditEntryView.swift:399-406`).
7. **Late reading → inbox.** The merge is ready and one function over kind, but no service/expense recognition is produced late, so step 7 is unreachable except by a test seed. Owned by **RV.215**; and once reachable, its line items render "Row 0" – owned by **RV.216**.

**Where a fact stops being carried:** step 3's total (no-vendor lump sum) and step 4's lifetime (create has no editor). Both are the PJ.23 shape – the screen is right, the value dies between doors – and both are already filed, not re-filed here.

## Proposed rows (unowned findings only)

| Row (proposed) | Deliverable | Closes journey stage | User-facing consequence today | Severity | Check | Scenario |
|---|---|---|---|---|---|---|
| *(proposed)* `dateFromInvoice` caption survives a manual date edit | Clear the "· invoice" provenance caption when the user changes the date after a scan | J7 scan-invoice stage, Date provenance | A user who edits the scanned date still sees "· invoice", which claims the date came from the invoice when it no longer did (hard rule 13: once changed, it is theirs) | polish | L4 `ServiceEntryUITests`: scan seed, change date, caption gone; EN+RU | J7 |

No other unowned promise found. Every other gap is carried by an existing open row and is cited above, not re-filed.

## Could not settle

- **Version-scope marker drift:** J7's body is unmarked (v1), yet its sentence "opt-in cloud LLM (tier 3) as the only model-assisted path" is filed as `PJ.29` `[v1.x]`. The deterministic rules-only parser is the v1 deliverable and is built; the cloud path is deferred. This is a doc/backlog reconciliation (mark the sentence, or re-scope the row), not a code gap – left for the owning docs, not filed as a row here.
- **`PJ.60` (Expense.recurrence dead) and `PJ.61` (ServiceItem.partNumber dead)** name J7b/J7d, not J7 proper, but sit inside the same "service visit" seam; they are cited as the brief lists them and their seam is the v2 parts shelf / recurring-expense owner, not this journey's.

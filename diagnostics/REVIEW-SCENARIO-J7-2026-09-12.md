# REVIEW-SCENARIO J7 – 2026-09-12 (second walk)

**Verdict: IMPLEMENTED.** Every v1 promise is MET or reasoned N/A (the cloud-LLM
clause is `PJ.29` `[v1.x]`, a tracked deferral; the deterministic parser is the v1
deliverable and is built). No ticked row is untrue. The four open rows that still
name J7 (`RV.245` hygiene, `RV.235` polish, `RV.246` which is J7b's, `PJ.29` v1.x)
do not block.

## Ticked rows found untrue

None. Every ticked row was walked against the code and holds.

| Row | Claim | Evidence |
|---|---|---|
| RV.212 | one odometer rule on both doors; km lifetime with blank odometer saves, mounted set refuses | `ServiceEntryDraft.saveReadiness` `ServiceEntryDraft.swift:96-99`; `serviceSaveReadiness` `:110-116`; create door `ServiceEntryFormState.saveReadiness` `ServiceEntryFormState.swift:210-222`; edit door calls the same core fn |
| RV.213 | create card renders the SAME lifetime editor; offer fires at first save | `ServiceEntryItemCard` renders `ServiceItemLifetimeFields` `ServiceEntrySections.swift:383-388`; same view in edit row `EditEntryNonFillView.swift:437`; offer staged at create save `ServiceEntryView.swift:441` |
| RV.214 | vendor-only, category-named, or any line saves; wholly blank refused; hint names the step | `serviceSaveReadiness` `ServiceEntryDraft.swift:110-116`; hint `ServiceEntryFormState.saveHint` `:228-239` |
| RV.215 | service/expense read deferrable; late answer routes through ONE policy | `ServiceInvoiceSession.start(stagedPages:...)` `ServiceInvoiceSession.swift:60-66`; `CaptureView.scanServiceInvoice` `CaptureView.swift:631-651`; inbox route `:644-646`; merge `GatewayInboxPolicy.serviceOffers` `:239-260` |
| RV.224 | manual date edit clears the `· invoice` caption | `dateBinding` → `form.userChangedDate(to:)` `ServiceEntryView.swift:213-218`; `userChangedDate` clears `dateFromInvoice` `ServiceEntryFormState.swift:279-283` |
| RV.230 | non-fill edit renders the shared F9a warn + Fix | `EditEntryNonFillView` params `odometerConflict`/`neighbourhood` `:23-31`; `F9aWarningRow` `EditEntryNonFillView+Odometer.swift:18`; single `OdometerConflict.from` `EditEntryNonFillConflict.swift:19` |
| RV.244 | invoice date reaches the late service reading as a date | `ServiceRecognition.date` set from `split.date` `ServiceInvoiceScanner.swift:85`; `serviceOffers` date branch `GatewayInboxPolicy.swift:241` |
| PJ.61 | `partNumber` has a real writer on both doors, keyed to the row, clearable | `ServiceItemPartNumberField` `ServiceItemPartNumberField.swift:10-41`; create card `ServiceEntrySections.swift:388`; edit row `EditEntryNonFillView.swift:438`; draft carries its own value, not `original?.partNumber` `ServiceEntryFormState.swift:77-93` |
| RV.204 | photo-write failure degrades on every entry kind; one seam | `attachHeldReceiptToFill` `EditEntryView+FillReceiptSave.swift:27-59`; non-fill `EditEntryView+NonFillSave.swift:116`; both call `attemptReceiptPhotoWrite` |
| RV.201 | inbox merge generalised over kind, one function | `GatewayInboxPolicy.offers`/`merged` switch over `.fuel`/`.service`/`.expense` `:152-185` |
| RV.243 | pages persist at scan start; late read only offers values | `ServiceInvoiceScanner.stagePages` `:61-66`; `enrichPages` updates in place `:126-139` |

## Promise-to-code map

| Journey promise | Status | Evidence / owner |
|---|---|---|
| Manual door: "Type it" → menu → Service opens `ServiceEntryView`, odometer pre-filled, editable | **MET** | `typeItControl` + `typeItMenu` `HomeView.swift:422-460`; pre-fill `ServiceEntryView.swift:287-289` |
| Scan invoice (document camera, multi-page) → deterministic parser splits, categorised, with attachments | **MET** | shutter opens document camera in Service mode `CaptureView.swift:656-660`; `scanServiceInvoice` `:631-651`; `ServiceInvoiceScanner.process` `:22-54`; pages persisted `:61-66` |
| – opt-in cloud LLM (tier 3) as the only model-assisted path | **N/A (v1.x)** | no `/extract` service path; `PJ.29` `[v1.x]` owns it with a written escape hatch ("invoices stay rules-only"); deterministic rules-only parser is the v1 deliverable and is complete |
| app proposes the next reminder from item lifetimes | **MET** | `ReminderOffer.propose(afterService:)` `ReminderOffer.swift:209-256`; lifetime editor on both doors (RV.213 above); anchor at record `:309-337` |
| P3 addition: insurance (ОСАГО) first-class reminder type | **MET** | `.insurance` curated 12-month interval `ReminderOffer.swift:101`; `propose(afterExpense:)` `:262-277`; `ReminderCategory.insurance` |
| Fallback: OCR can't split → one uncategorized item with the full total | **MET** | lump sum saves (RV.214): `serviceSaveReadiness` accepts a line even untitled `ServiceEntryDraft.swift:110-116` |
| Fallback: user renames/splits by hand | **MET** | `EditEntryServiceItemRow` `EditEntryNonFillView.swift:406-493`; add/delete `:220-222` |
| Fallback: no invoice (DIY) → manual line items, parts from shelf (J7b) | **MET** | `ServiceEntryPartsSection` + `PartsShelf.suggested` `ServiceEntryView.swift:113-119, 196-201` |
| Fallback: unknown category → `.other` free text, promoted later without data loss | **MET** | category menu + `otherTextBinding` `ServiceEntrySections.swift:405-451`; `serviceItem(homeCurrency:)` preserves every field `ServiceEntryFormState.swift:77-93` |
| Odometer: pre-filled; anchors km lifetime and tire set; km lifetime with blank odometer saves, offer names the missing odometer | **MET** | `requiresOdometer` (advisory) `ServiceEntryDraft.swift:81-87`; `saveReadiness` (gate) `:96-99`; card warning names the step `ServiceEntrySections.swift:308-326` |
| The record names itself (RV.187) | **MET** | `EntryTitle.serviceTitle` vendor→first named+count→category→"Service" `EntryTitle.swift:58-68` |
| The create gate accepts what the Log can name (RV.214) | **MET** | `serviceSaveReadiness` `ServiceEntryDraft.swift:110-116`; hint `ServiceEntryFormState.swift:228-239` |
| [v1.x] Editing the work (PJ.23 / RV.198 / PJ.22 / PJ.61) | **MET** | see ticked-rows table |
| [v1.x] Total and lines agree (RV.199) | **MET** | `lineSumBlock` `EditEntryNonFillView.swift:323-391`; shared `lineSum(homeCurrency:)` `ServiceEntryFormState.swift:117-119` |
| The receipt can be given (RV.202), fill-up edit obeys the same degrade contract (RV.204) | **MET** | `receiptCard` three-way branch `EditEntryNonFillView.swift:133-158`; `attachHeldReceiptToFill` `EditEntryView+FillReceiptSave.swift:27-59` |
| A late invoice reading reaches the same inbox (RV.201); producing side deferrable (RV.215); pages persisted at scan start (RV.243); date offered (RV.244) | **MET** | `GatewayInboxPolicy` service branch `:156-162, 239-260`; `ServiceInvoiceSession` deferral `:41-72`; `stagePages` `ServiceInvoiceScanner.swift:61-66`; `date` carried `:85` |

## Sequence trace – one user doing the whole thing

1. **Home → "Type it" → menu → "Service"** → `ServiceEntryView`, odometer pre-filled from last known, editable. ✓ (`HomeView.swift:422-460`, `ServiceEntryView.swift:287-289`)
2. **(or) Capture → Service mode → shutter → document camera → multi-page → stage pages → defer read → open form.** ✓ reachable in Release, no `#if DEBUG` gate (`CaptureView.swift:631-651`, `ServiceInvoiceScanner.swift:22-66`).
3. **Split fails → lump sum.** Titled with the vendor; a vendor-less lump sum now saves (RV.214) and reads as its category. ✓ (`serviceSaveReadiness`, `EntryTitle.swift:58-68`)
4. **Save → post-save offer.** The lifetime stated on the CREATE card (RV.213) drives `ReminderOffer.propose` at the first save; the offer is anchored at the record, never today. ✓ (`ServiceEntryView.swift:441`, `ReminderOffer.swift:209-256`)
5. **Log names the record** vendor → first named item + count → category. ✓ (`EntryTitle.swift:58-68`)
6. **Edit: rename/split, set lifetime/part number, watch line sum vs Amount (amber on mismatch), attach receipt, F9a warn + Fix on conflict.** ✓ (`EditEntryNonFillView.swift:82-85, 206-223, 331-391`; `EditEntryNonFillView+Odometer.swift:18`)
7. **Late read → inbox.** The read is deferred; a read that finishes after save routes through `GatewayInboxPolicy.item(.service(...))` and offers vendor/lines/total/date per field. ✓ (`CaptureView.swift:644-646`, `GatewayInboxPolicy.swift:239-260, 326-364`)

**Where a fact stops being carried:** none found this walk. The two facts the first walk flagged (step 3's no-vendor total, step 4's create-time lifetime) are now carried through the same doors by RV.214 and RV.213.

## Proposed rows

None. No unowned v1 promise was found, and the four open rows that name J7 are
cited, not re-filed: `RV.245` (staged pages orphaned on cancel – hygiene, not
user-visible), `RV.235` (Fix chip under the save bar – polish, the chip is
reachable by scroll), `RV.246` (late expense read date – J7b, not J7), `PJ.29`
(cloud LLM for invoices – `[v1.x]`).

## Could not settle

- **Version-scope marker drift (carried from the first walk).** J7's scan sentence
  ("with the opt-in cloud LLM (tier 3) as the only model-assisted path") is
  unmarked v1, while the row that owns it (`PJ.29`) is `[v1.x]`. It does not block
  v1: the deferral is tracked and the deterministic parser is the v1 deliverable.
  Resolution is a doc reconciliation (mark the clause, or re-scope the row) in
  `docs/JOURNEYS.md`/`docs/TASKS.md` – not a code gap, and outside this run's two
  write targets.
- **"Titled or categorised" vs "any line".** `docs/JOURNEYS.md:288` writes "a
  single line item (titled or categorised)" while `serviceSaveReadiness`
  (`ServiceEntryDraft.swift:110-116`) accepts any non-empty `items` list, so a
  user who taps "Add line item" and saves it empty produces a record whose only
  content is a blank line, named "Other" in the Log. This is the boundary of
  RV.214's decided rule (".empty when there is no vendor and no line"), which is
  internally consistent and mutation-tested; the journey prose is the looser
  summary. Noted, not filed – a product nuance, not a broken promise.

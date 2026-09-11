# REVIEW-SCENARIO J7b - 2026-09-11

- **Scenario:** `J7b` - Parts, tires, consumables (`docs/JOURNEYS.md` line 307)
- **Run id:** REVIEW-SCENARIO-J7b-2026-09-11
- **Rows that named it:** closed PJ.25 PJ.26 PJ.27 PJ.28 RV.200 RV.201 RV.202 RV.206; open PJ.50 PJ.60 PJ.61 RV.205 RV.209 RV.214 RV.215
- **Adjacent:** J7 (service invoice), J7c (reminder lifecycle), J7d (reminder birth), J6 (totals/trends)

## Verdict

**NOT IMPLEMENTED** - one journey promise (the late shop-receipt reading, JOURNEYS.md line 344) has no producer path; its consumer half is shipped but the producer is synchronous. That gap is owned by `RV.215`. The remaining open rows (`RV.214`, `RV.209`, `PJ.60`, `PJ.61`, `RV.205`) each carry one real defect; none is re-filed here.

## Ticked rows found untrue

None of the eight ticked rows is untrue when the code is walked - each is present and reachable. One caveat, stated rather than hidden: **the journey text over-credits `RV.201`.** Line 344-349 describes *"a late shop-receipt reading reaches the inbox ... amount and category ... per-field ticks"* as if it ships. What `RV.201` actually shipped is the **consumer** half only - `GatewayInboxPolicy.item(recognition:entry:)` and `AppInbox.resolve` generalised over `.service`/`.expense` (`RV201InboxKindMergeTests`). The **producer** half (a deferred expense/service recognition) does not exist: `acceptExpenseScan` awaits `CapturePipeline.process` inline (`CaptureExpenseScan.swift:68-73`). `RV.215` owns the producer and is open. The promise is therefore PARTIAL, not MET - a `PJ.23`-shaped over-claim in the journey prose, cited to a row that only did half of it.

## Promise-to-code map

### Stages

| Promise (journey text) | State | Evidence |
|---|---|---|
| Purchase: scan order confirmation → `Expense .parts` | MET | `acceptExpenseScan` (`CaptureExpenseScan.swift:32-58`); `.parts` is an `entryCases` member (`ExpenseEntryView.swift:11`) |
| Purchase: odometer not asked | MET | Expense form has no odometer field; `storedExpense` writes `odometer: nil` (`ExpenseEntryView.swift:203`) |
| Purchase: cost counts in totals from day one | MET | a normal `Expense` with `money`; no gating |
| Shelf: visible under Garage → "Parts shelf", "on shelf" state | MET | `Route.partsShelf` (`Routes.swift:61`), pushed from `VehicleDetailView.swift:211`; badge `PartsShelfRow.onShelfBadge` (`PartsShelfView.swift:123-136`) |
| Shelf: "next matching service suggests them" | MET | `PartsShelf.suggested` (`PartsShelf.swift:86-97`) wired at `ServiceEntryView.swift:196` |
| Install: offers shelf parts "Install oil filter from Mar 3?" → link, don't re-price | MET | `ServiceEntryPartsSection.linkRow` (`ServiceEntryPartsSection.swift:63-81`), `L10n.installPart` |
| Install: cost counted once, no double counting | MET | `PartsShelf.link` moves link never money (`PartsShelf.swift:45-53`); both halves commit in one transaction (`Repository+PartsLinking.swift:14-32`, `ServiceEntryView.swift:412`) |
| Tires: a tire purchase becomes a TireSet | MET | `TireSetPurchase.makeSet` (`TireSetPurchase.swift:37-46`); "Make this a tire set" (`TireSetSections.swift:95`), wired `EditEntryView.swift:238-254`, reachable in Release (`EditEntryNonFillView.swift:55`) |
| Tires: each seasonal swap marks which set went on | MET | `.tires` mode, `saveEnabled` requires `tireSetId` (`ServiceEntryView.swift:211-212`) |
| Tires: set mileage derives from odometer spans | MET | `TireMileage.mileage` (`TireMileage.swift:27-70`), shown on `TireSetsView.swift:31-38` |
| Tires: swap reminder each season | MET | see "swap reminder" row below |

### Swap reminder born from the mount (line 317-323)

| Promise | State | Evidence |
|---|---|---|
| mount (`tireSetId != nil`) proposes `.tires` anchored at mount date, recurring 6 months | MET | `ReminderOffer.propose(afterService:tireSetName:liveReminders:)` mount branch (`ReminderOffer.swift:212-226`), `seasonalSwapMonths = 6` (`:116`) |
| suppressed when a live `.tires` reminder exists | MET | `isSuppressed` (`ReminderOffer.swift:175-183`) |
| anchored at the record, never today | MET | `reminder(accepting:)` builds `dueDate = record.date + months` (`ReminderOffer.swift:313-337`) |
| Dismiss / Delete stop the season | N/A | generic J7c reminder lifecycle; not a J7b-specific promise |

### Fallbacks (line 325)

| Promise | State | Evidence |
|---|---|---|
| part logged without a receipt → plain manual expense, one field + price | MET | `canSave = amountDecimal != nil` (`ExpenseEntryView.swift:47`); `.parts` manual via category chooser |
| user skips shelf, types parts inside service records | MET | `.parts` is a `ServiceCategory` (`ServiceEntrySections.swift:20`, `L10n+EntryTitles.swift:21`) |
| tire mileage without logged swaps → shown as "–", never estimated | MET | `TireSetRowFormat.mileageText` returns `"–"` on nil (`TireSetRowFormat.swift:18-21`) |

### Expense capture door (line 327-342)

| Promise | State | Evidence |
|---|---|---|
| pre-fills only total / currency / date | MET | `ExpensePrefillBuilder.prefill` maps exactly three fields (`ExpensePrefill.swift:48-55`) |
| reads the kind, offers category pre-selection, editable | MET | `ExpenseCategoryInference.infer` (`ExpenseCategoryInference.swift:36`), wired `CaptureExpenseScan.swift:55`, applied `ExpenseEntryView.swift:353-357` |
| merchant is not guessed | MET | `ExpensePrefill` has no title member; no merchant field in the form |
| unrecognised kind → default, says nothing | MET | `pendingPreset` stays nil, form opens at `.accessory` |
| scan reading nothing → empty form, no error | MET | all-nil `ExpensePrefill()` renders the empty sheet (`ExpenseEntryView.swift:323-334`) |
| amount offered only when currency nil or home currency | MET | `currencyFitsForm` check (`ExpenseEntryView.swift:324-330`) |
| form saves on amount alone | MET | `canSave` (`ExpenseEntryView.swift:47`) |

### Late shop-receipt reading reaches the inbox (line 344-349)

| Promise | State | Evidence |
|---|---|---|
| inbox offers amount + category per-field ticks, differing offered never applied, one merge function | PARTIAL | consumer: `GatewayInboxPolicy.item/offers/merged` handle `.expense` (`AppInbox.swift:203`, `RV201InboxKindMergeTests`). producer: MISSING - no deferred expense recognition exists; `acceptExpenseScan` awaits inline (`CaptureExpenseScan.swift:68-73`) |

## Sequence trace

One user, one part, end to end:

1. **Buy** an oil filter online → Expense-mode scan → category inferred + total/date pre-fill → save on amount alone. Cost counts from day one. Carries: expense id, `.parts`, amount.
2. **Shelf** → Garage → car → Parts shelf → the part renders with "on shelf". Carries: expense id on shelf (`partsOnShelf` derives from `installedInServiceId == nil`).
3. **Install** → service entry → "Parts on your shelf" → "Install oil filter from Mar 3?" → Link → save commits `usedParts` + `installedInServiceId` in one transaction. Cost does not move.
4. **Tires** → buy a set → `.parts` expense → edit entry → "Make this a tire set" → TireSet. Mount → `.tires` mode → save → swap reminder (6 months, anchored at mount) → fires each season.
5. **Mileage** → derived from swap spans; "–" until a usable span exists.

The sequence holds through every step; no fact stops being carried across a boundary. **The one broken step is the inbox hand-off:** a shop receipt read that finishes *after* the expense saved never arrives, because `acceptExpenseScan` awaits the pipeline inline and no deferred producer exists. The inbox card that would render it is built and reachable only via a test seed or a future caller - the same "test seed or future in-process caller" shape `RV.215` describes.

## Handoffs

- → **J7** (service invoice): clean - service records are the shared entity; the parts section lives inside the same `ServiceEntryView`.
- → **J7c** (reminder lifecycle): clean - the swap reminder lands in the merged list; Dismiss/Delete are J7c's generic lifecycle.
- → **J7d** (reminder birth): clean - the mount offer rides the one `ReminderOffer` post-save path.
- → **J6** (totals): clean - the part is a normal `Expense`, cost counts from day one.

## Proposed rows / gaps - all owned, none re-filed

Every gap found maps to an existing open row. Grouped into the dispatch seams `docs/analysis/2026-09-11-process-and-backlog-review.md` names:

| Gap | Owner | Journey stage | User-facing consequence today | Severity | Check |
|---|---|---|---|---|---|
| No deferred expense/service recognition - the late-reading promise is unreachable | `RV.215` (open) | "late reading reaches the inbox" | a receipt read that finishes after save never offers its correction; the built inbox card is dead code for these kinds | gap | L1 (RV.215's own: late service + expense reading produce an item through `GatewayInboxPolicy.item`); L4 `InboxUITests` |
| Service create gate demands a titled line item; a vendor/category-nameable service blocks Save | `RV.214` (open) | Install (service record) | a scanned service with a readable vendor or category-named item cannot save | bug | L1 (named-but-untitled service saveable); L4 EN+RU |
| Two `Attachment` builders disagree on `extractionMeta` | `RV.209` (open) | Purchase (expense scan) / J3 | same photo through two doors records two accounts of what was read | gap | L1 (same extraction → same `extractionMeta` through both doors) |
| `Expense.recurrence` written nil, read nowhere | `PJ.60` (open) | Purchase (recurring expense, J7b/J7d) | none today - insurance reminder works via another path | gap | L1 (field gone or has a writer+reader) |
| `ServiceItem.partNumber` written nil, read nowhere | `PJ.61` (open) | Shelf (parts) | none today - field survives edit but cannot be set | gap | L1 (reasoned v2 exception naming PJ.52, or a writer) |
| Receipts corpus cannot measure expense-kind recognition (zero non-fuel images) | `RV.205` (open, `[!]`) | Expense capture door | RV.200's vocabulary verified against typed text, not photographs | gap | not agent work - needs photographs from the owner |
| Expense scan door title (PJ.50's merchant-line suggestion half) | unowned polish after `RV.206` | Expense capture door | none - journey explicitly says "merchant is not guessed" (line 333) | polish | close `PJ.50` against `RV.206`, re-file the suggestion only if wanted |

**Nothing unowned and load-bearing was found.** The single substantive finding is the `RV.201`/`RV.215` split described under "Ticked rows found untrue": the journey prose promises the whole flow, the shipped row is only its consumer half, and the producer half is `RV.215`. No new row is proposed - re-filing `RV.215` would duplicate it.

## Not settled

- **Success metrics** (line 351: shelf-suggested parts accepted >=40%, tire-swap reminders acted on >=70%): no telemetry/analytics exists in v1, so these are unmeasurable. Not treated as a code promise; flagging only so it is not mistaken for one.
- **`PJ.50` closure**: `RV.206` removed the title gate the row was written against. The analysis doc recommends closing `PJ.50` against `RV.206`; that is an owner decision, not one this read-only review makes.

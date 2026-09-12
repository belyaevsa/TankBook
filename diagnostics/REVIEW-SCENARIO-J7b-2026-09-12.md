# REVIEW-SCENARIO J7b - 2026-09-12

- **Scenario:** `J7b` - Parts, tires, consumables (`docs/JOURNEYS.md` line 349)
- **Run id:** REVIEW-SCENARIO-J7b-2026-09-12
- **Second walk.** First (`REVIEW-SCENARIO-J7b-2026-09-11.md`) was NOT IMPLEMENTED: one promise (the late shop-receipt reading) had a consumer but no producer. Since then shipped: `RV.206` `RV.214` `RV.215` `RV.243` `PJ.61`; `PJ.50` closed. Still open (cited, not re-filed): `PJ.60`, `RV.205`, `RV.246`.
- **Adjacent:** J7 (service invoice), J7c (reminder lifecycle), J7d (reminder birth), J6 (totals).

## Verdict

**IMPLEMENTED** - the one PARTIAL promise from the first walk (the late shop-receipt reading) is now end-to-end MET: the producer deferral (`RV.215`) and the photo-at-save (`RV.243`) shipped, and the three open rows each carry a decision or a measurement dependency, not a broken journey promise.

## Ticked rows found untrue

None. Every ticked row (`RV.206` `RV.214` `RV.215` `RV.243` `PJ.61`) is present and reachable when the code is walked:

- `RV.215` (producer deferral): `acceptExpenseScan` no longer awaits the pipeline - it calls `session.start(image:work:onAnswer:onSavedAnswer:)` and routes a late answer through `AppInbox.recordLateGatewayAnswer(.expense(...))` (`CaptureExpenseScan.swift:41-60`). Verified reachable, not seed-only.
- `RV.243` (photo at save): `ExpenseEntrySession.stageScan` stages the image before the read (`ExpenseEntrySession.swift:129-132`); `writeExpense` persists it from `scan` regardless of read state (`ExpenseEntrySave.swift:20-47`).
- `RV.214` (service gate): `saveEnabled` delegates to `form.saveReadiness == .ready` (`ServiceEntryView.swift:220-229`), the one core rule the edit door also calls.
- `RV.206` (expense gate): `canSave = amountDecimal != nil` (`ExpenseEntryView.swift:47`).
- `PJ.61` (`partNumber` writer): `ServiceItemPartNumberField` on both doors (`ServiceEntrySections.swift:388`, `EditEntryNonFillView.swift:438`); guard test `SchemaFieldWriterGuardNewEntityTests.theEditedPartNumberIsWrittenAndNotReported` pins it (`SchemaFieldWriterGuardNewEntityTests.swift:89-100`).

## Promise-to-code map

### Stages (journey line 352-357)

| Promise | State | Evidence |
|---|---|---|
| Purchase: scan order confirmation -> `Expense .parts` | MET | `acceptExpenseScan` (`CaptureExpenseScan.swift:41-60`); `.parts` is an `entryCases` member |
| Purchase: odometer not asked | MET | expense form has no odometer field; `storedExpense` writes `odometer: nil` |
| Purchase: cost counts in totals from day one | MET | a plain `Expense` with `money`; no gating |
| Shelf: visible under Garage -> "Parts shelf", "on shelf" state | MET | `Route.partsShelf`; badge `PartsShelfView.onShelfBadge` (`PartsShelfView.swift:123-136`) |
| Shelf: next matching service suggests them | MET | `PartsShelf.suggested` (`PartsShelf.swift:86-97`), wired in `ServiceEntryView` |
| Install: offers shelf parts, link don't re-price | MET | `ServiceEntryPartsSection.linkRow` (`ServiceEntryPartsSection.swift:63-81`), `L10n.installPart` |
| Install: cost counted once, no double counting | MET | `PartsShelf.link` moves the link never money (`PartsShelf.swift:45-53`); both halves commit in one transaction |
| Tires: a tire purchase becomes a TireSet | MET | `TireSetPurchase.makeSet` (`TireSetPurchase.swift:37-46`); "Make this a tire set" reachable in Release |
| Tires: each seasonal swap marks which set went on | MET | `.tires` mode requires `tireSetId` (`ServiceEntryView.swift:222`) |
| Tires: set mileage derives from odometer spans | MET | `TireMileage.mileage` (unchanged); shown via `TireSetRowFormat.mileageText` |
| Tires: swap reminder each season | MET | see swap-reminder rows below |

### Swap reminder born from the mount (journey line 359-365)

| Promise | State | Evidence |
|---|---|---|
| mount (`tireSetId != nil`) proposes `.tires` anchored at mount date, 6 months | MET | `ReminderOffer.propose(afterService:)` mount branch (`ReminderOffer.swift:209-226`), `seasonalSwapMonths = 6` (`ReminderOffer.swift:116`) |
| suppressed when a live `.tires` reminder exists | MET | `ReminderOffer.isSuppressed` (unchanged) |
| anchored at the record, never today | MET | `reminder(accepting:)` builds `dueDate = record.date + months` (unchanged) |
| Dismiss / Delete stop the season | N/A | generic J7c reminder lifecycle; not a J7b-specific promise |

### Fallbacks (journey line 367)

| Promise | State | Evidence |
|---|---|---|
| part logged without a receipt -> plain manual expense, one field + price | MET | `canSave = amountDecimal != nil` (`ExpenseEntryView.swift:47`); `.parts` manual via category chooser |
| user skips shelf, types parts inside service records | MET | `.parts` is a `ServiceCategory` (unchanged) |
| tire mileage without logged swaps -> "–", never estimated | MET | `TireSetRowFormat.mileageText` returns "–" on nil (`TireSetRowFormat.swift:18-21`) |

### Expense capture door (journey line 369-384)

| Promise | State | Evidence |
|---|---|---|
| pre-fills only total / currency / date | MET | `ExpensePrefillBuilder.prefill` maps exactly three fields (unchanged); applied `ExpenseEntryView.apply` (`ExpenseEntryView.swift:328-339`) |
| reads the kind, offers category pre-selection, editable | MET | `ExpenseCategoryInference.infer`, applied on load (`ExpenseEntryView.swift:358-361`) |
| merchant not guessed | MET | `ExpensePrefill` has no title member |
| unrecognised kind -> default, says nothing | MET | `pendingPreset` stays nil; form opens at `.accessory` |
| scan reading nothing -> empty form, no error | MET | all-nil `ExpensePrefill()` renders empty sheet; deferred read fills later via `onAnswer` (`ExpenseEntrySession.swift:89-94`) |
| amount offered only when currency nil or home currency | MET | `currencyFitsForm` (`ExpenseEntryView.swift:329-335`) |
| form saves on amount alone | MET | `canSave` (`ExpenseEntryView.swift:47`) |

### Late shop-receipt reading reaches the inbox (journey line 386-396)

| Promise | State | Evidence |
|---|---|---|
| inbox offers amount + category per-field ticks | MET | `expenseOffers` produces `.total` and `.category` (`GatewayInboxPolicy.swift:265-275`); `FieldRef` carries both (`Enums.swift:223-238`) |
| differing offered, never applied; one merge function | MET | `offers`/`merged` are ONE function over `InboxEntry` (`GatewayInboxPolicy.swift:152-185`); `mergedExpense` (`:366-385`); `resolve` writes back an `Expense` (`AppInbox.swift:219-228`) |
| producing side deferrable (RV.215) | MET | `acceptExpenseScan` defers (`CaptureExpenseScan.swift:41-60`); `DeferredRecognition` routes by save boundary (`ExpenseEntrySession.swift:83-114`); `recordLateGatewayAnswer(.expense(...))` (`AppInbox.swift:83-101`) |
| photograph persisted at save (RV.243) | MET | `stageScan` before the read (`ExpenseEntrySession.swift:129-132`); `writeExpense` writes from `scan` (`ExpenseEntrySave.swift:26-35`) |

## Sequence trace

One user, one part, end to end:

1. **Buy** an oil filter online -> Expense-mode scan -> category inferred + total/date pre-fill -> save on amount alone. Cost counts from day one. Carries: expense id, `.parts`, amount.
2. **Shelf** -> Garage -> car -> Parts shelf -> the part renders with "on shelf". Carries: expense id (`partsOnShelf` derives from `installedInServiceId == nil`).
3. **Install** -> service entry -> "Parts on your shelf" -> "Install oil filter from Mar 3?" -> Link -> save commits `usedParts` + `installedInServiceId` in one transaction. Cost does not move.
4. **Tires** -> buy a set -> `.parts` expense -> edit entry -> "Make this a tire set" -> TireSet. Mount -> `.tires` mode -> save -> swap reminder (6 months, anchored at mount) -> fires each season.
5. **Mileage** -> derived from swap spans; "–" until a usable span exists.
6. **Late read (the seam that failed last walk)** -> scan runs deferred -> form opens -> if the read beats the save it fills the form (`onAnswer`); if it loses, `recordLateGatewayAnswer(.expense(...))` -> `GatewayInboxPolicy.item` -> inbox card offering amount + category -> `resolve(.update(fields:))` -> `mergedExpense` writes only the ticked fields. The photograph is staged at scan start and written at save either way. No fact stops being carried across a boundary; the one producer the first walk found missing now exists and feeds the one policy.

The only residual sequence observation is `RV.246` (see below): because the read is now deferred, the receipt DATE is delivered only when the read beats the save; a read that loses can offer amount and category but not the date. That is a real "fact stops being carried" for the date alone, and it is filed, scoped "small; decide-or-do", and consistent with the journey text, which explicitly scopes the late reading to amount and category.

## Proposed rows / gaps

None new. Every gap found maps to an existing open row:

| Gap | Owner (existing row) | Journey stage | Consequence today | Severity | Notes |
|---|---|---|---|---|---|
| `Expense.recurrence` written nil, read nowhere | `PJ.60` (open) | purchase / J7d | none user-visible; insurance reminder works via a different path | decision | Owner decision pending; the J7b text never promises a recurring expense, so this does not block the journey. Treat as a decision, not a gap. |
| Corpus cannot measure expense-kind recognition (zero non-fuel images) | `RV.205` (open, `[!]`) | expense capture door | vocabulary verified against typed text, not photographs | measurement | N/A until the owner's photographs exist. |
| Late expense read can never offer a differing date | `RV.246` (open) | late reading | a deferred read that loses the save cannot correct the date | small; decide-or-do | Journey text scopes the late reading to amount + category, so this is an enhancement, not a broken promise. |
| Tyre-change advisory from forecast + law | `RV.124` (open, `[v1.1]`) | tires | none in v1 | N/A (v1.1) | Not part of the v1 J7b text ("swap reminder each season" is the reminder, which is met). |

**Nothing unowned and load-bearing.** The single substantive finding of the first walk (`RV.201`'s consumer-without-producer) is closed by `RV.215` + `RV.243`. No new row is proposed.

## Not settled

- **Duplicate task id in the backlog:** two rows share id `RV.243` - the shipped photo-survival row (`docs/TASKS.md` line 788, `[x]`) and a distinct open fuel-kind boilerplate defect (line 792, `[ ]`). `scripts/tasks-index.py` was not run here (read-only); this is a backlog-integrity defect outside J7b's scope but worth its own fix.
- **Success metrics** (journey line 398: shelf-suggested parts >=40%, tire-swap reminders >=70%): no telemetry exists in v1, unmeasurable; not a code promise.
- **`RV.246` and the date sequence** is the one honest residual: the deferral means the receipt date rides the pre-fill, which only lands when the read beats the save. Filed and consistent with the journey text's own scope, but the product owner may want to decide it sooner rather than later given `RV.244` already fixed the identical service-side date.

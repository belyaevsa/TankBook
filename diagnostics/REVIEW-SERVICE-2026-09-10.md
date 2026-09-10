# Service-loop walk: J7 / J7b / J7d / J7c — 2026-09-10 (new range `PJ.60+`)

*Read-only walk of the service loop against `docs/JOURNEYS.md`, run under
`agents/briefs/REVIEW-JOURNEYS.md` and narrowed by `agents/briefs/REVIEW-SERVICE-2026-09-10.md`.
Both passes applied: reachability AND sequence. A build agent (`RV.198`) is live in this checkout;
the tree carries its uncommitted work. One file created (this one).*

## Run history

| Run | Tree | Yield |
|---|---|---|
| 2026-08-29 | `93d2619` | 66 `PJ` rows |
| 2026-09-09 | `4cc801a` | 1 row (`PJ.55`) |
| 2026-09-10 (C+D) | `ea20655` | `PJ.58`, `PJ.59` (import/currency walk) |
| 2026-09-10 (service) | **this run** | `PJ.60`–`PJ.63`, 1 optional polish note; no ticked-but-untrue |

---

## 1. Ticked rows found untrue — the point of a re-run

**None.** Every `[x]` row in this loop holds up against the code. Checked honestly, not trusted:

- **`PJ.23` is ticked and is true.** The edit path really writes title / category / cost per item
  (`EditEntryView+NonFillSave.swift:59`), preserves the untouched `partNumber`/`lifetime`/rate
  snapshot by loading identity rather than position (`ServiceEntryFormState.swift:93-95`), and its
  own acceptance (`.other` → `.oil` keeps every `ServiceItem` field) is asserted in
  `PJ23ServiceItemEditTests`. Its edit-only fence is *honest* — the add/delete remainder is
  `RV.198`, already filed, not a hidden half.
- **`P3.1b` (invoice scan) is ticked and is true.** The Service-mode shutter is the document
  camera (`CaptureView.swift:672-678`), which hands pages to `ServiceInvoiceScanner.process`
  (`:605-610`), which OCRs per page, runs the deterministic `InvoiceSplitter`, persists pages and
  pre-fills items (`ServiceInvoiceScanner.swift:22-48`). It is reachable in Release — no
  `#if DEBUG` in the path.
- **`P3.2` (parts shelf + install linking), `P3.3` (tire sets + derived mileage), `P3.4`/`P3.5`
  (reminders), `PJ.25` (shelf reachable from Garage)** — all verified present in code; no claim
  outruns the implementation.

The nearest to a re-run finding is not a lying `[x]` but a **green guard over dead fields**:
`RV.196`'s field guard passes today while three fields in this loop are dead, because two of the
loop's types (`TireSet`, `ServiceItem`) are not under a `###` heading the guard scans. That is a
coverage blind spot, not a false claim — filed as `PJ.63`.

---

## 2. The sequence trace — one invoice, end to end, and where each fact stops

| # | Step | State today | Where the fact stops being carried |
|---|---|---|---|
| 1 | Scan invoice (multi-page) | **MET** | carried into items. `CaptureView.swift:605-610` → `ServiceInvoiceScanner.swift:22-48` → `InvoiceSplitter.split` |
| 2 | Manual door ("Type it" → Service) | **MET** | peer path, same `ServiceEntryView`. RV.61; `CaptureMode.swift` |
| 3 | Line items → title / category | **MET** | `ServiceItem.title/.category` (`ServiceItem.swift:9`); splitter fills, user edits |
| 4 | Items → costs | **MET** | `ServiceItem.cost: Money?`; exact `Decimal` parse (`ServiceEntryItemDraft.costDecimal`) |
| 5 | Costs → header total (create) | **MET** | `ServiceEntryDraft.total` = sum of item `amount`s (`ServiceEntryDraft.swift:92-96`); displayed via `ServiceEntryFormState.totalDecimal` |
| 6 | Costs → header total (edit) | **BROKEN** | edit's `money` is an independent Amount card, not the item sum (`EditEntryNonFillView.swift:195-224`, `EditEntryView+NonFillSave.swift:24`). **RV.199** |
| 7 | Header/item → "next reminder" (category) | **PARTIAL** | post-save offer fires for `.oil`/`.insurance` only (`ReminderOffer.swift:85-92,146-177`), writes `sourceEntryId`. **MET** for the category door (RV.77) |
| 8 | Item **lifetime** → "next reminder" | **STOPPED** | `ServiceItem.lifetime` has no editor, so it is always nil and never drives a proposal. **PJ.22** |
| 9 | Record → `proposedReminderId` | **STOPPED** | written `nil` at every construction (`ServiceEntryDraft.swift:122`, `ServiceEntryFormState.swift:271`, `ImportConversion.swift:110`); no reader. Dead field (RV.196 exception-list). |
| 10 | Parts shelf → part installed | **MET** | `.parts` Expense → shelf (`PartsShelf.onShelf`, `PartsShelfView`), link writes both `installedInServiceId` and `usedParts` (`PartsShelf.swift:45-53`), never re-prices |
| 11 | Part installed → shown on the service after save | **STOPPED** | `usedParts` is written and never read by any UI (`usedParts` appears in App sources only in seeds + form state); the "Linked" list is create-form-local state, lost on save. Polish note (§6) |
| 12 | `.parts` purchase → TireSet | **STOPPED** | `TireSet.purchaseExpenseId` written `nil` only (`TireSetDraft.swift:35`); no "make this a tire set". **PJ.26** |
| 13 | Tire set → mount (swap) | **MET** | `.tires` mode writes `ServiceRecord.tireSetId` (`ServiceEntryView.swift:83-87,195`); mileage derives (`TireMileage`, `TireSetsView` "–" when unknown) |
| 14 | Mount → seasonal swap reminder | **STOPPED** | mounting a set proposes nothing. **PJ.27** |
| 15 | Reminder fires → complete → "Log the cost?" → next cycle | **MET** | `ReminderLifecycle.complete` → `.done(entryId)` → next occurrence anchored at completion (`ReminderLifecycle.swift:191-229`); `ReminderCompleteSheet` Type amount / Skip |
| 16 | Complete → scan the invoice | **STOPPED** | completion sheet offers Type + Skip only (`ReminderCompleteSheet.swift:131-152`); no scan door. **PJ.24** |

The two facts that stop *invisibly* (a value written but never read, or a value never written while
a reader waits) are the same two shapes the dead-field rows already name: `proposedReminderId`
(step 9, writer missing) and `purchaseExpenseId` (step 12, writer missing) — plus `usedParts`
(step 11), the reverse: a **writer with no reader**.

---

## 3. Promise-to-row map (J7 / J7b / J7d / J7c)

Status vocabulary per the brief: MET (file:line), PARTIAL (what exists / what is missing), MISSING,
N/A (phase). Promises with **no row** are called out in the right column.

| Journey promise | Status | Evidence / row |
|---|---|---|
| **J7** manual door: Type it → Service, odometer pre-filled | MET | RV.61; `ServiceEntryView` odometer pre-fill (`ServiceEntryView.swift:256-258`) |
| **J7** multi-page invoice scan → deterministic line split | MET | `CaptureView.swift:605-610`, `ServiceInvoiceScanner.swift:22-48`, `InvoiceSplitter` |
| **J7** opt-in cloud LLM (tier 3) as the only model path | N/A (v1.x) | `PJ.29`; rules-only splitter ships |
| **J7** "app proposes the *next* reminder from item lifetimes" | PARTIAL | category offer exists (`ReminderOffer.swift:146-177`); **item-lifetime offer missing — `PJ.22`** |
| **J7** accept = the loop closes itself | PARTIAL | `ReminderOffer.reminder(accepting:)` writes `sourceEntryId` (`:230-258`); lifetime path absent (`PJ.22`) |
| **J7** fallback: "user **renames/splits** by hand" | PARTIAL | rename MET (`PJ.23`, shipped); **split was the no-row promise** → now `RV.198` (in flight) |
| **J7** lump sum with the bill attached is a good record | MET | `InvoiceSplitter` lump-sum outcome; `ServiceEntryDraft.isLumpSum` (`:101`) |
| **J7** unknown category → `.other`, promoted later without data loss | MET | `PJ.23` / `RV.195`; `EditEntryServiceItemRow` category menu |
| **J7** odometer required only for km lifetime / tire mount | MET (rule) | `ServiceEntryDraft.requiresOdometer` (`:76-78`); the km-lifetime *editor* that triggers it is `PJ.22` |
| **J7** record names itself (vendor → item → category) | MET | RV.187; one title function across surfaces |
| **J7b** scan order → Expense `.parts`, no odometer asked, cost counts day one | MET | `ExpenseEntryView` (no odometer row); `.parts` in `ExpenseCategory.entryCases` |
| **J7b** shelf visible "on shelf", next service suggests them | MET | `PartsShelfView`, `PartsShelf.suggested`, `ServiceEntryPartsSection` |
| **J7b** install: link, don't re-price | MET | `PartsShelf.link` moves the link, never money (`PartsShelf.swift:45-53`) |
| **J7b** "a tire purchase becomes a TireSet" | MISSING | **`PJ.26`** — `purchaseExpenseId` dead (`TireSetDraft.swift:35`) |
| **J7b** each swap marks which set went on | MET | `.tires` mode → `ServiceRecord.tireSetId` |
| **J7b** set mileage derived, "–" when unknown | MET | `TireMileage`, `TireSetsView.swift:64-68` |
| **J7b** "swap reminder each season" | MISSING | **`PJ.27`** |
| **J7b** fallbacks (no receipt → plain expense; skip shelf → type in service) | MET | `ExpenseEntryView`; `ServiceEntryItemCard` |
| **J7d** Home permanent "Reminders · N due" row | MET | RV.76 |
| **J7d** post-save "Remind you next time?" offer | MET | RV.77; wired `ServiceEntryView.swift:407`, `ExpenseEntryView.swift:241` |
| **J7d** offer suppressed when a live reminder exists | MET | `ReminderOffer.isSuppressed` (`:129-137`) |
| **J7d** empty state filled "New reminder" | MET | RV.76 |
| **J7c** Complete → "Log the cost?" → pre-filled entry | MET | `ReminderCompleteSheet.swift:131-152` |
| **J7c** next cycle anchored at completion, not the due date | MET | `ReminderLifecycle.complete` (`:191-229`) |
| **J7c** "Scan invoice" on ReminderComplete | MISSING | **`PJ.24`** — Type + Skip only |
| **J7c** Reschedule re-arms / Delete tombstones / dismiss-with-reason | MET | `ReminderLifecycle.reschedule/dismiss`; repo tombstone |

**Promises with no row behind them** (the shape this walk exists to find):

- J7's *"renames/splits by hand"* — **had** no row for the split half until `RV.198` was filed
  this evening. The rename half is `PJ.23`. This is now tracked, not a new finding.
- SCHEMA.md's *"yearly insurance auto-suggests next **entry** + reminder"* (`SCHEMA.md:237`) — the
  reminder half is met (ReminderOffer), the **field** `Expense.recurrence` and the *"next entry"*
  half are neither. No row names either. → **`PJ.60`**.
- SCHEMA.md's *"`partNumber` … enables reorder and lifetime tracking"* (`SCHEMA.md:228`) — no
  writer, no reader, no editor; only `PJ.52` (v2) references it. → **`PJ.61`**.
- The `proposedReminderId` ↔ `sourceEntryId` **double pointer** to one relationship — only the
  latter is ever written; no row records the redundancy. → **`PJ.62`** (decision).

---

## 4. Group or rebuild? The recommended dispatch list

**The six rows are the right *decomposition*, but the dispatch boundaries are wrong in two places,
and one decision is missing.** Three real seams, not six atoms, not one theme.

| Group | Rows | Seam (named) | Blockers / order |
|---|---|---|---|
| **A — the service item surface** | `RV.198` + `RV.199` (one dispatch) | The item collection + its derived total on **edit**: `EditEntryNonFillView.swift`, `EditEntryView+NonFillSave.swift`, `ServiceEntryItemDraft`/`ServiceEntryFormState`. They are the same screen, and RV.199's decision (derived vs independent Amount) is a **precondition** of RV.198's add/delete — adding a line must move the total or the screen must say it won't | `PJ.23` shipped (foundation). Not blocked by PJ.22 |
| **B — reminder birth from an item's lifetime** | `PJ.62` (decision) + `PJ.22` (one brief) | The reminder-birth path (`ReminderOffer`, `ReminderDraft`) plus the `lifetime` editor, which rides the **same item row** Group A is finishing. The brief must **name `ReminderOffer` as the seam and forbid a second reminder-minting path** (RV.169/RV.170/RV.171's complaint), and carry the `proposedReminderId` decision from `PJ.62` | after Group A (lifetime editor is a field on the row RV.198 touches) |
| **C — the tire loop** | `PJ.26` + `PJ.27` (one dispatch, already briefed) | `.tires` mode + `TireSet` + `TireSetsUITests`. The brief's "both write through `TireSet`" is a defensible seam; the mount record PJ.27 fires from is the `.tires` ServiceRecord, and the brief already orders the agent to confirm it | independent; runs in parallel with B |
| **D — dead-field sweep** | `PJ.63` (headings/guard) → `PJ.60` + `PJ.61` (decisions) | `SCHEMA.md` `###` headings + `FieldWriterScanner.entityFieldSpecs`. `PJ.63` first (so the guard can *see* the fields), then the drop-or-write decisions it surfaces | after PJ.63 |

**What changes vs. the rows as filed:**

1. **`RV.199` is not a standalone "filed, needs a DECISION" row** — the decision is a clause of
   `RV.198`'s add/delete work, and shipping add/delete while the total stays stale *is* the RV.199
   bug. Fold it into the RV.198 dispatch; leave the row id as the decision's home but do not
   dispatch them separately.
2. **`PJ.22` as written mints a second reminder link.** Its row says "write `proposedReminderId`"
   without noticing `Reminder.sourceEntryId` already encodes the same relationship and is already
   written by the shipped `ReminderOffer`. `PJ.62` must be decided before PJ.22 is briefed, and the
   brief must fence the reminder path the way `PJ.26+PJ.27.md` already fences `proposedReminderId`.
3. **`PJ.26`+`PJ.27` are correctly grouped.** Leave them.

**"Leave them as they are" is not the answer:** the six rows are not six dispatches, and PJ.22 as
written would produce the exact second-reminder-path defect the repo has a standing guard against.

---

## 5. Proposed `PJ.60+` rows

| Row | Deliverable (one line) | Journey stage | Consequence today | Severity | Check (done when…) |
|---|---|---|---|---|---|
| **PJ.60** | Decide drop-or-write for `Expense.recurrence` (a `RecurrenceRule?` written `nil` only, read nowhere) and record it in `SCHEMA.md` — the reminder half of "yearly insurance" is already met by `ReminderOffer`, so the honest answers are *delete the field+type* or *give it a writer+reader for the "next entry" half*, never a silent dead column | J7b Purchase / J7d | none user-visible (insurance reminder works), but a persisted column + `Codable` type + schema entry with zero function, and the "next entry" half of `SCHEMA.md:237` is unbuilt | gap | L1: `recurrence` on `Expense` is either gone from type+migration+schema+decoder, or there is a production writer/reader; grep shows no `recurrence:` assigned only `nil`. Decide whether a guard exception or a writer lands |
| **PJ.61** | Decide drop-or-write for `ServiceItem.partNumber` (written `nil` only at `ServiceEntryDraft.swift:12` and `ImportConversion.swift:147`, read nowhere, edited nowhere) — the v2 parts shelf (`PJ.52`) is the natural owner, so the honest v1 answer is a *written reason*, not a phantom writer | J7b Shelf | none user-visible; a dead column + schema promise (`SCHEMA.md:228`) | gap | L1: a reasoned `RV.196` exception names the v2 owner, or a writer lands; grep shows no non-nil `partNumber` construction |
| **PJ.62** | Decide the `proposedReminderId` vs `sourceEntryId` redundancy **before PJ.22 is briefed**: either PJ.22 writes `proposedReminderId` *and* a reader exists, or drop the field and let `sourceEntryId` be the single link (queryable in both directions); record the decision in `SCHEMA.md` and the PJ.22 row | J7 "app proposes the next reminder" | none today (the field is nil), but briefing PJ.22 as written creates a second link nobody reads | gap | L1: the decision is written; PJ.22's brief and acceptance match it (write-and-read, or delete the field and cite `sourceEntryId`) |
| **PJ.63** | Give `TireSet` (and `ServiceItem`) their own `###` sections in `SCHEMA.md` and `entityFieldSpecs` entries, then re-run the field guard so it *reports* `TireSet.purchaseExpenseId` / `ServiceItem.partNumber` / `ServiceItem.lifetime` as unwritten until their writers land | guard completeness (no-scenario) | `RV.196` is green while three fields in this loop are dead — the blind spot that let `purchaseExpenseId` ship dead | gap | L1 `SchemaFieldWriterGuardTests`: `TireSet.purchaseExpenseId` is reported unwritten before `PJ.26`; reasoned exceptions are added in the same change that ships each writer, so the list cannot rot |

**Optional polish (not a row until a product call):** `ServiceRecord.usedParts` has a writer and no
reader — a saved service never shows which parts it installed (only the shelf emptying is visible).
Likely `PJ.52` (v2 parts shelf) territory; if it is wanted in v1 it is a new row with `EditEntryUITests`.

---

## 6. Could not settle

- **`Expense.recurrence`'s guard status.** The field is not in `RV.196`'s raw report
  (`SchemaFieldWriterGuardTests.swift:203-217`), so the guard currently treats it as *written* —
  almost certainly via the repository-writer rule (a production host calls `upsertExpense`, whose
  write surface assigns the field) even though the value is always `nil`. Confirming the exact
  mechanism needs reading `FieldSourceParser.repositoryFieldWriters`; the consequence either way is
  the same (a dead field the guard cannot see), which is `PJ.60`'s subject. What would settle it:
  a run of the guard with `upsertExpense` temporarily removed from the host set, to see whether
  `Expense.recurrence` flips into the report.
- **Whether the mount record `PJ.27` fires from** (a `.tires` ServiceRecord vs something unbuilt)
  is deliberately left to the already-briefed `PJ.26+PJ.27` agent, whose brief orders it to confirm
  before building — the `.tires` mode writes `ServiceRecord.tireSetId`, which reads as the natural
  anchor, but I did not trace the reminder planner's input against it.
- **`usedParts` reader-vs-PJ.52 boundary.** Whether "show the installed parts on a saved service"
  is v1 polish or v2 shelf work is a product call; it is not the dead-field shape (the writer
  exists), so I have not filed it as a numbered row.

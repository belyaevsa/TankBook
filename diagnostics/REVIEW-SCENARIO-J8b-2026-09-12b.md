# REVIEW-SCENARIO run: J8b - 2026-09-12b (second walk, after RV.243)

- **Scenario:** `J8b` (`docs/JOURNEYS.md:458-464`)
- **Run id:** REVIEW-SCENARIO-J8b-2026-09-12b
- **Report path:** `diagnostics/REVIEW-SCENARIO-J8b-2026-09-12b.md`
- **Context:** Second walk. Re-checks only what the first walk (`REVIEW-SCENARIO-J8b-2026-09-12`) gated on: **RV.243** (the single blocker, now `[x]`) and **RV.181** (`[~]`, decide blocking). Everything else in the first walk's map is unchanged and not re-walked. Read-only except this report and the status line.

## Verdict

**IMPLEMENTED** - RV.243 (the sole blocker) is shipped and true in code and tests; RV.181 is `[~]` (shipped, awaiting one physical-device share) and does not block this scenario's status line for the reason stated in Not settled.

## Ticked rows found to be untrue

None. The one closed row this walk re-checks, **RV.243**, holds in code and tests.

- **RV.243** (deferred read keeps the photo) is true:
  - Expense: `ExpenseEntrySession.stageScan` (`ExpenseEntrySession.swift:129-132`) stages the photograph before the read; `start(image:...)` (`:102-108`) calls it, and `acceptExpenseScan` (`CaptureExpenseScan.swift:44`) passes the image, so the photo is in hand the instant the scan starts. The save writes from the staged capture, not the read's state: `writeExpense` (`ExpenseEntrySave.swift:20-47`) -> `ExpenseReceiptWrite.write` (`ExpenseReceiptWrite.swift:28-44`). The read only enriches via `onAnswer` (`ExpenseEntryView.swift:122-128`, which consumes the capture for its photo even when a user edit suppresses the values).
  - Service: `ServiceInvoiceScanner.stagePages` (`ServiceInvoiceScanner.swift:61-66`) persists pages at scan start; `enrichPages` (`:125-138`) updates the same rows in place, never a duplicate.
  - Oracle is the stored row + file on disk, not the inbox item: `RV243DeferredReceiptSaveTests` (`RV243DeferredReceiptSaveTests.swift:113-158` expense, `:165-210` service).

## Promise-to-code map (re-checked items only)

The first walk's full map stands for every other promise. This walk re-checks the two the gating turned on:

| Journey promise (J8b) | Status | Citation |
|---|---|---|
| A deferred expense/service read that lands after save keeps the receipt/invoice photo (RV.243 gate) | MET | `ExpenseEntrySession.stageScan:129`; `ExpenseEntrySave.writeExpense:20` -> `ExpenseReceiptWrite.write:28`; `ServiceInvoiceScanner.stagePages:61` + `enrichPages:125`; tests `RV243DeferredReceiptSaveTests.swift:113,165` |
| Share hands the **full** rendition, offered only once local | MET (code; RV.181 device step outstanding) | `AttachmentViewerView.presentShare:408-419` gates `fullData != nil`, payload is the full `UIImage`/temp PDF (`shareItems:425-434`), routed through `SharePresenter.present` from the top-most controller (`ActivityView.swift:36-52`) |

## Sequence trace (the gating path, one user)

1. Expense-mode capture -> `acceptExpenseScan` -> `session.start(image:...)` stages the photograph immediately (`stageScan`), then starts the deferred read (`CaptureExpenseScan.swift:44-54`).
2. User saves before the read lands -> `save()` -> `writeExpense(form:..., scan: scan, ...)` writes the staged capture through `ExpenseReceiptWrite` -> the receipt row and file are on disk (`ExpenseEntryView.swift:249-251`).
3. The read lands late -> `markSaved` routes it to the inbox through `onSavedAnswer` (`ExpenseEntrySession.swift:89-91`), never to the closed form; the photo is already the entry's.
4. Service invoice: same shape - pages persisted at `stagePages`, the save references them, the late read reaches the inbox.

**Where a fact stops being carried:** none. The photograph is carried by the session from scan start, not by the read's completion, so the read no longer has a crossing with the photo.

## Proposed rows

None. RV.243 (the gate) is closed and true; re-filing it would duplicate it. RV.181 is `[~]`, owned by its own row, not a J8b promise gap.

## Not settled

- **RV.181's device step does not block J8b, and here is why.** The J8b promise is that the Share affordance *hands the full rendition to the system share sheet, offered only once that rendition is local* - and that is MET in code (`AttachmentViewerView.swift:408-419` gates on `fullData`, routes through `SharePresenter.present` from the top-most controller). RV.181's open tail is not a J8b code gap: its cause was withdrawn as unestablished, the shipped change is hardening plus a diagnosable `ShareOutcome` log, Save Image / Save to Files (in-process) work, and the remaining out-of-process destinations (Mail, Telegram) are unverifiable on any simulator - the row is explicitly "not agent work" and "out of the dispatch queue." Blocking J8b on it would convert "one share not yet confirmed on a physical device" into "J8b's share promise is missing," which the code does not say, and would re-file a cross-cutting share-layer concern under a journey that does not own it. RV.181 stays `[~]`; the residual risk is already tracked, and the `ShareOutcome` log now makes the next device report answerable.
- **The first walk's two open "Not settled" notes remain open and are not this run's scope:** the replace re-read ask is fill-up-only (`AttachmentViewerActions.swift:125`, not a J8b promise as written), and the recognised-page journey-text drift ("OCR lines and the scan timestamp" vs the per-field assignment headline) still folds into the next change touching `docs/JOURNEYS.md`.

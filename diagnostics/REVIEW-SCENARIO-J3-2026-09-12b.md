# REVIEW-SCENARIO run: J3 - 2026-09-12b (second walk, after RV.243)

- **Scenario:** `J3` (`docs/JOURNEYS.md:86-123`)
- **Run id:** REVIEW-SCENARIO-J3-2026-09-12b
- **Report path:** `diagnostics/REVIEW-SCENARIO-J3-2026-09-12b.md`
- **Context:** Second walk. The first walk (`REVIEW-SCENARIO-J3-2026-09-12.md`) gated J3 on **RV.243** (a deferred expense/service read that lands after save lost the photo). RV.243 shipped as `23ec0d85` and is now `[x]` in `TASKS.md:86/787`. This walk re-checks only what gated, plus the RV.181 `[~]` blocking question the run instruction raised. Read-only walk; no code, no build, no commit.

## Verdict

**IMPLEMENTED** - RV.243 resolved the single blocker: the photograph and the invoice pages are now staged at scan start, so a save that beats a deferred read keeps them, and the late read only offers values through the inbox. Every other J3 promise was MET or reasoned N/A in the first walk and is unchanged.

## Ticked rows found to be untrue

None. RV.243's `[x]` was walked against the tree and holds:

- `ExpenseEntrySession.start(image:)` calls `stageScan(image)` **before** `deferred.start`, so `pendingCapture` is set the instant the scan begins (`ExpenseEntrySession.swift:102-108,129-132`).
- The save writes the photo from whatever capture the sheet holds, never from the read's state (`ExpenseEntrySave.swift:16-34`, called from `ExpenseEntryView.swift:249-251`).
- The expense form consumes the staged capture even when the read produced no pre-fill (`ExpenseEntryView.swift:390-397`); a late read's values are suppressed on edit but its photo is always consumed (`ExpenseEntryView.swift:122-128`).
- The service path persists pages at scan start (`ServiceInvoiceScanner.stagePages`, `ServiceInvoiceScanner.swift:56-62`) and the read enriches the same rows, never a second set (`enrichPages`/`updatePage`, `ServiceInvoiceScanner.swift:121-133`, `InvoicePageStore.swift:60-69`).
- L1 asserts the real contract - row on disk, file on disk, inbox item - for both kinds (`RV243DeferredReceiptSaveTests.swift:113-158,165-210`).

## Promise-to-code map (re-checked items only)

The first walk's map (`REVIEW-SCENARIO-J3-2026-09-12.md:24-55`) stands for every other stage. The one row it marked BLOCKED is re-checked here:

| Journey promise (J3) | Status | Citation |
|---|---|---|
| **Receipt catches up** - a deferred expense read keeps its photo | MET | `stageScan` stages the image before the read (`ExpenseEntrySession.swift:129-132`); save writes from the staged capture (`ExpenseEntrySave.swift:22-33`); load consumes it with or without a pre-fill (`ExpenseEntryView.swift:390-397`); late read routes to inbox only (`ExpenseEntrySession.swift:83-96`, `CaptureExpenseScan.swift:52-54`) |
| **Receipt catches up** - a deferred service read keeps its invoice | MET | pages persisted at scan start (`ServiceInvoiceScanner.swift:56-62`); staged into `pendingPrefill` (`ServiceInvoiceSession.swift:79-82`); `apply` writes `attachments` + `.receiptScan` (`ServiceEntryFormState.swift:245-255`); late read enriches the same rows (`ServiceInvoiceScanner.swift:121-133`) |

## Sequence trace (the RV.243 delta)

1. Expense scan starts → `session.start(image:)` → `stageScan` → `pendingCapture` holds the image with an empty extraction, before any read runs (`ExpenseEntrySession.swift:106-107,129-132`).
2. Sheet opens; `load()` consumes `pendingCapture` into `scan` regardless of whether `pendingPrefill` arrived (`ExpenseEntryView.swift:390-397`).
3. Save → `writeExpense(scan:)` writes the photo from the held capture, then `markSaved` (`ExpenseEntryView.swift:249-251,287`).
4. Read lands late → `savedEntryID` is set, so `onSavedAnswer` → inbox; `pendingCapture` is never re-set, the photo is already on disk (`ExpenseEntrySession.swift:83-96`).
5. Service path is the same shape one page set over: `stagePages` → `start(stagedPages:)` → `stagePages` → `pendingPrefill` carries the persisted pages → save keeps `attachments` → late read enriches the same rows (`ServiceInvoiceSession.swift:60-82`, `ServiceEntryFormState.swift:252-254`).

**Where a fact stops being carried:** none. The one fact the first walk found dropped behind a slow read - the photo/pages - is now staged before the read and written at save through the one receipt path. Nothing a user photographs can vanish behind a slow read.

## Proposed rows

None. The blocker was the already-filed RV.243, now shipped and verified here. Nothing new was found that is unowned.

## Not settled / cited-but-not-blocking

- **RV.181 (`[~]`) does not block J3.** Its scenario tags are J13 (export) and J8b (sharing a receipt); J3's text (`docs/JOURNEYS.md:86-123`) makes no share promise - the Done row ends at "closes phone". The open on-device share verdict belongs to J8b/J13, not this journey. The first walk reached the same conclusion (`REVIEW-SCENARIO-J3-2026-09-12.md:76`).
- **The second RV.243 row - "fuel kind committed from till boilerplate" (`TASKS.md:89/790`, `[ ]`) - does not block J3.** It is tagged primarily F2 ("scan recognized WRONG data"), and its J3 mention is only that the wrong pre-fill lands on J3's Confirm screen. J3's promise is the flow (pre-fill is an editable default, rule 13; RV.71's mismatch warning never blocks); the pre-fill's *correctness* is F2's promise, and this bug is already filed there. Cited, not re-filed.
- **Duplicate task id:** `RV.243` names two different rows (`TASKS.md:86` the deferred-photo bug, now `[x]`; `TASKS.md:89` the fuel-kind-boilerplate bug, `[ ]`). A tracking defect, not a code one; flagged for the owner, no row proposed here.
- **RV.245** (staged pages orphaned by a cancelled service scan, `[ ]`) is J7/hygiene, not J3, and out of scope for this verdict.
- **Unchanged from the first walk** and still not blocking: the AdBlue variant version-marker disagreement, the "Save -> haptic" beat wording (PJ.15 `[v1.1]`), and the unmeasured "camera ready in <1s" figure (`REVIEW-SCENARIO-J3-2026-09-12.md:74-79`).

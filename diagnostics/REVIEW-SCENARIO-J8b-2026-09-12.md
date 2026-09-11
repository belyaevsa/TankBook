# REVIEW-SCENARIO run: J8b – 2026-09-12 (first walk)

- **Scenario:** `J8b` (`docs/JOURNEYS.md:453-459`)
- **Run id:** REVIEW-SCENARIO-J8b-2026-09-12
- **Report path:** `diagnostics/REVIEW-SCENARIO-J8b-2026-09-12.md`
- **Context:** First walk. Closed today for this scenario: RV.197, RV.208, RV.216, RV.217, RV.204, RV.209, RV.215 (and RV.181 shipped `[~]`, awaiting the owner's device). Open and known: RV.243 (blocks), RV.244, RV.227, RV.234, RV.235. Read-only walk; no code, no build, no commit.

## Verdict

**NOT IMPLEMENTED** – every concrete promise in J8b's text is MET in code, but the scenario is gated on the already-filed **RV.243** (a deferred expense/service read that lands after save loses the receipt photo), per the run instruction. No new unowned promise was found; the deliverable here is the map and trace, not a fresh backlog.

## Ticked rows found to be untrue

None. Each closed row naming this scenario was walked against the tree and holds:

- **RV.197** (guest Log): `HomeView.swift:190-202` renders `HomeGuestLayout` with the same `logStream` the signed-in layout uses, gated on `HomeLayout.logArea(for:) == .stream`, never on the session.
- **RV.208** (dangling id, no sweep): `AttachmentReference.unresolved` (`Domain/AttachmentReference.swift:43-51`) reports without writing; `EditEntryRows.missingReceiptCard` (`EditEntryRows.swift:72-105`) surfaces it with the re-attach door. No migration sweeps the id.
- **RV.204** (degrade everywhere): one seam, `attemptReceiptPhotoWrite`, called from `attachHeldReceiptToFill` (`EditEntryView+FillReceiptSave.swift:51`) and `writeNonFillWithHeldReceipt` (`EditEntryView+NonFillSave.swift:116`); `.lost` reported after save (`EditEntryView.swift:353,379`).
- **RV.209** (two builders, difference documented): `ReceiptAttachmentWriter`'s doc comment (`ReceiptAttachSupport.swift:18-29`) states why it records default provenance vs the save-side `writeReceiptPhoto`.
- **RV.215** (deferred service/expense read): `acceptExpenseScan` defers via the session (`CaptureExpenseScan.swift:40-49`) and routes the late answer through `AppInbox.recordLateGatewayAnswer`.
- **RV.216** (line-item `n + 1`): `FieldLabel.text(.lineItem(n))` renders `n + 1` while the ref stays the index (`FieldLabel.swift:28-33`).
- **RV.217** (RU label column): layout-only row on the Inbox; not a J8b surface, closed per `TASKS.md:766` with the orchestrator's own frame check. Not re-walked here (not this journey's screen).

## Promise-to-code map

| Journey promise (J8b) | Status | Citation |
|---|---|---|
| Chip is a **tap target**, not decoration | MET | `ReceiptCardView.swift:76-89` (`chipButton` wraps `AttachmentPhotoChip` in a `Button` that sets `showViewer`); chip itself renders only (`AttachmentPhotoChip.swift:4-9`) |
| Photo opens full-screen, fitted, pinch/double-tap magnifies | MET | `AttachmentViewerView.swift:212-229` (`fullRendition`) -> `ZoomableImageView` (`AttachmentRenditionViews.swift:12-79`: fitted, zoom 1–6, double-tap) |
| PDF invoice opens in the PDF viewer, not a blank frame | MET | `AttachmentViewerView.swift:213-219` branches `kind == .pdf` -> `AttachmentPDFView` (`AttachmentRenditionViews.swift:84-99`); unreadable bytes -> explicit `.unreadable` state (`:218`) |
| Full rendition not on device -> thumbnail from first frame + named next step; never empty, never blocks | MET | `pendingContent` (`:237-255`) shows `thumbnailPreview` + `unavailableCard` (`:304-335`); headline/nextStep per reason (`:349-365`); guest -> `.signedOut`, not a crash (`:449-451`) |
| Recognised data -> second page beside photo, swipe away, absent when nothing | MET | `hasRecognisedData` (`:379-386`) gates a `TabView` (`:178-191`) -> `AttachmentRecognisedView` (per-field assignment + OCR disclosure + capture time). Never re-runs OCR |
| Share hands the **full** rendition, offered only once local | MET (device verification of RV.181 pending) | gate `fullData != nil` (`:99`); `presentShare` (`:408-419`) -> `SharePresenter.present` from the top-most controller (`ActivityView.swift:29-52`); PDF shares a temp file, photo shares the `UIImage` (`:425-434`) |
| Close/swipe-down -> entry exactly as before, still editable | MET | viewer is a `.sheet` with a drag indicator (`:111`); `dismiss()` on Close (`:104`); `onAttachmentChanged` fires only on Delete/Replace/Update-entry |
| Entry without a receipt -> **Add receipt** on the strip (RV.202) | MET | fill-up four-way branch `EditEntryView+Attachment.swift:74-96` (empty -> `receiptCard` + `onAddReceipt`); non-fill `EditEntryNonFillView.swift:133-158` |
| Dangling id -> "The photo for this entry was never saved" + Add receipt door; reference stays (RV.208) | MET | `EditEntryRows.missingReceiptCard` (`:72-105`); `AttachmentReference` reports never writes (`Domain/AttachmentReference.swift:32-64`); surfaced in both branches |
| **Delete** – system-confirmed, tombstone + unlink, blob left alone | MET | `AttachmentViewerActions.swift:86-96` (`performDelete`) -> `Repository+Attachment.swift:26-34` (one transaction, tombstone only when no other live entry references the id) |
| **Replace** – camera/Photos door, new attachment + tombstone old, never in-place | MET | `AttachmentViewerActions.swift:104-137` (`handleReplace`) -> `replaceAttachment` (`Repository+Attachment.swift:41-54`) |
| Replace asks "Re-read this and update the entry?"; "Leave it as it is" is the default | MET (fill-up only, see Not settled) | `AttachmentViewerView.swift:140-164` (confirmationDialog, plain default button, `.tint(.action)`); ask fires only `if entry is FillUp` (`AttachmentViewerActions.swift:125-130`) |
| "Update entry" -> suggestions fill **blank fields only**, dimmed until tapped | MET | `onAttachmentChanged(replaceExtraction)` -> `handleAttachmentChanged` (`EditEntryView+Attachment.swift:18-25`) -> `ReceiptAttachMerge.suggestions` + `applyAttachedSuggestions` (`ReceiptAttachSupport.swift:167-…`) |
| "Use a different receipt" is just replace again | MET | `AttachmentViewerView.swift:158-160` sets `showReplaceSource`; `effectiveAttachmentID` tracks the newest attachment (`AttachmentViewerActions.swift:19`) |
| Success metric (readable without leaving app; never a blank screen) | N/A | metric, not code |

## Sequence trace (one user, weeks later, questioning a fill)

1. Cold launch as guest -> Home renders the log stream, entry visible without a session (`HomeView.swift:190-202`; hard rule 1).
2. Tap the entry -> Edit entry (fill-up) -> `fillUpReceiptCard` shows the receipt strip (`EditEntryView+Attachment.swift:74-78`).
3. Tap the chip -> `.sheet` presents `AttachmentViewerView` (`ReceiptCardView.swift:64-69`).
4. `load()`: local -> `.full` zoomable; not local -> thumbnail + spinner then fetch; signed out -> `.unavailable(.signedOut)` naming the next step; PDF -> PDFKit. No blank frame at any branch.
5. Swipe -> recognised page (only when `hasRecognisedData`): per-field assignment, OCR disclosure, capture time. Absent otherwise.
6. Share (only once `.full`): `SharePresenter` from the top-most controller.
7. Close/swipe-down -> entry untouched and still editable.
8. Delete -> confirm -> tombstone + unlink in one transaction -> receipt gone, entry editable.
9. Replace -> camera/Photos -> new attachment + tombstone old -> ask -> default "Leave it as it is" / "Update entry" (blank fields dimmed) / "Use a different receipt".
10. Entry with no receipt -> "Add receipt" -> camera/Photos -> pending card -> Save -> photo persisted via `attemptReceiptPhotoWrite`; a failed write degrades and reports (RV.204).
11. Dangling id -> `missingReceiptCard` -> "Add the receipt again".

**Where a fact stops being carried:** no J8b-internal loss found. The viewer carries `entry` and `onAttachmentChanged` through every surface, the entry's `attachments` are re-read from the repository after delete/replace, and the form's field values are untouched unless the user explicitly picks "Update entry". The one carry that is scoped by construction: the re-read ask (and its fuel-typed `onAttachmentChanged: (FuelExtraction?) -> Void`) fires only for `FillUp` (`AttachmentViewerActions.swift:125`), so a service/expense replace swaps the photo with no ask – consistent with the fuel framing of J8b's trigger, but see Not settled.

## Proposed rows

None. The single blocker is the already-filed **RV.243** (bug; a deferred expense/service read that lands after `markSaved` leaves the attachment nil – the photo the user took is gone; `TASKS.md:786`). Re-filing it would duplicate the row. RV.181 (share dispatch) is `[~]`, shipped in code, awaiting the owner's device, not a missing promise.

## Not settled

- **RV.181's device verdict is outstanding.** The share now presents from the top-most controller (`ActivityView.swift:29-52`) and the J8b share surface (`AttachmentViewerView.swift:408-419`) routes through it, but the `[~]` state means no one has confirmed on-device that a chosen destination actually receives the photo. Until that lands, the "hands the full rendition to the system share sheet" promise is MET in code but unverified in the one place the original report came from. Owned by RV.181, not a new row.
- **The replace re-read ask is fill-up-only.** J8b's Delete-and-replace paragraph is written fuel-generically, but `handleReplace` (`AttachmentViewerActions.swift:125`) skips the ask for charge/service/expense, and `onAttachmentChanged` is `(FuelExtraction?)`-typed. A service invoice's re-read would need the service-shaped recognition RV.201/RV.215 built for the inbox, not the fuel `FuelExtraction` the viewer holds. Today this reads as: replace a service invoice -> photo swaps silently, no re-read offered. Not a J8b promise as written (the trigger and the ask are fuel), and not filed – worth a product-owner confirmation only if replace-for-service-invoice should offer a re-read.
- **Minor journey-text drift on the recognised page.** J8b's text still says the second page shows "the OCR lines and the scan timestamp"; RV.48/RV.183 made the per-field assignment the headline and demoted raw OCR behind a disclosure, with the capture time as the caption and the printed date as a field row. The promise ("shows what was read, absent when nothing") is still MET – the wording is stale, not the behaviour. Folds into the next change touching `docs/JOURNEYS.md`.

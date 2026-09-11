# REVIEW-SCENARIO run: J3 – 2026-09-12 (first walk)

- **Scenario:** `J3` (`docs/JOURNEYS.md:86-123`)
- **Run id:** REVIEW-SCENARIO-J3-2026-09-12
- **Report path:** `diagnostics/REVIEW-SCENARIO-J3-2026-09-12.md`
- **Context:** First walk. Closed today for this scenario: RV.197, RV.208, RV.216, RV.217, RV.204, RV.209, RV.215 (and RV.181 shipped `[~]`, awaiting the owner's device). Open and known: RV.243 (blocks), RV.244, RV.227, RV.234, RV.235. Read-only walk; no code, no build, no commit.

## Verdict

**NOT IMPLEMENTED** – every concrete stage of J3's core loop (Open → Scan → Review → Confirm → Done) and the mixed-receipt variant are MET in code, but the scenario is gated on the already-filed **RV.243** (a deferred expense read that lands after save loses the receipt photo), per the run instruction. No new unowned promise was found; the deliverable here is the map and trace, not a fresh backlog.

## Ticked rows found to be untrue

None. Each closed row naming this scenario was walked against the tree and holds:

- **RV.197** (guest Log): `HomeView.swift:190-202` renders `HomeGuestLayout` with the same `logStream` the signed-in layout uses, gated on `HomeLayout.logArea(for:) == .stream` (`HomeView.swift:199,273-279`), never on the session.
- **RV.208** (dangling id, no sweep): `AttachmentReference` reports without writing (`Domain/AttachmentReference.swift:32-64`); `EditEntryRows.missingReceiptCard` (`EditEntryRows.swift:72-105`) surfaces it with the `onAddReceipt` re-attach door. No migration sweeps the id.
- **RV.204** (degrade everywhere): one seam, `attemptReceiptPhotoWrite`, called from the fill-up edit (`EditEntryView+FillReceiptSave.swift:51`) and the non-fill edit (`EditEntryView+NonFillSave.swift:116`); `.lost` reported after save.
- **RV.209** (two builders, difference documented): `writeReceiptPhoto` (`ManualFillUpReceiptSave.swift:237-261`) records `extraction?.assignmentOnly` from the save plan; `ReceiptAttachmentWriter.write` records default provenance from a bare `FuelExtraction`. Both readers consume values only.
- **RV.215** (deferred service/expense read): `DeferredRecognition` (`Inbox/DeferredRecognition.swift:30-75`) is the shared boundary; `acceptExpenseScan` (`CaptureExpenseScan.swift:37-55`) and `scanServiceInvoice` (`CaptureView.swift:631-645`) route the late answer through `AppInbox.recordLateGatewayAnswer` – the one policy, never a second producer.
- **RV.216** (line-item `n + 1`): `FieldLabel.text(.lineItem(n))` renders `n + 1` while the ref stays the `items` index (`FieldLabel.swift:28-33`).
- **RV.217** (RU label column): label cell keeps its ideal width (`fixedSize(horizontal: true)`), values take the remainder (`InboxView.swift:169-191`); same-line layout, disposition caption only on `.fillsBlank`.

## Promise-to-code map

| Journey promise (J3) | Status | Citation |
|---|---|---|
| **Open** – lock-screen widget | N/A | `[v1.x]` per `VISION.md:93` ("Widgets, Shortcuts, Siri | v1.x"); no widget extension in `project.yml` |
| **Open** – camera ready in <1s | MET (by inspection, unmeasured) | `CaptureView.resolvePermission` on `.task` → `setCameraStatus` → `camera.start()` (`CaptureView.swift:94,156-172`); preview is the same session the shutter reads (`CaptureView.swift:57-60`) |
| **Open** – auto-shutter on document detect | N/A | `[v1.1]` per PJ.16 (`TASKS.md:756`, "document-segmentation auto-shutter"); shutter is manual (`CaptureView.captureFrame`, `:384-409`) |
| **Scan** – torch auto-suggest | N/A | `[v1.1]` per PJ.16 ("torch toggle … from a luminance signal", `TASKS.md:756`); no `torch`/`hasTorch` in the tree |
| **Scan** – keep the photo regardless of OCR result | MET | `CapturePipeline.process` returns `ConfirmPrefill(sourceImage: image, …)` even when OCR resolves nothing (`CapturePipeline.swift:40-49`); a nil extraction is the empty manual form, never an error |
| **Review** (RV.5) – photo shown immediately, OCR only on "Use this" | MET | `processScanned` sets `reviewSubject` with no pipeline run (`CaptureView.swift:309-311`); `acceptReview` runs the pipeline only on accept (`:321-333`); the raw image is the review frame (`CaptureReviewView.swift:75-88`) |
| **Review** – Re-take is the back path (nothing kept) | MET | `onRetake` → `reviewSubject = nil` (`CaptureView.swift:145`); no pipeline ran, nothing persisted |
| **Review** – "Type it" is a peer, never the failure branch | MET | `onTypeIt` sits beside Re-take at equal width (`CaptureReviewView.swift:104-113`); `typeItAfterReview` opens the selected mode's form and drops the photo (`CaptureView.swift:349-358`) |
| **Confirm** – Pump Card pre-filled | MET | `acceptFillUpScan` → `CapturePipeline.process` → `ScannedFillUpSheet(prefill:)` → `ManualFillUpView(prefill:)` (`CaptureFillUpScan.swift:26-30`, `ScannedFillUpSheet.swift:51-68`) |
| **Confirm** – cross-check line locks ✓ | MET | `ManualFillUpSections.swift:280-331` (`.mismatch` warn vs `.verified` lock, draw-in animation) |
| **Confirm** – types odometer, live "+N km since last" (PJ.14) | MET | `OdometerDelta.evaluate` per render, four states (forward/backwards/pace/equal), never blocks save (`ManualFillUpSections.swift:409-451`) |
| **Confirm** – low-confidence fields dimmed until tapped | MET | `ConfirmConfidenceGate.confidence` → `.opacity(dimmed ? … : 1)` (`ManualFillUpSections.swift:214,233-245`) |
| **Confirm** – RV.71 fuel-kind mismatch warns, never blocks | MET | `FuelKindMismatchNotice` (`FuelKindMismatchNotice.swift:20-83`), rule in `FuelKind.shouldWarnFuelMismatch` (`Enums.swift:57-70`) |
| **Done** – haptic + "6.8 L/100 km – best this year" insight one-liner | N/A | `[v1.1]` per PJ.15 ("after-save haptic + insight toast … today `save()` posts nothing", `TASKS.md:755`). The only haptic is the cross-check lock's `.success` beat, fired at Confirm not Save (`ManualFillUpSections.swift:323-329`) |
| **Done** – RV.12 Save leaves capture, lands on the tab with the entry visible | MET | `noteEntryChanged()` then `onSaved?()` (`ManualFillUpView.swift:617,631`) → `leaveCaptureAfterSave` → `onEntrySaved` → `dismiss()` of the cover (`CaptureView.swift:373-379`, `Destinations.swift:170`) |
| **Mixed receipt** – arithmetic check isolates the fuel line, not the grand total | MET | `MixedReceiptDetector.detect` (QR signal + structure signal, fuel line vs grand total) (`MixedReceipt.swift:78-112`) |
| **Mixed receipt** – "Also on this receipt" section, one tap to accept/skip | MET | `MixedReceiptSection` (`MixedReceiptSection.swift:13-113`) |
| **Mixed receipt** – accepted lines become Expenses sharing one photo + `purchaseGroupId` | MET | `ReceiptGroupPlanner.plan` (`MixedReceipt.swift:304-315`) + `ScannedSavePlan.expenses` (`ScannedSavePlan.swift:330-345`); photo written once via `attemptReceiptPhotoWrite` (`ManualFillUpView.swift:565`) |
| **Mixed receipt** – Log shows one grouped moment | MET | entries sharing a `purchaseGroupId` render as one receipt (`HomeSections.swift:297`) |
| **Mixed receipt** – photo can't be kept → whole group saves with no photo + one shared toast (RV.173) | MET | `ReceiptWriteOutcome.lost` (`ManualFillUpReceiptSave.swift:203-216`); `binding(nil)` leaves every row unattached (`ScannedSavePlan.swift:302-345`); `reportLostReceiptPhoto` (`:158-162`) + `GroupedSaveReceiptLost` (`ManualFillUpView.swift:591-594`) |
| **Mixed receipt** – fallback: line detection fails → fill-up + receipt save; "add expense from this receipt" later | PARTIAL | `.notMixed` → ordinary fill-up save with receipt MET (`ManualFillUpView.save`, `:553-635`); the "add expense from this receipt" affordance is `[v1.x]` per PJ.41 (`TASKS.md:804`) – no such door exists in the edit form |
| **AdBlue variant** – second fill-up `.adBlue`, AdBlue rate, standalone chip | N/A | `[v1.1]` per P1.14 (`TASKS.md:638`, unticked). `FuelKind` has no `.adBlue` case (`Enums.swift:4-14`); the mixed detector emits only `Expense` rows, never a second `FillUp` (`MixedReceipt.swift:150-167`) |
| **Receipt catches up** – late fuel answer → inbox suggestion, per tick, "leave as it is" default (RV.38) | MET | `gatewaySession.markSaved` → `recordLateGatewayAnswer(.fuel, …)` (`ManualFillUpView.swift:463,622`); `GatewayInboxPolicy.item/offers/merged` (`GatewayInboxPolicy.swift:141-185,424-440`) |
| **Receipt catches up** – same inbox serves service + shop receipt (RV.201/RV.215) | MET | `InboxRecognition` (`.fuel/.service/.expense`); `DeferredRecognition` defers the service/expense read (`DeferredRecognition.swift:30-75`); both route through `recordLateGatewayAnswer` |
| **Receipt catches up** – a deferred expense read keeps its photo | **BLOCKED** | RV.243 (`TASKS.md:786`, open): the photo travels via `pendingCapture` set only when the read finishes before save (`CaptureExpenseScan.swift:42-46`); a read landing after `markSaved` carries `ExpenseRecognition` (total + category only, no photo) (`CaptureExpenseScan.swift:91-93`) |
| **RV.197 note** – saved fill-up on Home even with no account | MET | `HomeView.swift:190-202` (guest renders the same `logStream`) |
| **RV.208 note** – a never-saved photo shows the missing-photo card with re-attach next step | MET | `EditEntryRows.missingReceiptCard` (`EditEntryRows.swift:72-105`), fed by `AttachmentReference.unresolved` (`EditEntryView+EntryResolution.swift:109-110`) |
| **Success metric** (median capture-to-save, ≥80% capture share, etc.) | N/A | metric, not code |

## Sequence trace (one user, receipt in hand)

1. Home (signed in or guest) → capture card/button, one tap (`HomeGuestLayout.swift:194-225`; guest Home still renders the log stream, RV.197).
2. Capture cover opens on the live camera (`CaptureView.resolvePermission` → `camera.start()`); shutter takes a frame → `captureFrame` (`:384-409`) → `reviewSubject` set, no OCR yet.
3. Review shows the raw frame with Use this / Re-take / Type it (`CaptureReviewView.swift:90-118`).
4. "Use this" → `acceptReview` → `acceptFillUpScan` → `CapturePipeline.process` → `ScannedFillUpSheet` → `ManualFillUpView(prefill:)`, the Pump Card pre-filled; a nil extraction is the empty manual form.
5. Confirm: cross-check locks (haptic), fuel-kind mismatch warns if the scan disagrees (RV.71), odometer shows the live delta (PJ.14), low-confidence fields dim. Mixed receipt → "Also on this receipt" toggles.
6. Save → one `attemptReceiptPhotoWrite` (shared id) → grouped save (fill-up + accepted expenses, one `purchaseGroupId`) → `noteEntryChanged` → `gatewaySession.markSaved` → `dismiss()` → `onSaved` → `leaveCaptureAfterSave` → `onEntrySaved` → the cover dismisses, landing on the tab with the entry visible (RV.12).
7. A gateway answer that finishes after save becomes an inbox item, per-field, "leave it as it is" loud by default (RV.38/RV.201).
8. Mixed-receipt photo write fails → the whole group saves with no attachment and one shared toast (RV.173).

**Where a fact stops being carried:** exactly one, and it is already filed – **RV.243**. On the fuel path the photo is safe: `writeReceiptPhoto` runs at save from the plan the sheet holds, regardless of whether the cloud answer has arrived (`ManualFillUpView.swift:565`). On the expense path the photograph is carried by `pendingCapture`, which is set only when the read finishes before save (`CaptureExpenseScan.swift:42-46`); a read that lands after `markSaved` routes a recognition holding amount + category only (`:91-93`), so the photo the user took is dropped. Same shape on the service path (`CaptureView.swift:631-645`). This is the one place in the whole journey where a fact (the photo) does not survive the save boundary.

## Proposed rows

None. The single blocker is the already-filed **RV.243** (bug; a deferred expense/service read that lands after `markSaved` leaves the attachment nil – the photo is gone; `TASKS.md:786`). Re-filing it would duplicate the row. RV.181 (share dispatch) is `[~]`, shipped in code, awaiting the owner's device, and out of J3's core loop.

## Not settled

- **RV.181's device verdict is outstanding** – identical to the J8b walk: the share now presents from the top-most controller, but the `[~]` state means no on-device confirmation that a chosen destination receives the photo. Not a J3 core-loop promise, and not a new row.
- **The AdBlue variant carries no version marker.** J3's text (`docs/JOURNEYS.md:100-101`) states the AdBlue variant as an unmarked (v1) promise, while its owner P1.14 is `[v1.1]` and unticked (`TASKS.md:638`), and `VISION.md:83` lists AdBlue as MVP. The code has no `.adBlue` case at all (`Enums.swift:4-14`). No code is missing that v1 owes – the row owns the work – but the journey text and the roadmap disagree about *when*. Folds into the next change touching either doc; a `[v1.1]` marker on the variant paragraph would settle it.
- **"Save → haptic" is written at the wrong beat.** The only haptic is the cross-check lock's `.success` (`ManualFillUpSections.swift:323-329`), which fires at Confirm, not at Save. The after-save haptic the Done row literally describes is PJ.15 `[v1.1]`. Behaviour is as designed once the version markers are read; the journey's Done row is stale wording, not a missing feature.
- **"Camera ready in <1s" is asserted nowhere.** The code path (`camera.start()` on appear) is the right shape, but the <1s figure is a claim the tree cannot prove. A future L4 launch-time measurement would settle it; not filed.

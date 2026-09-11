# REVIEW-SCENARIO-F1-2026-09-11b – F1 · Scan recognized nothing (or almost nothing)

**Verdict: NOT IMPLEMENTED** – the Aftermath stage (silent improvement-sample queue + onboarding opt-in) is not built, and PJ.20 is ticked as closing it; the success metric is also unmeasurable.

---

## Ticked rows found to be untrue

| Row | Claim | Finding |
|---|---|---|
| **PJ.20** `[x]` | Closes "F1 Aftermath" | **PJ.20 is ticked but does not deliver F1's Aftermath.** It ships a manual feedback composer in About (Settings → About & feedback), whose consent `"Send this case to help improve scanning"` (`L10nFeedback.swift:38-40`) gates a *user-typed message*. The journey promises two things it does not: (1) the failed scan's **photo + OCR text silently queued** as an improvement sample, and (2) an opt-in **"set once during onboarding"**. Neither exists. `FeedbackModel.send()` (`FeedbackModel.swift:76-104`) queues only a free-text message plus optional device model; no failed-scan sample is ever captured or queued, and the consent lives in About, never in onboarding (`WelcomeView` / `WelcomeRootView` – PJ.3's one screen has three doors, no scanning consent). |

No other F1 row (PJ.1, PJ.2, PJ.17, PJ.17b, RV.164) is untrue; each is walked below and holds.

---

## Promise-to-code map

### Capture – "Shutter fires, brief processing shimmer (<2s)" / "Never a spinner longer than 2s – commit to an answer"

**MET** (design evolved; the rule's substance holds). RV.5 inserted a review step: the shutter hands the raw frame to `CaptureReviewView` and the pipeline does **not** run yet – `CaptureView.swift:306-308` (`processScanned` just sets the review subject), `CaptureReviewView.swift:23-27` ("the pipeline runs only when the user taps Use this … the photo appears with no wait"). After "Use this", `CapturePipeline.process` runs (`CaptureFillUpScan.swift:27-30`) with **no visible spinner** – the `isProcessing` flag (`CaptureView.swift:42`) only guards against a double tap and renders nothing. So there is no spinner to exceed 2 s: the answer (review, then the Confirm sheet) is committed immediately. The literal "processing shimmer" is superseded by the review step and is absent, which is a wording drift in the F1 text, not a broken promise.

### Verdict – "Pump Card opens empty but alive: photo attached at top, fields blank, keyboard already up on Total"

| Sub-promise | Status | Citation |
|---|---|---|
| Opens empty, not an error screen | **MET** | All-nil `FuelExtraction` renders as the ordinary form; `ScannedFillUpSheet` wraps every scan in `ManualFillUpView`, "never presents an error state" – `ScannedFillUpSheet.swift:46-50`; `ManualFillUpView.swift:369-412` (`apply` leaves nil fields blank). |
| Fields blank | **MET** | `apply()` writes only what the extraction resolved; nil stays blank (`ManualFillUpView.swift:398-412`). |
| Keyboard up on Total | **MET** | `focusEmptyScanTotalIfShown()` sets `focus = .total` on appear (`EmptyScanCaption.swift:34-37`), gated on `ConfirmEmptyScanCaption.shouldShow` (`ConfirmPrefill.swift:239-254`). Test proves focus by typing with no tap: `ConfirmManualUITests.swift:665-681`. |
| No "recognition failed" banner | **MET** | Caption is `inkSoft`, "a caption never a banner … never amber" (`EmptyScanCaption.swift:40-44`). |
| Quiet caption, exact copy | **MET** | `EmptyScanCaption.swift:45-52`; core decision `ConfirmEmptyScanCaption.shouldShow` (`ConfirmPrefill.swift:242-253`) shows it only when `hasPhoto` and nothing resolved. |
| Photo **attached at top** | **PARTIAL** | The photo is *carried and persisted* (see Recovery) but is **not rendered** anywhere on the Confirm sheet – `ManualFillUpView.body` (`ManualFillUpView.swift:131-212`) has no photo thumbnail; the only image surface is tap-to-verify crops (`VerifyCropSheet`). The user last sees the photo at the RV.5 review step, not "at top" of the form; the caption's "the photo stays attached" is the reassurance instead. Design artboard `ConfirmManual.dc.html:38` also draws no photo. Substance (photo kept) holds via PJ.2; the literal "at top" is a wording drift, not filed. |

### Recovery – "type 3 numbers (total, liters, odometer), price/unit auto-derives, saves" + photo survives

| Sub-promise | Status | Citation |
|---|---|---|
| Type two, third derives | **MET** | `ManualFillUpMath.derive` derives the third from any two and sets `.notApplicable`; three typed runs the cross-check (`ManualFillUpMath.swift:64-70`). Odometer is a separate field, not part of the triple. |
| Photo survives the save (PJ.2, "whatever the OCR resolved") | **MET** | `ScannedSavePlanner.plan` sets `attachmentID` when `hasPhoto` is true, provenance from the declared `.receiptScan` default (`ScannedSavePlan.swift:119-130`; `ConfirmPrefill.swift:43`); the save writes the photo via `attemptReceiptPhotoWrite` → `writeReceiptPhoto` (`ManualFillUpReceiptSave.swift:203-216, 224-247`). A failed scan's all-nil `FuelExtraction` is **not nil**, so it takes this path (photo attached, provenance `.receiptScan`, empty extraction meta). A write failure still saves and reports (RV.149, `reportLostReceiptPhoto`). |

### Aftermath – "Photo + OCR text silently queued as an (opt-in) improvement sample → Opt-in 'help improve scanning' set once during onboarding"

| Sub-promise | Status | Citation |
|---|---|---|
| Failed scan's photo + OCR text silently queued as an improvement sample | **MISSING** | Searched for any queue of a failed-scan sample: the only feedback path is `FeedbackOutbox` → `POST /feedback`, fed solely by the About composer's typed message (`FeedbackModel.swift:76-104`). No code reads a failed scan's `sourceImage`/`ocrLines` and queues it as a sample. |
| Opt-in "help improve scanning" set once during onboarding | **MISSING** | The consent exists but lives in About & feedback, default OFF, persisted (`FeedbackModel.swift:47-58`; `FeedbackComposerView.swift:157-174`). Onboarding is PJ.3's Welcome (`WelcomeView`), whose doors are Add car / Sign in / Import – no scanning consent. The "once during onboarding" moment does not exist. |

### Metric – "save-completion rate after failed scans ≥85%"

**MISSING (unmeasurable)** – `capture.pipeline` is emitted **only at commit** (`ManualFillUpView.swift:606-610`; `CaptureCommitLog.swift:30-42`), so a failed scan that *saves* is countable (empty `fields`), but a failed scan that is *abandoned* emits nothing – the denominator is unknowable. No "capture verdict" or "session ended without save" event exists (searched `abandon`/`completion`/`resolvedNothing`; nothing). Same shape as RV.225 (F3's unmeasurable metric, filed `polish`).

---

## Sequence trace

One user, one thing: a faded thermal receipt they can still photograph.

1. Home → Capture. Shutter fires → **review step shows the raw photo instantly** (`CaptureView.swift:306-308`), no wait, no spinner.
2. "Use this" → `CapturePipeline.process` runs Vision+QR, resolves **nothing** (`CaptureFillUpScan.swift:27-30`).
3. `ScannedFillUpSheet` opens `ManualFillUpView` with an all-nil extraction + `sourceImage` → **empty form, no error banner, caption `"Couldn't read this one – type it, the photo stays attached."`, keyboard on Total** (`EmptyScanCaption.swift:34-52`; `ConfirmManualUITests.swift:665-681`).
4. User types total + liters; price derives (`ManualFillUpMath.swift:64-70`); types odometer; Save.
5. Save writes the receipt **once** as an `Attachment`, provenance `.receiptScan`, empty extraction meta (`ScannedSavePlan.swift:119-130`; `ManualFillUpReceiptSave.swift:224-247`); entry lands on Home with the photo kept. **The fact the scan failed is carried** – as the caption, the empty extraction, and the attached photo.
6. **Here the story stops being carried.** The Aftermath promises the photo + OCR text silently become an improvement sample; nothing happens. The user would have to separately open Settings → About & feedback, type a message, and enable a consent that was never asked at onboarding. The "help improve scanning" opt-in that the journey says is "set once during onboarding" is neither set nor asked.

Steps 1–5 hold end to end; step 6 is where a promise in the journey has no code.

---

## Proposed rows

| # | Row (one-line deliverable) | Closes | Consequence today | Severity | Check (L1/L4, suite) | Scenario |
|---|---|---|---|---|---|---|
| 1 | **F1 Aftermath: either build the silent improvement-sample queue + onboarding opt-in, or amend the journey text to describe the manual feedback path and mark the silent queue a later phase.** The consent exists in About (`FeedbackModel.swift:47-58`); the queue and the onboarding moment do not. Decide one way and make the journey and code agree in the same change (hard rule: a row that redefines a promise edits the journey text with it). | F1 Aftermath | A failed scan's photo + OCR text is never collected as an improvement sample, so OCR never improves from real failed captures; the "help improve scanning" consent the journey says is asked at onboarding is never asked there. | **gap** | If built: L1 – a failed scan queues the sample only with consent (default off, persisted); an abandoned failed scan emits the sample. If amended: L1 – journey text and code agree (a `REVIEW-SCENARIO` re-walk passes). | F1 |
| 2 | **F1 metric: emit a capture-verdict/session-ended event so "save-completion after failed scans" is answerable from diagnostics.** One Safe field on the capture pipeline marking "resolved nothing" at verdict, plus a session-ended-without-save event – mirroring RV.225's F3 fix, which this duplicates in shape but not in row. | F1 Metric | The headline metric (≥85% finish manually) cannot be measured at all; no abandonment event exists. | **polish** | L1 – a capture that resolves nothing emits the marker; a capture session that ends without a save emits the end event (field names/values only, hard rule 12). Suite: `OB2LoggingEmissionTests` or a new capture-logging L1 suite. | F1 |

---

## Unsettled

- **Whether "photo attached at top" is a literal promise or a superseded wording.** The photo is shown at the RV.5 review step and persisted (PJ.2), but not rendered on the Confirm form. The artboard also draws no photo. This reads as stale F1 text (RV.5 updated J1/J3/J3b, not F1). Settle by amending F1's Verdict wording in the same change as row 1, or by deciding a top-of-form thumbnail is wanted and filing it.
- **Whether the Aftermath's silent queue was a deliberate re-scope to manual feedback** (in which case the journey text is the defect, not the code). Row 1 leaves that decision to the product owner; the review only records that code and journey disagree today.

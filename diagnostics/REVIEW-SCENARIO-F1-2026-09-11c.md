# REVIEW-SCENARIO run: F1 - 2026-09-11c (third walk, after RV.232 deferred to v2)

**Verdict: IMPLEMENTED**

The Aftermath stage is now correctly split: the silent sample queue + onboarding opt-in carry a **[v2]** marker (RV.232 deferred by the product owner, `02e43d4`), and the v1 half - the About & feedback manual path - is MET by PJ.20. The only remaining item is RV.233 (the success metric), a **[v1.0.x] polish** telemetry gap that does not block: per the F3 walk's accepted convention, a journey's "Metric:" line is an aspirational success measurement, not a user-facing promise. Every stage and fallback is MET or reasoned N/A.

## Ticked rows found to be untrue

None. PJ.20 is true for what it built (manual feedback composer, consent default off); it is no longer cited as closing the silent-queue promise, because that promise now carries the [v2] marker.

## Promise-to-code map

| F1 text | Verdict | Evidence |
|---|---|---|
| Capture - "Shutter fires, brief processing shimmer (<2s)"; "never a spinner longer than 2s" | **MET** (wording stale, substance holds) | RV.5's review step supersedes the shimmer: the shutter hands the raw frame to `CaptureReviewView`, pipeline not run yet (`CaptureView.swift:122,139`; `CaptureReviewView.swift:23-29`). After "Use this" (`CaptureReviewView.swift:93`) `CapturePipeline.process` runs with no visible spinner - `isProcessing` guards double-tap only and renders nothing. No spinner exists to exceed 2s; the answer commits immediately. |
| Verdict - "opens empty but alive ... fields blank, keyboard up on Total" | **MET** | All-nil `FuelExtraction` renders as the ordinary form, never an error state (`ManualFillUpView.swift:6,369-412`; `ScannedFillUpSheet.swift:46-50`). |
| Verdict - keyboard already up on Total | **MET** | `focusEmptyScanTotalIfShown()` sets `focus = .total` on appear (`EmptyScanCaption.swift:34-37`), gated on `ConfirmEmptyScanCaption.shouldShow` (`ConfirmPrefill.swift:242-253`). Pinned by `ConfirmManualUITests` (type with no tap). |
| Verdict - no "recognition failed" banner; quiet caption, never amber | **MET** | Caption is `inkSoft`, "a caption never a banner" (`EmptyScanCaption.swift:40-52`). |
| Verdict - "photo attached at top" | **PARTIAL (wording stale)** | The photo is carried and persisted (Recovery below) but is not rendered at the top of the Confirm form - `ManualFillUpView.body` has no photo thumbnail; the user last sees the photo at the RV.5 review step. The artboard `ConfirmManual.dc.html:38` also draws no photo. Substance (photo kept) holds via PJ.2; the literal "at top" is stale F1 text RV.5 never updated. |
| Recovery - "type 3 numbers, price/unit auto-derives, saves" | **MET** | `ManualFillUpMath.derive` derives the third from any two and sets `.notApplicable` (`ios/Sources/TankbookCore/Validation/ManualFillUpMath.swift:64,96-112`). |
| Recovery - "the photo survives the save" (PJ.2, "whatever the OCR resolved") | **MET** | `ScannedSavePlan.plan` sets `attachmentID` when `hasPhoto`, provenance from the `.receiptScan` default (`ios/Sources/TankbookCore/Domain/ScannedSavePlan.swift:112-128`); a failed scan's all-nil `FuelExtraction` is not nil, so it takes this path. The save writes the photo once as an `Attachment` (PJ.2). |
| Aftermath - "Photo + OCR text silently queued as an (opt-in) improvement sample ... set once during onboarding" | **N/A for v1 ([v2])** | The journey text now carries the [v2] marker with the owner's reason (`docs/JOURNEYS.md:493`); RV.232 is deferred to v2. No silent-queue code exists and none is required for v1. |
| Aftermath - "v1: the manual path - About & feedback -> the composer, consent default off (PJ.20)" | **MET** | `FeedbackConsentStore.hasConsented` reads `UserDefaults` defaulting off (`FeedbackConsentStore.swift:27-28`); `FeedbackQueue` enqueues only with consent (`FeedbackQueue.swift:91`); the composer lives on About, reachable from Settings -> "About & feedback" (`AboutView.swift:5,30-31` hosts `FeedbackComposerView`; `FeedbackComposerView.swift:29,160-165`). |
| Metric - "save-completion rate after failed scans >=85%" | **N/A for v1 (RV.233 [v1.0.x] polish, non-blocking)** | `capture.pipeline` is emitted only at commit (`ManualFillUpView.swift:604-607`; `CaptureCommitLog.swift`), so an abandoned failed scan emits nothing and the denominator is unknowable. RV.233 is filed [v1.0.x]; a journey's Metric line is an aspirational measurement, not a user-facing promise (F3 walk's accepted ruling, `REVIEW-SCENARIO-F3-2026-09-11.md`). |

## Sequence trace

One user, one faded thermal receipt they can still photograph:

1. Home -> Capture -> shutter fires -> review step shows the raw photo instantly, no wait, no spinner (`CaptureView.swift:122,139`). **Fact carried: the photo.**
2. "Use this" -> `CapturePipeline.process` runs Vision + QR, resolves nothing. **Fact carried: an all-nil extraction + source image.**
3. `ScannedFillUpSheet` opens `ManualFillUpView` empty but alive - no banner, quiet `inkSoft` caption, keyboard on Total (`EmptyScanCaption.swift:34-52`). **Fact carried: "the scan failed" as the caption + empty fields.**
4. User types total + liters; price derives (`ManualFillUpMath.swift:64`); types odometer; Save.
5. Save writes the receipt once as an `Attachment`, provenance `.receiptScan`, empty extraction meta (`ScannedSavePlan.swift:112-128`); entry lands on Home with the photo kept. **Fact carried: photo attached, scan provenance.**
6. The journey's Aftermath handoff: the v1 manual path (Settings -> About & feedback -> composer, consent default off) exists and is reachable; the silent queue + onboarding opt-in it names as the improvement sample is [v2], so the handoff is out of scope for v1 by the owner's decision.

Steps 1-5 hold end to end; step 6 hands off cleanly for v1 (manual path exists) and defers the queue to v2 with the marker in place.

## Proposed rows (non-blocking)

**1. F1 wording reconciliation - two phrases the shipped code has outrun.**
- Deliverable: (a) replace "brief processing shimmer (<2s)" in the Capture stage with the review-step wording (RV.5's step: the photo shows instantly, the pipeline runs on "Use this", no spinner exists to exceed 2s); (b) replace "photo attached at top" in the Verdict stage with what actually happens - the photo is carried and persisted (PJ.2), last seen at the review step, with the caption "the photo stays attached" as the reassurance.
- Journey stage it closes: Capture and Verdict.
- Consequence today: none for the user (the app keeps the photo and commits to an answer faster than the text implies); the risk is a future reader re-adding a processing spinner or a top-of-form thumbnail because the doc still names one.
- Severity: **polish** (doc-only).
- Check: doc-only; no code/test gate. A later `REVIEW-SCENARIO` re-walk of F1 passes with the text reconciled.
- Scenario id: F1.

## Unsettled

- **RV.233 does not block** - this restates F3's accepted ruling: a journey's "Metric:" line is an aspirational success measurement, not a promise the status line enforces. If the owner wants the metric's flag now rather than at v1.0.x, RV.233's severity lifts to the same build as RV.225; the scenario remains implemented either way because the user-facing story is complete.
- **Whether "photo attached at top" should instead be built** (a top-of-form thumbnail on the Confirm sheet) rather than reconciled away. Proposed row 1 recommends reconciling the text, which matches the artboard and the RV.5 design; a thumbnail is a separate product call and is not required for F1.

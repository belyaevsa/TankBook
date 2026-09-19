# PU.15-REVIEW-LIFECYCLE - the full lifecycle of a pump photo, from shutter to stored entry

Read-only product-and-architecture review, 2026-09-19. One pump-display photograph is walked
through every stage of the shipped product: what exists, what is missing, what can go wrong,
and what the user sees when it does. The model itself is out of scope - the sibling reviews
(`agents/reviews/PU.11-REVIEW-IMPL.md`, `PU.12-REVIEW-DATA.md`) cover the reader's internals and
its training material; where their findings change a lifecycle answer, they are cited, not
re-derived. Evidence: `CLAUDE.md` (rules 1/7/9/12/13/15), `docs/JOURNEYS.md` (J4, F1-F4),
`docs/SCREENMAP.md`, `docs/ERRORS.md`, `docs/EXTRACTION.md`, `docs/VISION.md`, `docs/LOGGING.md`,
`docs/CONFIG.md`, `docs/TASKS.md` (PU, P2.7, RV), `ml/pump-reader/REPORT.md`,
`Spike/ReceiptSpike/fixtures/high-water.json`, and the code under `ios/App/Sources/Capture/`,
`ios/App/Sources/ConfirmManual/`, `ios/Sources/TankbookCore/Extraction/` (incl. `PumpReader/`,
`PumpExtractor.swift`, `Gateway/`), `ios/Sources/TankbookCore/Config/PumpPhotoGate.swift`,
`ios/Sources/TankbookCore/Logging/`, `backend/src/Tankbook.Api/Llm/`. One file written: this one.

## The headline: the product has TWO pump paths, and they are crossed

**Path A - the pump path proper.** `ExtractionSource.pump` selects `PumpExtractor` (the label-
anchor + scale-search resolver, `FuelExtractor.swift:46-64`), suppresses fuel-kind inference
(`:42-44`), suppresses station-name extraction (`:32-34`), enables seven-segment `DigitRepair`
(`:123-137`, `DigitRepair.swift:83` refuses every other source), and is the path the whole PU
programme builds toward (locator → slicer → Core ML classifier → decoder, PU.5). It is guarded by
`PumpPhotoGate` (precision 0.946 < 0.99, coverage 0.175 < 0.60 → the mode is OFF), by the
`pumpPhoto` config flag the remote document may only turn DOWN (`ConfigStore.swift:243`), by the
PJ.12b caption that reads the gate directly (`CaptureView.swift:520-525`), and by the RV.241
Welcome-copy localization gate. **And it is unreachable from any production UI.** All five
`CapturePipeline.process` call sites hardcode `source: .receipt` (`CaptureFillUpScan.swift:28`,
`CaptureExpenseScan.swift:132`, `ManualFillUpReceiptSave.swift:73`, `EditEntryView.swift:676`,
`AttachmentViewerActions.swift:109`); `git log --all -S 'source: .pump' -- ios/App` is empty - no
commit ever passed it from the app target, and in the current tree it appears only inside core
(`PumpExtractor`'s own `DigitRepair` call) and in tests; the only caller of `PumpPhotoCapture.prefill` is a `#if DEBUG`
launch-arg seed (`ConfirmPrefill.swift:236-245`); `ConfigStore.isEnabled(.pumpPhoto)` has zero
production callers. The gate guards a door nobody walks through.

**Path B - the de facto pump path.** Nothing stops a user pointing the camera at a dispenser -
the product owner did exactly that on build 1344 (RV.288's Circle K Gilbarco display). That photo
runs the RECEIPT parser, goes to `/extract` as `kind: "receipt"` (`ManualFillUpView.swift:449`,
hardcoded since P6.3; the backend's registered `pump` kind - `ExtractModels.cs:27`,
`LlmPrompts.cs:94` - has never been sent by any client build, `git log -S 'kind: "pump"'` over
`ios/` is empty), and saves with provenance `.receiptScan`. **This path carries no accuracy
gate.** The hazard the gate's own comment names - a seven-segment display drops its decimal
point, and a factor-of-ten volume is invisible to the scale-invariant cross-check and permanent
in the user's history (`PumpPhotoGate.swift:66-70`, `docs/VISION.md:85`) - applies unchanged when
a pump display is parsed by the receipt ladder, whose label-value "pump form" branches (built for
receipts that print `1,869 EUR/L`-shaped labels, `FuelExtractorLabelValue`, RV.282 §5d) read
exactly the shapes a dispenser prints. What Path B actually produces on a pump photo is
**unmeasured**: the ratchet scores the pump class through `source: .pump` only
(`AccuracyRatchetTests.swift:259`), so the 53/320 mark describes code production never runs, and
no measurement describes the code production does run. One production sample is on file and it is
bad: RV.288's cloud arm returned volume 0.56 / price 1.954 / total 0.00 - a triple that cannot
coexist - and the inbox offered all three as independent corrections (open row; the
cross-check-before-offer fix is RV.288's own proposal).

The two paths' rule guards are crossed the same way. "Never infer fuel kind from a pump photo"
(`docs/EXTRACTION.md` stage 3, the `pump-001` worked example: visible grades are evidence the
station SELLS them) is enforced by `if source != .pump` - structurally unreachable in production,
so a pump photo processed as a receipt runs `detectFuelKind` over the display's grade labels, and
a board printing `АИ95` passes `FuelKindNormalizer.isProductLine` (`octanePattern` matches the
`A[ИH]` form). The RV.71 fuel-mismatch warn catches a diesel CAR; it does not catch a petrol car
photographed at a multi-grade pump. This is `docs/DEFECT-PATTERNS.md`'s "docs naming behaviour
with no call site" shape, inverted: the call site exists, the classification that would reach it
does not.

**In one sentence:** the shipped build has no idea a pump photo is a pump photo - every pump-
specific rule, gate, prompt, provenance and metric is keyed to a classification that no
production code performs.

## The stage table

Exists? = in the SHIPPED app (production callers), not in core/tests. "Test-only" means the code
exists and is exercised by harnesses but has no production call site.

| # | Stage | Exists? | Owner file(s) | Failure mode | What the user sees | Gap |
|---|---|---|---|---|---|---|
| 1a | Door: get to "photograph the pump" | Partial | `CaptureView.swift` (mode row, caption, shutter), `ScannedFillUpSheet.swift` | User photographs a dispenser in Fill-up · auto mode; nothing names it a pump capture | Caption "Receipts are detected automatically" (PJ.12b, gate-tied - honest); Type it and Photos are peer affordances (rule 15 satisfied for the typed door) | No pump door, no pump guidance; J4's first-use tip "no receipt? Shoot the pump" is in the journey text and in zero files |
| 1b | Camera: framing, glare, distance | Partial | `CameraCapture.swift:60-85` (`.photo` full-res preset, `.near` focus restriction) | Glare/dark frames - the pump corpus's dominant failure (pump-067, the washed Wayne LCDs) | Nothing: no torch, no dark hint, no framing reticle | ERRORS.md:245-246 promises "Dark – tap for torch" and the ~4 s "Fill the frame" hint; `rg torch\|glare\|dark` over `ios/App/Sources`: zero hits. Docs name behaviour with no call site |
| 1c | Burst vs single frame | Single only | `CameraCapture.swift:90-104` (one `AVCapturePhotoSettings()` shot) | One bad frame is one bad capture; no temporal median against glare/aliasing | Re-take loop at the review step | PU.11 Q1 and PU.12 Q5 both ask for 3-5 frames; no product decision exists |
| 1d | Resolution + EXIF orientation | Yes (Vision side) | `.photo` preset (3024x4032 class); RV.49: rotation baked via `videoRotationAngle`, EXIF kept via `fileDataRepresentation` + `UIImage(data:)`, orientation mapped for Vision (`CapturePipeline.swift:37,126-138`) | Picker-sourced photos carry EXIF orientation the camera path already baked; Vision is told the truth | Correct reading for camera shots; rotated Photos picks are handled on-device | The GATEWAY rendition does NOT get the same treatment (stage 5) |
| 2 | Classification receipt vs pump | **No** | `CapturePipeline.process(source:)` - a caller-chosen constant, `.receipt` at all five call sites | Cannot misclassify - it never asks | A pump photo is indistinguishable from a receipt to the whole downstream product | `docs/EXTRACTION.md` pipeline stage 3 ("classify → ExtractionSource") has no implementation; every pump guard downstream is keyed to it |
| 3a | Locate (number windows) | Test-only stub | `PumpPanelLocator.swift` (classical CV, "deliberately not polished") | Median IoU 0.008 over the corpus; one fixture (pump-078) at 0.61 | Nothing (unreachable) | PU.11 F14: Vision-as-proposer or user-tapped crop; no row owns it past PU.4's partial |
| 3b | Warp | Test-only | `PumpQuadWarp.swift` | Strip-height contract disagrees across harness (96 px) / scorer (48 px) / training (~40 px) | Nothing | PU.11 F5, PU.12 §9: one declared contract height before PU.5 freezes the device path |
| 3c | Slice (glyph cells) | Test-only | `PumpGlyphSlicer.swift` (Otsu, LCN, autocorrelation pitch, grid snap) | Count agreement 259/433 (0.598) against a 0.80 target; wayne under-counts, scheidt over-counts | Nothing | PU.11 F3/F6/F7: candidate grids scored by classifier likelihood; leading-blank emission is pure loss |
| 3d | Classify (segment CNN) | Resource ships, loader does not | `ios/App/Resources/PumpSegments.mlpackage` (64 KB, in the app target via `project.yml:27`); no Swift loads it (`rg MLModel ios/App/Sources ios/Sources`: zero) | Held-out per-glyph 0.400 cc / 0.309 all; dp bit dead on real cells (AUC 0.52, PU.11 F2); confidence barely ranks errors (flat coverage curve, PU.11 F11) | Nothing; the app carries a dead 64 KB resource | PU.5 builds the wrapper; PU.11 F11 says no abstention policy on current outputs reaches the 0.99 gate |
| 3e | Decode (segments → digits) | Python only | `decode_constrained` (PU.16, digit-only 0.666); no Swift decoder | Threshold decoding emits patterns no display shows (25.5% `?`) | Nothing | PU.5 must port the constrained decode; row says so |
| 3f | Row assignment + decimal recovery | Design only (rules path exists) | `docs/EXTRACTION.md` "The pump reader" steps 4-5; `PumpExtractor.solve` (uniqueness law) is the rules stand-in | The decimal point is the whole ballgame: not-unique → nil, never a guess | Nothing (Path A unreachable) | PU.5; PU.11 F13 sketches it - cell count as the external scale pin kills the pump-009 factor-of-ten class by construction |
| 3g | Cross-check | Yes (both paths) | `CrossCheck.swift` (four outcomes), `PumpExtractor.solve` (exact-close + unique-repair law), `DigitRepair` (pump-only) | a×b==b×a: the swap and the joint decimal shift are invisible to it | Amber underline + "these don't multiply up – check the amber field" (`ManualFillUpSections.swift:280-284`); repair keeps `mismatch`, never locks | Sound where it runs; on Path B it can LOCK a pump-derived triple that only looks consistent |
| 3h | Threading / latency | Yes (receipt pipeline) | `CapturePipeline.recognize`: `Task.detached(.userInitiated)`, Vision through `VisionRequestGate` (background dispatch, never a cooperative thread) | F1's <2 s shimmer promise; the future reader adds locator + ~200 CNN inferences (trivial per PU.11 F3) but has NO documented budget | Processing beat between "Use this" and the Confirm sheet | PU.5 needs a per-stage latency budget and a decision on where the reader runs relative to Vision |
| 3i | Per-stage diagnostics | No | Would be `docs/LOGGING.md` §4: stage name, durationMs, window/glyph COUNTS, outcome codes, model version - all Safe class | The decoded digits can never be logged: OCR text is Never-class, values are Sensitive (§1) - diagnostics must be counts and codes only | Nothing | No pump stage emits anything; `capture.pipeline` carries one duration for OCR+QR+assembly |
| 4 | Gate + flag | Yes, honest | `PumpPhotoGate.swift` (53/56 committed-correct = 0.946 precision; 56/320 = 0.175 coverage; thresholds 0.99/0.60), ratchet asserts constants == live corpus (`AccuracyRatchetTests.swift:231-248`), remote-cannot-enable (`ConfigStore.swift:243`), bundled default off, rolloutPercent 0 | Constants drift → the ratchet test fails the build (good); runtime-specific Vision → the suite skips off macOS 26 (RV.295 open: does iOS 27 move the numbers? unknown) | Below the gate: caption says receipts only; Welcome copy gate (RV.241) refuses a pump claim; a pump photo still enters via Path B, ungated | The gate governs Path A only. Nothing gates Path B; `isEnabled(.pumpPhoto)` has no consumer, so "the flag" is presently decoration around the caption |
| 5a | Cloud arm: when/what | Yes, pump-blind | `ManualFillUpView.startGatewayReading` (~:438-465): fires on Confirm-sheet load when a photo exists, signed in, `config.allowsServerBacked`, JPEG rendition | Pump photo sent as `kind: "receipt"` → the model reads a dispenser with a receipt prompt | Proceed note ("A more reliable reading may still arrive…") or nothing | Backend `pump` kind is dead code from the client's view; RV.289 (pump prompt has no layout hint) is written against a kind no build sends - reconcile before briefing |
| 5b | Ledger / storage | Yes | Rule 9's LLM-ledger amendment: `llm_calls` stores caller, model, tokens, cost, prompt AND response bodies, image by sha256 in blob storage; 30-day retention; write-only (no read endpoint); write queue (migration 021) + delivery outbox bounded the same way | Unmetered spend is the failure the ledger exists to prevent | Invisible (correctly) | The pump photo IS in blob storage for 30 days today, under the receipt kind, for every signed-in capture |
| 5c | Offline path | Yes | F3/F4 implemented: no gateway without a session/network; on-device result stands; `.required` withholds the call | Offline pump photo = Path B local parse only | Identical to online minus the proceed note; nothing sync-gated (rule 1) | RV.225 open: no capture event says whether it happened offline, so F3's own metric is unmeasurable |
| 5d | Merge of the two readings | Yes (receipts) | Within budget: fill BLANK-AND-UNTOUCHED only (`GatewaySuggestionPolicy`); late: inbox per-field ticks, "leave it as it is" default (RV.38/RV.45, `GatewayInboxPolicy`) | A cloud pump reading contradicts itself (RV.288's 0.56 × 1.954 ≠ 0.00) and is offered field-by-field anyway; local vs cloud disagreement has no arithmetic referee at OFFER time | Inbox card "yours vs the receipt" - and it says "receipt" for a dispenser (RV.290 open) | RV.288's cross-check-before-offer is the fix; the pump/receipt two-source case (stage 6) is undecided |
| 5e | Rendition orientation | **Suspect** | `GatewayRendition.jpegData(from: CGImage)`; all three callers pass raw `image.cgImage` (`ManualFillUpView` ~:446, `ExpenseEntrySession.swift:171-173`, `ServiceInvoiceSession.swift:143`) | A `CGImage` carries no orientation and the re-encode writes no EXIF tag: a Photos-picked frame with EXIF orientation 6/8 uploads SIDEWAYS. Camera shots are fine (rotation baked, RV.49). The corpus holds rotated fixtures (pump-069, receipt-050/-051) precisely because this happens | Cloud reading silently worse on rotated picks; nothing surfaces it | RV.49's fix stopped one seam short of its sibling (DEFECT-PATTERNS: sibling defects). Needs a verify-then-fix row; seam named |
| 6a | Confirm: suggestion presentation | Yes, source-agnostic | `ManualFillUpView.apply` (:369-411), `ConfirmConfidenceGate` (60% dim until tap/edit), crops + `VerifyCropSheet` (tap-to-verify, F2's "show the source crop") | Rule 13 satisfied mechanically: every pre-filled field stays editable, engagement is permanent, gateway never refills a touched field | Dimmed DIN figures, magnifier per resolved field, amber mismatch line | Nothing distinguishes a pump-derived value; the dim is uniform (the 0.9 default confidence in `ScannedSavePlanner.onDeviceConfidenceDefault` is a documented placeholder, not a signal) |
| 6b | Nil / abstain | Yes | All-nil extraction = F1 "empty but alive": photo attached, quiet caption, Total focused | Abstention is honest - but on Path B an ABSTAIN is the good outcome; a plausible COMMIT from pump glyphs is the bad one, and it looks identical to a receipt read | Empty form + "Couldn't read this one – type it, the photo stays attached." | The factor-of-ten class has only residual mitigations on Path B: tank-capacity warn, odometer delta (PJ.14), consumption-outlier pose (RV.218) |
| 6c | Odometer (never on the pump) | Yes | Pre-filled from last known (`ManualFillUpView.load`), delta caption, F9a validator + ranked fixes (PJ.34) | A pump photo carries no odometer; the field is always the user's | Pre-filled last-known value, "+N km since last" caption | `docs/VISION.md:217`'s "receipt on the dash" pattern (odometer in frame) is unexplored and would need the pump-classifier first |
| 6d | Station on a pump capture | Yes | PJ.19 ranking (`StationSuggestion`, local, rungs 3-4 need no permission); pump source correctly skips station-name extraction | Path B does NOT skip it: `StationNameExtractor` runs over display/forecourt text | Suggested station row, changeable, add-door | Same unreachable-guard family as fuel kind |
| 7a | Persistence | Yes | `ScannedSavePlanner` (provenance, `ExtractionMeta` per field: value + confidence + `userCorrected`), `FillUp.provenance/.extraction`, `Attachment` (JPEG q0.8 via `UIImage.jpegData`, `ocrText`, thumbnail, `extractionMeta` incl. station, RV.184) | `.pumpPhoto` provenance is never written in production, so the stored record cannot tell a pump capture from a receipt scan after the fact | Paperclip on the Log row; "What was read" page in the viewer | Provenance is the natural carrier of the missing classification - and it is declared by the capture, which never declares pump |
| 7b | Sync | Yes | `docs/SYNC.md`: record payloads opaque (rule 9), blob = sync rendition JPEG ≤2048 px q~80, thumbnail inline, lazy fetch + prefetch (PJ.35) | A pump photo syncs like any receipt; full-res original never leaves the device | Non-event (correct) | The ≤2048 rendition is what a future re-read (on-device or cloud) gets, not the 12 MP original - a re-scan years later reads a downsampled frame |
| 7c | 30-day undo | Yes | Tombstones + Recently deleted; attachment tombstone waits for the orphan sweep, which protects blobs inside the window | Covers entries and attachments uniformly | Recently deleted (30 days) | None |
| 7d | "Re-scan" later | Yes | PJ.48 attach / RV.37 replace (`AttachmentViewerActions.handleReplace`): re-runs `CapturePipeline` - `source: .receipt` again - fill-BLANKS-only (`ReceiptAttachMerge`), ask before applying | A pump photo re-attached to a typed entry runs Path B; a late cloud answer re-arrives via inbox | "Add receipt" door on Edit entry; ask, never silent | Same classification gap; rule 13 respected (blanks only, user ticks) |
| 8 | Feedback loop | Partial, learns nothing | `CaptureCommitLog` → `capture.pipeline` (field NAMES + confidence + crossCheck + aggregate `userCorrected`, Safe class only); `ExtractionMeta.userCorrected` persists per field on the entry/attachment | Nothing collects corrections; v1 has no consent surface (product owner 2026-09-11: cloud OCR on by default, no opt-in/out; F1's improvement sample is [v2]) | Nothing | The corrected-cell training set is ASSEMBLABLE from data already on device: photo (attachment) + what the scan proposed (`extractionMeta.value`) + what the user saved (entry) = exactly (input, wrong output, right output) triples. Collecting it is a fifth user-content store: rule 9 requires its own written decision, consent, retention; PU.12 Q9 recommends not yet |
| 9a | Corpus ↔ gate ↔ build | Yes | Ratchet asserts gate constants == live score; `high-water.json` records 53/320 committed 56; runtime-specific (macOS 26 Vision) | The ratchet measures Path A, which ships unreachable - a green ratchet says nothing about what users experience | Nothing | RV.295 (iOS 27 device measurement) open; RV.114 (rotated fixtures, pump/receipt pairs) open |
| 9b | Production number for "the feature works" | **No** | `capture.pipeline` carries no source/kind field; provenance `.pumpPhoto` never written; J4's metrics (pump share ≥15% of captures, ≥95% confirm accuracy) have no feed | Even after the gate opens, nobody could tell whether pump capture is used or works | Nothing | RV.225 is the sibling (offline flag); a Safe `source` field on `capture.pipeline` is the cheap fix |
| 9c | Docs honesty | Drifting | ERRORS.md:273 cites "receipts 88/175, pump 21/84" (live: 286/345, 53/320); VISION.md:85 cites "24 of 178 across 66 photographs, every committed value correct" (live: 56 committed of 320 across 114, THREE committed-wrong per `PumpPhotoGate.swift:45-48`); TASKS P2.7 cites "0/30" | Stale prose on live controls | Nothing | PR.32 owns `PumpPhotoGate.swift:22-29`'s numbers; the ERRORS/VISION/P2.7 vintages have no row - PU.6's doc reconcile is the natural owner but fires only at the ship decision |

## Gaps ranked by user impact, each with a proposed row

**G1. Path B is ungated and unmeasured (stage 2/4/9a).** Users photograph dispensers today; the
receipt parser answers; the answer is unmeasured on the one corpus that could measure it; the
cross-check can lock a seven-segment-derived triple; the cloud arm demonstrably returned a
self-contradicting one (RV.288). This is the confident-wrong-value class rule 13 exists to
prevent, live in production, on the exact document type the gate was built for.
*Proposed row (measurement first, decision second):* **"Score the pump corpus through the receipt
path"** - (J4 pump display photo; F2 scan recognised WRONG data) run all 114 pump fixtures through
`FuelExtractor.extract(source: .receipt)` with the live scorer and record, per fixture: cells
committed, committed-correct, confident-wrong by name, fuel-kind and station-name commits from
display text. The number decides the next row: a minimal classifier, a documented acceptance, or
an urgent guard. *Check:* L5 harness output committed beside `high-water.json` (a new
`pump-as-receipt` column, never mixed into the pump mark); the row names every confident-wrong
fixture; vacuous trap: reporting "the parser mostly abstains" without the committed-cell counts.
*Owner today: none - file.* (RV.288/289/290 own cloud-side symptoms; no row owns the local arm.)

**G2. The classification stage does not exist (stage 2).** `docs/EXTRACTION.md` pipeline stage 3
is documentation with no call site; five production call sites answer the question by constant.
Every pump-specific guard (fuel kind, station, digit repair, the gate itself, provenance, the
gateway kind, the inbox copy) hangs off an enum value production never sets.
*Proposed row:* **"ExtractionSource is decided by the document, not by the call site"** - (J4;
F2) either (a) a minimal deterministic classifier over `[OCRLine]` in core (pump label vocabulary
`ЛИТРЫ/LIITRIT/СУММА/HIND` + no-operand-pair + no-fiscal-QR is already most of the signal, and
`PumpExtractor.role(of:)` is the vocabulary), consulted by `ExtractionAssembler` when the caller
says `.receipt`, or (b) a written product decision that fill-up capture MEANS receipt and the
pump guards are re-homed. Decide-then-do, G1's number first. *Check:* L1 over the corpus OCR
dumps: the 114 pump fixtures classify `.pump`, the 70+ receipt fixtures stay `.receipt`, the two
matched pairs agree; mutation: a pump dump with the label lines removed must NOT classify pump
(the classifier abstains to receipt, never guesses); the `source != .pump` fuel-kind guard becomes
reachable and a pump-shaped line set yields nil kind. *Owner: none - file; PU.5's "wired as the
.pump source behind the P2.7 flag" presumes a classifier nobody has rowed.*

**G3. The cloud arm sends the wrong kind and the wrong prompt (stage 5a/5d).** The backend
registered `pump` in `ExtractKinds` and gave it a one-line document name; no client build has ever
sent it; RV.289's planned pump prompt fixes a kind that is dead from the client's view; RV.288's
inbox offers a contradictory triple because `GatewayInboxPolicy.fuelOffers` never runs the
reading's own arithmetic. Three open rows already own pieces - the lifecycle finding is that they
must land in one order: RV.288 (offer gate, core) → RV.289 (kind + prompt + L5 sweep) → RV.290
(copy), and RV.289's step 1 ("read the ledger response") now has a sharper question: **the ledger
row RV.288 cites says `kind: "pump"`, but no client build ever sent one** - either the ledger read
or the row's premise is wrong, and the brief should say which.
*Proposed action:* no new row; add the discrepancy as a comment on RV.289 and let its
decide-then-do step 1 resolve it. *Check:* RV.289's own (L2 prompt test + the on-demand L5 pump
sweep through the live provider).

**G4. Camera guidance promised, not built (stage 1b).** ERRORS.md:245-246 catalogues a torch hint
and a 4-second "fill the frame" hint with next steps; neither exists in any source file. Pump
displays are the glare-and-dark case par excellence (the corpus's washed Wayne LCDs, night-lit
Scheidt faces). A catalogued error state that cannot occur is the DEFECT-PATTERNS doc-drift shape
and fails ERRORS.md's own 3-question audit rule.
*Proposed row:* **"Build the ERRORS.md capture hints or strike the rows"** - (J4; F1) implement
torch + dark hint + idle hint per the catalogue, or amend ERRORS.md in the same change and say
what replaced them. *Check:* L4 `CaptureUITests` for the torch affordance appearing on a seeded
dark frame (or the doc diff alone if struck); EN + RU screenshots if built. *Owner: none - file.*

**G5. The gateway rendition drops EXIF orientation (stage 5e).** RV.49 fixed the Vision seam
("an in-app photo reaches Vision sideways without it"); the sibling seam - `image.cgImage` handed
to `GatewayRendition.jpegData` with no orientation, re-encoded with no EXIF tag - was not fixed,
on all three cloud paths (fuel, expense, invoice). Camera-path frames are physically rotated and
safe; Photos-picked and shared frames are not. Verify first (one UI-free L1: encode an oriented
`UIImage`, decode the rendition, compare pixel geometry), then fix at the shared seam.
*Proposed row:* **"Gateway rendition carries orientation"** - (J3; J4; F4) pass
`CGImagePropertyOrientation` (the mapping already exists in `CapturePipeline.swift:126-138`) into
the rendition or normalize before encoding; one seam, three callers. *Check:* L1 with a rotated
fixture: rendition pixels upright; mutation: drop the orientation argument, test red. Corpus
relevance: pump-069/receipt-050/-051 are the rotated fixtures RV.114 already asks about. *Owner:
none - file; name RV.49 as the sibling.*

**G6. No production number can ever say the feature works (stage 9b).** J4's success metric
(pump-photo share ≥15%, ≥95% confirm accuracy) has no feed: no event carries the capture source,
provenance `.pumpPhoto` is never written, and `capture.pipeline`'s `userCorrected` is an
aggregate. RV.225 already adds one Safe field (offline) to this exact event; the source/kind field
is the same shape and the same discipline (a code, never a domain value).
*Proposed row:* **extend RV.225** rather than filing fresh: "one Safe field on `capture.pipeline`
from the path monitor's last status" becomes two - `offline` and `source` (receipt/pump/
screenshot/expense/invoice, from the classification G2 lands or from the declared capture mode
until then). *Check:* RV.225's own (L1, field name and value only, hard rule 12).

**G7. The "gate on" Confirm experience is untestable today (stage 4/6).** The DEBUG seed
`-seedPumpCapture` routes through `PumpPhotoCapture.prefill(pumpPhotoEnabled:
PumpPhotoGate.allowsPumpPhoto)` - and the gate is a compiled constant that is false in every
build, so no UI test or screenshot can render the state J4 will ship in (a pump pre-fill on the
Confirm sheet). When PU.5/PU.6 open the gate, the L4 evidence P2.7's own row promises ("flag-on
pump capture pre-fills") has no seam to run through.
*Proposed action:* fold into PU.5's brief: the gate needs an injectable seam (the codebase's
standard pattern) or the seed needs to pass the flag state directly; plus EN + RU screenshots of
the pump Confirm state the day the gate opens. *Check:* PU.5's L4 list names the pump-prefill
frame; the screenshot manifest gains the lines.

**G8. Doc vintage drift on the pump numbers (stage 9c).** ERRORS.md ("21/84"), VISION.md ("24 of
178 … every committed value correct", "66 photographs"), TASKS P2.7 ("0/30") all predate the live
mark (53 correct of 56 committed over 320 cells, 114 fixtures, precision 0.946 - THREE committed
values are wrong, which VISION's "every committed value correct" now contradicts). PR.32 owns
`PumpPhotoGate.swift:22-29`'s stale comment only.
*Proposed action:* PU.6's doc-reconcile step is the natural owner, but it fires "whichever way
the ship decision goes" - the ERRORS.md disclosure line is user-trust copy and should not wait
for PU.6; fold it into PR.32's list or fix with G1's measurement row. *Check:* reviewed diff;
`scripts/tasks-index.py --check` 0.

**G9. Dead model resource in the shipping bundle (stage 3d).** `PumpSegments.mlpackage` (64 KB)
is in `ios/App/Resources`, therefore in the app target, and no code loads it. Harmless at 64 KB,
but it is an unexercised binary artifact in a submitted build, and App Review has asked about
unexplained ML resources before. PU.5 makes it live; until then it could equally live in the
package's test resources.
*Proposed action:* one sentence in PU.5's brief (load it or move it); no standalone row.

## What I would need to know or have (ranked questions to the product owner)

1. **May a pump photo go to the cloud by default TODAY?** It does: every signed-in fill-up scan
   with a photo fires `/extract` (v1 cloud OCR is on by default, decided 2026-09-11), and nothing
   distinguishes a dispenser shot - so pump frames are in the 30-day ledger and blob store now,
   read with a receipt prompt that produced RV.288's garbage. Was the "on by default" decision
   meant to cover a document type the build makes no claim to read? If not, the cheapest honest
   stop is a decision, not a classifier: e.g. withhold nothing (accept), or land G2's minimal
   classifier first and send `kind: "pump"` (RV.289) only after its prompt exists.
2. **What should the shipped build DO with a pump photo while the gate is off?** Three coherent
   options: (a) today's behaviour - parse as a receipt and accept the unmeasured risk; (b) G2's
   classifier routes pump frames to the F1 empty-but-alive form (photo kept, "type it" caption -
   an honest head start, zero confident-wrong values); (c) a user-visible pump door that says
   "coming soon" (worst: advertises the feature the gate exists to hide). G1's measurement should
   decide between (a) and (b); my reading of rules 13/15 is that (b) is the only one consistent
   with "a confident wrong value is worse than a nil" - but that is your call, and it is a call
   about the RECEIPT-path risk, which no gate currently owns.
3. **When the pump reading and the receipt disagree, who wins?** The corpus already holds the
   cases: pump-031's display shows 32.58 while the receipt's discounted truth is 32.50;
   pump-072's transaction price (1.894, loyalty) is not on the board at all; the pump-067/068 +
   receipt-049/050 pairs are the same fill from two devices. `docs/EXTRACTION.md` settled
   list-vs-effective price for receipt/app pairs ("a document can carry two truthful unit
   prices") but nothing says what Confirm shows when the user scanned BOTH, or whether a saved
   fill may be cross-checked against a twin document scanned later (the inbox machinery is
   already per-field). This is a product decision PU.5's row assignment will inherit.
4. **Burst capture: yes or no?** Both sibling reviews independently rank 3-5 frames as the single
   biggest lever on the 0.99-precision gate (temporal median kills glare, aliasing and dp-dot
   loss; PU.11 Q1, PU.12 Q5). It changes the shutter UX, the review step (which frame does the
   user judge?), storage (the attachment keeps one photo) and the rendition contract. If the
   answer is no, the render side must carry the whole noise budget alone and PU.6 should know
   that was a decision, not an oversight.
5. **Is a two-tap display crop an acceptable v1 locator?** (PU.11 Q6, from the product side.)
   The locator is at IoU 0.008; a tap-to-frame crop on the review step always works, is honest,
   and is rule-15-shaped (a peer path, not a failure branch). If yes, PU.5 can score end-to-end
   on oracle quads while the crop ships, and the automatic locator becomes an enhancement with
   its own row. If no, the locator needs a row before PU.5 means anything end-to-end.
6. **Camera guidance for dispensers: what did you picture?** J4's deltas promise a first-use tip
   ("no receipt? Shoot the pump") and ERRORS.md catalogues torch/dark/idle hints that were never
   built. With the mode off, the tip presumably ships with the gate (PU.6) - but the torch and
   glare hints help EVERY capture and are catalogue rows with no code. Build, strike, or defer to
   a named row?
7. **Corrected cells as a future training set: when do we decide?** The triples (photo, what the
   scan proposed, what the user saved) already exist on-device per `ExtractionMeta`; collecting
   them is a fifth user-content store under rule 9 (its own written decision, consent surface,
   retention - the 30-day precedent does not transfer automatically), and PU.12 Q9 recommends
   not yet. Do you want the decision point named (e.g. "after PU.6, if the synthetic chain
   stalls") so it is a choice rather than a drift?
8. **Reconcile RV.288's ledger claim.** The row says the build-1344 call carried `kind: "pump"`;
   no client build ever sent one (`git log -S` over `ios/` is empty; the kind has been the literal
   `"receipt"` since P6.3). Either the ledger row was read from a different field or the premise
   of RV.289's pump-prompt fix is aimed at a call that cannot happen. One look at the `llm_calls`
   row settles which - and it changes what RV.289 step (1) concludes.
9. **What does "re-scan" mean for a pump entry years later?** Sync keeps a ≤2048 px rendition,
   never the 12 MP original; a future on-device reader (or a re-attach through PJ.48) re-reads the
   downsampled frame, and the PU pipeline's framing sensitivity (a framing change alone moved
   per-glyph by a third, REPORT.md) says resolution is not a detail. Is the rendition size a
   product commitment to revisit when the reader ships, or is "the photo you can see is the photo
   we keep" the answer?

## Found and not fixed (this review writes no code)

| finding | owner |
|---|---|
| Path B ungated/unmeasured (G1) | **none - file** (RV.288/289/290 own cloud symptoms only) |
| No classification stage; pump guards unreachable (G2) | **none - file**; PU.5 presumes it, PU.6 files "from measurement" |
| Client never sends `kind: "pump"`; backend pump prompt dead from the client's view; RV.288's ledger claim vs code (G3, Q8) | RV.289 step 1 - add the discrepancy to the row before briefing |
| Inbox offers a self-contradicting reading; no arithmetic at offer time | RV.288 (open, fix specified) |
| Inbox says "receipt" for a dispenser reading | RV.290 (open, polish) |
| ERRORS.md torch/dark/idle hints catalogued, never built (G4) | **none - file**; ERRORS.md's own audit rule |
| Gateway rendition drops EXIF orientation on all three cloud paths (G5) | **none - file**; sibling of RV.49, seam named (`GatewayRendition.jpegData` + its three callers) |
| No production feed for J4's metrics; `capture.pipeline` has no source field (G6) | RV.225 (open) - extend, same seam, same discipline |
| Gate-on Confirm state has no test/screenshot seam (G7) | PU.5's brief should name it; PU.6 walks J4's review |
| Doc vintage drift: ERRORS.md:273, VISION.md:85, TASKS P2.7 "0/30" (G8) | PR.32 owns the `PumpPhotoGate` comment only; the rest **has no row** - fold into PR.32 or PU.6 |
| `PumpSegments.mlpackage` ships in the bundle with no loader (G9) | PU.5 (load it) - one sentence in the brief |
| iOS 27 runtime may move every Vision number the gate rests on | RV.295 (open) |
| Rotated pump/receipt fixtures unscored; pairs never cross-checked | RV.114 (open) |
| Ratchet scores only Path A; a green pump ratchet is not evidence about the shipped app | consequence of G1/G2; the measurement row's check covers it |

## Method and checks

Read-only: no code, fixture, gate or corpus file was touched; the only write is this file. No
build or test gates were run - nothing compiled or executed changed, which is the one case
`docs/TESTING.md` releases from the baseline gate; the sibling reviews ran the harnesses and
their reproduced numbers (count agreement 259/433, per-glyph 0.400 cc, dp AUC 0.520, decode 0.666)
are cited from their reports rather than re-run. Evidence commands, all exit 0: `rg`/`grep` over
`ios/App/Sources`, `ios/Sources/TankbookCore`, `backend/src`, `docs/`; `git log -S 'kind:
"pump"'`, `git log -S 'source: .pump'`, `git log -S 'kind: "receipt"'` (the last: one commit,
P6.3, 2026-08-28 - the kind has never varied); reads of every file named in the stage table.
Corpus numbers are quoted from `Spike/ReceiptSpike/fixtures/high-water.json` (pump 53/320,
committed 56, note of 2026-09-18) and `PumpPhotoGate`'s constants, cross-checked against each
other; where the docs disagree with them, both vintages are named above rather than reconciled
silently.

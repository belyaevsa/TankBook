# REVIEW-SCENARIO J1 – 2026-09-11c

**Verdict: NOT IMPLEMENTED.**

## Ticked rows found untrue

None. All four closed v1 rows naming J1 are true in the code:

| Row | Claim | Verdict | Evidence |
|---|---|---|---|
| `PJ.3` | Welcome root, three paths, never reappears once a car exists | MET | `WelcomeView.swift:127-201` (three doors + restore); `WelcomeGate.swift:95` (no vehicle AND no session); `WelcomeRootView.swift:65-71` (`onFinished` the moment a car/session lands) |
| `RV.5` | First shot reviewed before anything is read | MET | `CaptureView.swift:139-144` (review cover), `:306-308` (`processScanned` sets `reviewSubject` without running OCR); `CaptureReviewView.swift:39-118` (Use this / Re-take / Type it) |
| `RV.23` | First launch copy names why an account is worth having; sign-in is a peer door; "Add your car" continues with no account | MET | `WelcomeView.swift:161-185` (peer sign-in door + benefit line), `:127-141` (Add car, taillight, no account gate); `WelcomeRootView.swift:47-53` (`SignInRequest` carries restore intent) |
| `PJ.51` | Store listing copy names what the build does | MET (docs) | `docs/TASKS.md:791` DONE note; store copy no longer names "electric"/six importers. See finding: it did **not** extend to the in-app Welcome copy |

`PJ.42` (bundled demo receipt) is `[v1.x]` and deferred – N/A for v1. `SH.3` is deprecated and not a backlog row.

## Promise-to-code map

| Journey stage / note | Status | Evidence (or what is missing) |
|---|---|---|
| **Open** – one screen, skippable, three paths ("Add your car", "Import", "Sign in") | MET | `WelcomeGate.swift:95`; `WelcomeRootView.swift:34-39`; `WelcomeView.swift:127-201`. Sign-in peer; Add car continues with no account. |
| **Open** – the Welcome copy names only what the build does | **MISSING** | `WelcomeView.swift:89` tagline "Fuel, charging and service – one log" names EV charging (v2, `PJ.49` – "an EV cannot log a single charge"); `WelcomeView.swift:103` "Scan receipts and pump displays" names pump scanning, which ships off (`PumpPhotoGate.allowsPumpPhoto == false`, `PumpPhotoGate.swift:96-98`). Artboards carry both: `design/screens/Welcome.dc.html:25,32`, `LightWelcome.dc.html:25,32`. |
| **Add car** – make/model or plate, powertrain, home currency pre-filled from locale | MET | `AddVehicleView.swift:31-51`; `AddVehicleForm.swift:37-39` (`LocaleCurrency.defaultCurrency`, `VehicleDefaults.defaultFuelKinds`) |
| → RU locale defaults to ₽ + RU fuel grades | MET | `LocaleCurrency.swift:12` (RU → RUB); `VehicleDefaults.swift:15` (RU → `[.petrol92, .petrol95]`); ₽ glyph `AddVehicleForm.swift:155` |
| → photo of car optional | MET | `AddVehicleView.swift:31` (`VehiclePhotoTile`), `:186-194` (photo written only when present) |
| **First entry** – prompted to scan | MET | Guest home capture card `HomeGuestLayout.swift:176-209` ("Scan your first fill-up"); signed-in empty state `HomeEmptyStates.swift:20` ("Scan or type your first fill-up"). Scan door is the tab-bar capture circle (`AppTabBar.swift:193-217`). |
| → the first scan IS onboarding | MET | Capture is the natural next step; review step precedes any read (`RV.5`, above). |
| → bundled demo receipt if they have none | N/A | `PJ.42` is `[v1.x]`, deferred (not blocking per brief). |
| → RV.5: first shot reviewed before read | MET | `CaptureView.swift:306-308`; `CaptureReviewView.swift` (whole screen). |
| **Payoff** – Pump Card lock ✓, entry saved | MET | Cross-check lock `ManualFillUpSections.swift:291-321` (✓ when `crossCheck == .verified`, never gates save); save `AddVehicleView`/`ManualFillUpView` + `toastCenter.noteEntryChanged()` reloads Home (`HomeView.swift:130-134`). |
| ⚠ confidence gating | MET | `ManualFillUpFormState.swift:70-72` (resolved-but-unconfirmed fields dim at 60%, `P2.3`); currency low-confidence asks (`ConfirmPrefill.swift:47`, `ERRORS.md:271`). |
| ⚠ instant manual fallback without losing the photo | MET | `CapturePipeline.swift:43-49` attaches `sourceImage` even when OCR resolves nothing, so the empty manual form keeps the photo (the F1 empty-but-alive state). |
| ⚠ review step catches a bad frame before it reads as bad recognition | MET | `CaptureReviewView.swift` – one image, accept/re-take before any OCR (`CaptureView.swift:303-305`). |

## Sequence trace (one user, one first session)

1. Fresh install → `WelcomeGate` (no vehicle, no session) → Welcome root. **OK.**
2. "Add your car" → `AddVehicleView`; name/make/plate/powertrain, currency+fuel defaults from locale, optional photo; Save → `upsertVehicle` → `noteEntryChanged` → dismiss. **OK.**
3. `WelcomeRootView.reevaluate()` sees a vehicle → `onFinished` → tabs replace Welcome. **OK.**
4. Home, no session → `isGuest` (`HomeView.swift:180-186`) → `HomeGuestLayout` with garage card + capture card "Scan your first fill-up". **OK.**
5. Capture (tab-bar circle) → `CaptureView` → shutter → `reviewSubject` (review cover, no OCR yet). **OK.**
6. "Use this" → `acceptReview` → `CapturePipeline.process` (Vision OCR + QR, sourceImage kept) → `ConfirmPrefill` → `ManualFillUpView` pre-filled, fields dimmed, cross-check lock. **OK.**
7. Confirm/edit → Save → receipt photo written once (`ManualFillUpReceiptSave.swift:224-247`), entry saved, capture closes (`leaveCaptureAfterSave`), Home reloads, entry in log. **OK.**

The sequence holds end to end; no fact stops being carried. The **single defect is at step 1**: the Welcome screen (the Open stage) tells a new user the app logs charging and reads pump displays, and neither ships – the same over-promise `PJ.51` removed from the store listing today.

## Proposed rows

| Row | Deliverable | Closes | Consequence today | Severity | Check | Scenario |
|---|---|---|---|---|---|---|
| **PJ.5x** | Make the Welcome copy name what the build does: drop "charging" from the tagline (`WelcomeView.swift:89`, `Localizable.xcstrings:5685`) and "pump displays" from the feature row (`WelcomeView.swift:103`, `Localizable.xcstrings:10525`), and update `design/screens/Welcome.dc.html:25,32` + `LightWelcome.dc.html:25,32` in the same change (PJ.3b's artboard rule). Re-add "charging" with `PJ.49` and "pump displays" when `PumpPhotoGate.allowsPumpPhoto` first clears, in both directions. | J1 · Open | A brand-new user is promised EV charging (v2, an EV cannot log a single charge – `PJ.49`) and pump-display scanning (ships off – `PumpPhotoGate.swift:96-98`) on the first screen they ever see – the exact class `PJ.51` fixed on the store listing today. | **bug** (copy-over-promise; same class as `PJ.3b`, `PJ.12b`, `PJ.51`) | L4 `WelcomeUITests` assert the shipped tagline and feature row (EN+RU); copy review EN+RU; a grep gate that the Welcome surface names no capability the build lacks; artboards + app string + catalog move together. | J1 |

## Could not settle

- **The success metric is not measurable.** "≥70% of installs log a first entry in session 1; time-to-first-entry < 3 min" has no telemetry behind it (the analytics choice is "Held on the owner", `docs/TASKS.md:601`). This mirrors `RV.225` (F3's metric gap) but is not filed here because it is the already-deferred analytics decision, not a J1-specific unowned promise. Worth a row only if the owner picks a hosted analytics path.
- **Whether the guest capture card should carry its own scan affordance.** The card says "Scan your first fill-up" with a camera glyph but its only in-card button is "Type it"; the scan door is the tab-bar capture circle. Both doors are peers and reachable, so this is polish, not a defect – left to the owner's eye rather than filed.

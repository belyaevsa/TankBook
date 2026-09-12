# REVIEW-SCENARIO J1 – 2026-09-12

**Verdict: IMPLEMENTED.**

This is a re-walk of J1 after the previous run (`REVIEW-SCENARIO-J1-2026-09-11c.md`)
returned NOT IMPLEMENTED on one finding: the Welcome copy over-promised (EV charging
and pump-display scanning). That finding became `RV.241`, shipped `ff3c873c`. The same
period also shipped the guest-parity seam `RV.251` + `PJ.100` + `PJ.101` + `PJ.200`
(`e6972b3d`), which the previous run had already anticipated as "the next thing the guest
layout lacks". Both changes are walked here against the journey text.

## Ticked rows found untrue

None. Every closed row naming J1 is true in the code, including the ones the previous
run's single defect grew into:

| Row | Claim | Verdict | Evidence |
|---|---|---|---|
| `PJ.3` | Welcome root, three paths, never reappears once a car exists | MET | `WelcomeGate.swift:95` (no vehicle AND no session); `WelcomeRootView.swift:65-72` (`reevaluate` on appear/pop); `WelcomeView.swift:127-201` (three doors + restore) |
| `RV.23` | Two-sided account copy; sign-in a peer door; Add-car continues with no account | MET | `WelcomeView.swift:101-106` (feature rows), `:161-185` (peer sign-in + benefit line) |
| `RV.5` | First shot reviewed before anything is read | MET | `CaptureView.swift:314-316` (review subject set, OCR NOT run), `:326-338` (pipeline only on "Use this") |
| `RV.197` | Guest Home renders the same log stream | MET | `HomeView.swift:180-186` (`isGuest`), `:200-204` (guest logStream); `HomeLayout.swift:24-27` (`logArea`, no session param) |
| `RV.241` | Welcome copy names only what the build does | MET | `WelcomeView.swift:89` (`Fuel and service – one log`), `:103` (`Scan receipts`); `LocalizationGateRV241Tests.swift` (L1 gate); artboards `Welcome.dc.html`/`LightWelcome.dc.html` carry `Fuel and service` / `Scan receipts` only |
| `RV.251` | Guest Home renders the same car switcher when >1 live car | MET | `HomeGuestLayout.swift:54-57`; `HomeControls.swift:11-33`; `HomeLayout.swift:35-37` (`showsCarSwitcher`, no session param) |
| `PJ.100` | Guest "Type it" opens Service and Expense too | MET | `HomeGuestLayout.swift:244-247` (`HomeTypeItControl`); `HomeControls.swift:44-87` (menu from `CaptureEntryForm.doorMenuForms`) |
| `PJ.101` | Guest no-car Home has the Add-car button | MET | `HomeGuestLayout.swift:304-306` (`HomeAddFirstCarButton`); `HomeControls.swift:122-136` |
| `PJ.200` | Guest Home carries the Reminders row | MET | `HomeGuestLayout.swift:65-67`; `HomeBanners.swift:164-201` (`NavigationLink` to `Route.remindersAll`) |

`PJ.42` (bundled demo receipt) is `[v1.x]`, deferred – N/A for v1.

## Promise-to-code map

| Journey stage / note | Status | Evidence (or what is missing) |
|---|---|---|
| **Open** – one screen, skippable, three paths | MET | `WelcomeGate.swift:92-95`; `WelcomeRootView.swift:34-39`; `WelcomeView.swift:127-201` |
| **Open** – copy names only what the build does (RV.241) | MET | `WelcomeView.swift:89` (`Fuel and service – one log`), `:103` (`Scan receipts`), `:104` (type-it peer), `:105` (two-sided account line); gate `LocalizationGateRV241Tests.swift:72-99` forbids `charging`/`зарядк`/`pump`/`колон` in EN+RU |
| **Open** – sign-in names what an account buys, no cloud word | MET | `WelcomeView.swift:161-185` (benefit line "Smart receipt scanning, backups and sync…", free, not monetization) |
| **Add car** – make/model or plate, powertrain, home currency from locale | MET | `AddVehicleView.swift:32-51` (identity card, powertrain, fuel); `AddVehicleForm.swift:37-40` (`homeCurrency` from `LocaleCurrency.defaultCurrency`) |
| → RU locale defaults to ₽ + RU fuel grades | MET | `LocaleCurrency.swift:12` (RU → RUB); `VehicleDefaults.swift:15` (RU → both 92 and 95); `AddVehicleForm.swift:154-160` (₽ symbol) |
| → photo of car optional | MET | `AddVehicleView.swift:31` (`VehiclePhotoTile`), `:186-194` (photo written only when present) |
| **First entry** – prompted to scan | MET | `HomeGuestLayout.swift:236` (`Scan your first fill-up`); typed door `:247` (`HomeTypeItControl`); scan door `AppTabBar.swift:193-217` (capture circle, no session gate) |
| → the first scan IS onboarding | MET | Capture is the natural next step; review precedes any read (`RV.5`, below) |
| → bundled demo receipt if they have none | N/A | `PJ.42` is `[v1.x]`, deferred |
| → RV.5: first shot reviewed before read | MET | `CaptureView.swift:314-316`; `CaptureReviewView.swift` (Use this / Re-take / Type it) |
| **Payoff** – Pump Card lock ✓, entry saved | MET | `ManualFillUpSections.swift:291-321` (✓ when `.verified`, never gates save); save + `noteEntryChanged` reloads Home (`HomeView.swift:130-134`) |
| ⚠ confidence gating | MET | `ManualFillUpFormState.swift:65-70` (resolved-but-unconfirmed fields dim to 60%) |
| ⚠ instant manual fallback without losing the photo | MET | `CapturePipeline.swift:48` (`sourceImage` attached even when OCR resolves nothing) |
| ⚠ review step catches a bad frame | MET | `CaptureView.swift:145-150` (full-screen review cover before any OCR) |
| **RV.197** – guest Home renders the same log stream | MET | `HomeView.swift:200-204`; `HomeLayout.swift:24-27` |
| **Guest parity** – switcher / Type-it menu / Add-car / Reminders row | MET | `HomeGuestLayout.swift:54-57, 65-67, 244-247, 304-306`; all controls single views in `HomeControls.swift` |

## Sequence trace (one user, one cold launch, no account)

1. Fresh install → `WelcomeGate.shouldShowWelcome` (no vehicle, no session) → Welcome root. **OK.**
2. "Add your car" → `AddVehicleView`; name/make/plate/powertrain, currency + fuel defaults from locale, optional photo; Save → `upsertVehicle` → `noteEntryChanged` → dismiss. **OK.**
3. `WelcomeRootView.reevaluate()` sees a vehicle → `onFinished` → tabs replace Welcome. **OK.**
4. Home, no session → `isGuest` → `HomeGuestLayout`: garage card, capture card ("Scan your first fill-up" + `HomeTypeItControl`), reminders row, import card ("Drivvo / My Fuel Manager"), privacy line. **OK.**
5. Typed door: "Type it" → `.confirmManual` → `ManualFillUpView`; type total + litres → Save → entry saved → Home reloads → `HomeLayout.logArea == .stream` → entry in the log stream. Proven by `ColdLaunchJourneyUITests.testGuestColdLaunchLogsAFillUpAndFindsItOnHomeAndInTheLog` (`:200-241`). **OK.**
6. Scan door: tab-bar capture circle → `CaptureView` → shutter → `processScanned` (review, no OCR) → "Use this" → pipeline → `ConfirmPrefill` → pre-filled form → Save → receipt attached, entry in log. Proven by `testJ3ScanSaveReopenEntryAndSeeTheReceipt` as a guest (`:254-302`). **OK.**
7. Second car from Garage → guest Home shows the switcher (`HomeLayout.showsCarSwitcher`), switching follows the log. Proven by `testGuestWithTwoCarsSwitchesOnHomeAndTheLogFollows` (`ColdLaunchGuestParityJourneyUITests.swift:50-86`). **OK.**

No fact stops being carried at any step; the no-account promise holds end to end – nothing in the
walk requires a session, and the guest Home now carries the full control set the signed-in Home
renders.

## Proposed rows

None. Every promise is MET or reasoned N/A.

## Could not settle

- **The success metric is still not measurable.** "≥70% of installs log a first entry in session 1;
  time-to-first-entry < 3 min" (`JOURNEYS.md:52`) has no telemetry behind it. Same as the prior run:
  this is the deferred analytics decision (the choice is "Held on the owner"), not a J1-specific
  unowned promise. Not filed; would need the owner to pick a hosted analytics path.
- **The guest capture card names scanning but has no in-card scan button.** The card's heading is
  "Scan your first fill-up" and its only in-card button is "Type it"; the scan door is the tab-bar
  capture circle, always visible and one thumb-tap away. Both doors are peers and reachable, so this
  is polish (carried from the prior run), not a defect under hard rule 15. Left to the owner's eye.

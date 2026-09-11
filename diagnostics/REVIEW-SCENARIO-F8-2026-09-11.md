# REVIEW-SCENARIO F8 – 2026-09-11

## Verdict

**NOT IMPLEMENTED** – the denied surface (card + embedded manual form + three next
steps) and the always-present Photos door are real and tested. Two promises in the
journey's own text are not kept: the deep-link's payoff – *granting the camera in
Settings resumes the surface without a relaunch* – is broken, and the trigger's
other half – *camera in use / hardware fault* – has no code at all, with a comment
that claims a "degrade to the manual form" that no call site implements.

## Ticked rows found to be untrue

None outright false. **PJ.1** and **PJ.6** tick accurately: Photos feeds the real
pipeline (`CaptureView.swift:110-114,441-447`), and both "Type it" call sites are
mode-aware (`CaptureView.swift:396-398,580-581`).

**P2.1's F8 acceptance over-claims**, and its shape is the review's own critique:
`"L4: F8 denied-permission flow (manual form + deep link)"` is satisfied by
`testDeniedShowsManualFormWithCardAndAllThreeNextSteps` asserting the Settings
button *exists and is hittable* (`CaptureUITests.swift:70-77`). That proves a door
names a button; it never walks the deep link's round trip. The round trip is
broken – see F8.1 below.

## Promise-to-code map

| F8 text | Verdict | Evidence |
|---|---|---|
| "camera permission denied at first capture" (trigger) | **MET** | `.denied`/`.notDetermined` → `deniedLayout` (`CaptureView.swift:80-84`); first-capture request in `resolvePermission` (`CaptureView.swift:139-151`). |
| "camera in use / hardware fault" (trigger) | **MISSING** | No state for it: `CaptureCameraStatus` is only `authorized/denied/notDetermined` (`CaptureCamera.swift:7-11`). On a fault `capture()` returns nil (`CameraCapture.swift:63-64`) and the shutter silently returns (`CaptureView.swift:344` `guard let image else { return }`). See F8.2. |
| "the capture tab doesn't become a dead button – it opens the manual form" | **MET** | Centre button opens Capture regardless of permission (`testCenterButtonReachesCaptureWithoutLaunchArgument`, `CaptureUITests.swift:312-324`); denied renders card + embedded `ManualFillUpView` (`CaptureView.swift:373-380`). |
| "with a top card: 'Scanning needs the camera – enable in Settings'" | **MET** | Card copy verbatim (`CaptureView.swift:388`); localized EN+RU (`Localizable.xcstrings:10421`). |
| "(deep link)" | **PARTIAL** | `openSettings()` uses `UIApplication.openSettingsURLString` (`CaptureView.swift:433-436`). The link opens; the *resume after granting* is broken (F8.1). |
| "The core promise degrades but the app remains fully usable, permanently" | **MET** | Embedded form saves and dismisses to the opener (`ManualFillUpView.swift:615,624`; `testDeniedStateCanStillSaveFromEmbeddedManualForm`, `CaptureUITests.swift:80-103`). Three next steps (Settings · Type it · Photos) always present (`CaptureView.swift:392-404`). |
| "Photo-library-only users: 'add from photos' is always present" | **MET** | `photosButton` in the granted layout (`CaptureView.swift:558-577`) and a Photos button on the denied card (`CaptureView.swift:400-403`); both route through `openPhotos()` → the shared pipeline (`CaptureView.swift:441-447`). |
| "(also serves the screenshot journey J6)" | **N/A** | Cross-reference, not an F8 promise. J6 is now "EV charge (P2) **[v1.x]**" (`JOURNEYS.md:233`); the "screenshot journey" phrasing is stale but carries no F8 obligation. |
| Metric: "permission-denied users still logging entries at D7" | **N/A** | A product KPI over telemetry, not a code promise this review can verify. |

## Sequence trace (one user: denies camera, then changes their mind)

1. First capture: `resolvePermission` requests; user denies → `cameraStatus = .denied`, `deniedLayout` (card + fill-up form). **No `camera.start()`** (`CaptureView.swift:148-150`).
2. User taps "Settings" → deep link → app backgrounds. User enables camera, returns.
3. `onChange(of: scenePhase)` re-reads the status and sets `cameraStatus = .authorized` (`CaptureView.swift:91-98`) – but **never calls `camera.start()`**.
4. Body flips to `liveLayout`; `cameraBackground` renders `CameraPreview` over a nil session (`isReady == false`, so `captureSession == nil`, `CameraPreview.swift:29-34`) – a blank `midnight` surface.
5. Shutter: `captureFrame` → `camera.capture()` returns nil (guard `isReady`) → `guard let image else { return }` – silent no-op (`CaptureView.swift:342-345`).

**The fact that stops being carried:** the *grant* is read (step 3 updates the
status flag) but the *session* it authorises is never started. The comment that
guards the handler promises "a grant in Settings resumes the camera surface
without a relaunch" (`CaptureView.swift:92-93`); the only path to a working camera
is to close the cover and reopen it (a fresh `CaptureView`, `resolved == false`,
so `resolvePermission` runs `camera.start()`). No test drives this round trip.

## Proposed rows

| Row | Deliverable | Closes | Consequence today | Severity | Check | Scenario |
|---|---|---|---|---|---|---|
| **F8.1** | Start the camera session when a grant is detected on return from Settings, not only on first resolve: the `scenePhase == .active` handler (or the `cameraStatus` setter) calls `camera.start()` when the status becomes `.authorized`. Make the `CaptureView.swift:92-93` comment true. | "(deep link)" next step – the deep link's payoff | A user who denies, then enables the camera in Settings, returns to a blank surface and a dead shutter; they must close and reopen Capture to scan. | **bug** | L1: a status transition to `.authorized` on resume triggers the session start (extract the start-on-authorised decision so it is unit-testable). L4 `CaptureUITests`: denied → foreground with the authorizer re-forced `.authorized` resumes a live preview and a working shutter with no relaunch. | F8 |
| **F8.2** | Give "camera in use / hardware fault" a name: when `capture()` returns nil (not merely the fixture path), the shutter surfaces a next step – a hint or the manual form – instead of silently doing nothing; and rewrite the `CameraCapture.swift:61-62` "the caller then degrades to the ordinary manual form" comment, which names behaviour with no call site. | trigger "camera in use / hardware fault" | On a device whose camera is authorised but broken or in use, tapping the shutter does nothing visible; the degrade the code claims does not exist (hard rule 7 – no named next step). | **gap** | L1: `capture()` returning nil yields a state the caller acts on. L4 `CaptureUITests`: an injected no-camera controller shows the fallback next step rather than a silent no-op. | F8 |

## Adjacent, already filed (do not re-file)

- **PJ.16** (`TASKS.md`, **[v1.1]**) already owns the wider capture-readiness gap
  (torch, "Dark – tap for torch", the ~4 s hint, off-main-thread session start). It
  does **not** cover the grant-resume or the nil-capture no-op – those are the two
  rows above, distinct from PJ.16's scope.
- **SH.3** (`TASKS.md`) keeps a human "F8 camera denied" walk on the floor device;
  it is the product owner's own, not a tracked row, and does not own either defect.

## Could not settle

- **The denied surface is fill-up-only.** `deniedLayout` hardcodes
  `ManualFillUpView` (`CaptureView.swift:378`) and there is no mode row in the
  denied state, so a denied user can log a fill-up but must leave Capture and use
  Home's "Type it" menu for Service/Expense. This is arguably correct (fill-up is
  the default mode, and hard rule 15's other doors exist – `JOURNEYS.md:245`), but
  whether the denied surface *should* offer Service/Expense is a product call the
  journey text does not make. Not filed; flagging for the owner.
- **`.restricted` reads as `.denied`.** `SystemCameraAuthorizer.status()` maps
  `.restricted` (parental controls) to `.denied` (`CaptureCamera.swift:33`), so a
  restricted user is told to "enable in Settings" where no toggle exists for them.
  Edge case; not filed.

# REVIEW-SCENARIO F8 – 2026-09-11b (second walk, after RV.222+RV.223)

## Verdict

**IMPLEMENTED**

## Ticked rows found to be untrue

None. The two rows the first walk could not pass are now true: **RV.222** (grant-in-Settings
resumes the session) and **RV.223** (a nil capture surfaces a next step) are both ticked and the
code beneath them keeps the promise. Re-checked against the tree, not the row.

## Promise-to-code map

| F8 text | Verdict | Evidence |
|---|---|---|
| Trigger: "camera permission denied at first capture" | **MET** | `resolvePermission` requests on the first resolve, `.denied` → `deniedLayout` (`CaptureView.swift:160-169`, `:85-86`, `:432-439`). |
| Trigger: "camera in use / hardware fault" | **MET** | `captureFrame` maps a real nil to `.cameraFault` → `cameraFault = true` (`CaptureView.swift:393-404`); the fault card renders over `liveLayout` (`CaptureView.swift:469-473`). The old "no state for it" gap is closed by `@State cameraFault` (`CaptureView.swift:29-33`) and the core `CaptureShutterOutcome` (`CaptureSurface.swift:33-44`). |
| "the capture tab doesn't become a dead button – it opens the manual form with a top card" | **MET** | Card copy verbatim (`CapturePermissionCards.swift:19`); three next steps Settings · Type it · Photos (`:23-33`); embedded `ManualFillUpView` saves and dismisses (`CaptureView.swift:432-439`). |
| "(deep link)" | **MET** | `openSettings()` uses `UIApplication.openSettingsURLString` (`CapturePermissionCards.swift:91-94`). |
| "A grant in Settings resumes the camera on return, without a relaunch" | **MET** | `setCameraStatus` is the one place a status is applied and starts the session when `.authorized` (`CaptureView.swift:153-158`); the `scenePhase == .active` handler re-reads and calls it (`CaptureView.swift:96-109`). `start()` is idempotent so first-resolve and return share the call (`CameraCapture.swift:51-59`). L4 proves the frame comes back, not merely the status flip (`CaptureRecoveryUITests.swift:47-70`). |
| "the live surface stays and a card names the manual door … shutter still there for a retry … never points at Settings … transient presented state" | **MET** | Fault card over `liveLayout`, shutter is `bottomActions` (`CaptureView.swift:454-482`, `:611-613`); fault card carries only `Type it` (`CapturePermissionCards.swift:60-62`); test asserts the Settings button is absent (`CaptureRecoveryUITests.swift:83-85`). Transient: cleared by `openManualEntry` (`CaptureView.swift:181-184`) and on a successful capture (`:397`). |
| "the core promise degrades but the app remains fully usable, permanently" | **MET** | Denied surface offers the full manual form plus Photos; unchanged from the first walk. |
| "Photo-library-only users: 'add from photos' is always present" | **MET** | `photosButton` in the granted layout's `bottomActions` (`CaptureView.swift:566-585`) and a Photos button on the denied card (`CapturePermissionCards.swift:30-32`); both route through `openPhotos()` (`CaptureView.swift:444-450`). Present in live, denied and fault states. |
| "(also serves the screenshot journey J6)" | **N/A** | Cross-reference; J6 is **[v1.x]** (`JOURNEYS.md:234`). |
| Metric: "permission-denied users still logging entries at D7" | **N/A** | Product KPI over telemetry, not a code promise. |

## Sequence trace

**Deny, then change their mind (the RV.222 round trip).**

1. First capture: `resolvePermission` → `authorizer.request()` denied → `setCameraStatus(.denied)`, no `start()` → `deniedLayout` (`CaptureView.swift:160-169`).
2. Tap Settings → `openSettings()` → app backgrounds.
3. Return: `scenePhase == .active` → `authorizer.status()` reads `.authorized` → `setCameraStatus(.authorized)` → `camera.start()` (`CaptureView.swift:104-108`, `:153-158`).
4. `surface` resolves `.live`; `CameraPreview` renders a running session.
5. Shutter → `capture()` returns a frame → review step.

The grant now carries into the session start; the fact is no longer dropped at step 3. Verified by
`testGrantOnReturnFromSettingsResumesTheSessionWithoutRelaunch`, which distinguishes a started
session from an unstarted one via `-captureCameraTestFrame` (`CameraCapture.swift:26-38,90-94`).

**Camera fault, then retry or type.**

1. Authorised camera returns nil (`capture()` → nil: no camera, a photo-capture error, or a capture
   already in flight) → `CaptureShutterOutcome.resolve` → `.cameraFault` → `cameraFault = true`
   (`CaptureView.swift:386-404`; `CameraCapture.swift:90-104,136-139`).
2. `surface == .fault` → fault card over `liveLayout`; shutter and Photos still present
   (`CaptureView.swift:469-473`, `:558-564`).
3. Retry: a recovered camera returns a frame → `cameraFault = false`, review (`CaptureView.swift:395-399`).
4. Or "Type it" → `openManualEntry()` clears the fault and opens the manual form
   (`CaptureView.swift:181-184`).

Both traces hold end to end; the fault state is reachable in production (a real nil capture), not
behind a `#if DEBUG` door (`-captureAutoFault` is a screenshot seam only, `CaptureView.swift:253-266`).

## Proposed rows

None. Both gaps the first walk filed (F8.1 → RV.222, F8.2 → RV.223) are closed; no promise in F8's
text is unowned, and no ticked row is untrue.

## Could not settle

- **The denied surface is fill-up-only.** `deniedLayout` hardcodes `ManualFillUpView`
  (`CaptureView.swift:437`) and the denied state has no mode row, so a denied user logs a fill-up
  in place but must leave Capture for Service/Expense. Whether the denied surface should offer mode
  selection is a product call the journey text does not make. Not filed; unchanged from the first
  walk.
- **`.restricted` reads as `.denied`.** `SystemCameraAuthorizer.status()` maps `.restricted` to
  `.denied` (`CaptureCamera.swift:58`), so a parental-controls user is told to "enable in Settings"
  where no toggle exists. Edge case; not filed.
- **Screenshots not opened by this agent.** `design/screenshots/RV.223-capture-fault.png` and its
  `-ru` sibling exist and are recorded in the manifest; colour/truncation QA is the orchestrator's
  personal pass, not this read-only review.

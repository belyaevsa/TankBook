# RV.222 + RV.223 - the capture cover's two recovery paths, and the comments that lie about them

**Scenario: F8 · Permissions and hardware said no.** These are the ONLY two v1 rows holding F8 open.
When they land, F8 is re-walked for its `Status: implemented` line - so the fix must satisfy the
journey text (`docs/JOURNEYS.md` -> F8), not just the rows. One brief because both live on the same
screen, the same `capture()` nil path, and both are a comment promising behaviour the code beneath
it does not keep.

## RV.222 - a grant in Settings comes back to a blank preview

Verified in the tree by `REVIEW-SCENARIO-F8-2026-09-11` and the orchestrator:

- The `scenePhase == .active` handler (`ios/App/Sources/Capture/CaptureView.swift:91-98`) re-reads
  `authorizer.status()` and flips `cameraStatus`. Its comment says *"a grant in Settings resumes the
  camera surface without a relaunch."*
- `camera.start()` has **exactly one call site** - inside `resolvePermission` (`:149`). The handler
  never reaches it.
- So the body flips to `liveLayout`, `CameraPreview` renders over a nil session
  (`CameraPreview.swift:29-34`, `isReady == false`), and the shutter's `capture()` returns nil under
  `guard isReady`. The only recovery is closing and reopening the cover.

**Build**: when the status becomes `.authorized` on return from Settings, start the session - in the
handler or in the `cameraStatus` setter, **one place**, and make the existing comment true. Check
`CameraCapture.start()` is safe to call on an already-running session (it may be reached on first
resolve AND on return); if it is not, guard it once, inside `start()`.

## RV.223 - a camera fault is a silent no-op, under a comment claiming a fallback

- `CaptureCameraStatus` is `authorized` / `denied` / `notDetermined` only (`CaptureCamera.swift:7-11`).
  F8's trigger names *"camera in use / hardware fault"* - there is no state for it.
- `capture()` returns nil on a fault (`CameraCapture.swift:63-64`) under the comment *"the caller
  then degrades to the ordinary manual form"* (`:61-62`). The caller is
  `guard let image else { return }` (`CaptureView.swift:345`). Nothing degrades; nothing is shown.
  Hard rule 7 - no next step - and `DEFECT-PATTERNS`' "a comment naming behaviour with no call site".

**Build**: when `capture()` returns nil **outside the fixture path**, surface the next step - the
denied-state card's own manual form is the natural one (F8 already has it: *"the core promise
degrades but the app remains fully usable"*), or a hint that names it. Decide whether this is a new
`CaptureCameraStatus` case or a transient presented state; **say which and why**. Rewrite the
`CameraCapture.swift:61-62` comment to what actually happens. **Do not make the comment true by
deleting it.**

## Tests you must add

- **L4 `CaptureUITests`, and it FAILS TODAY**: denied -> status flips to authorized on scene
  activation -> a frame can be captured, no relaunch. The existing `-cameraStatus` launch argument
  and the test authorizer are the seam; add whatever lets a test flip the status mid-run without a
  real Settings round-trip, and say what you added.
- **L4 `CaptureUITests`**: a `capture()` that returns nil presents the next step; assert the next
  step's control exists AND that tapping it reaches the manual form. Not merely that a label rendered.
- **L1** where the decision lives (the new state or the presented-state enum): nil-outside-fixture
  maps to the next step; nil-in-fixture path is unchanged.
- EN + RU screenshots of the new state, dark; capture lines added.

## The mutation you must run - named

**RV.222**: remove the new `start()` call on return from Settings; the resume L4 goes red.
**RV.223**: restore `guard let image else { return }`; the next-step L4 goes red.
Both restored byte-identical, both re-run, all four outputs verbatim.

## Vacuous traps

- Asserting `cameraStatus == .authorized` after activation - that was already true; the session is
  what was missing.
- A second `start()` call site that races the first.
- A next step that names Settings for a hardware fault - Settings does not fix a busy camera.

## Docs

`docs/JOURNEYS.md` F8 already promises both; edit only if what you ship differs, and say why.
`docs/ERRORS.md` -> Capture: the fault state is a new error surface and needs its row with its next
step.

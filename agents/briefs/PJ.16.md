# PJ.16 - capture readiness: session start off main, torch, the dark and "fill the frame" hints, auto-shutter

Journey: J3 Open/Scan (`docs/ERRORS.md:258-259`, `docs/JOURNEYS.md:96` "torch auto-suggest").
Product owner, 2026-10-01: build it.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`: `ios/App/Sources/Capture/`,
`ios/App/Sources/Settings/` (the auto-shutter setting), `ios/Sources/TankbookCore/` (only for a pure
hint state machine), `ios/App/Sources/Localizable.xcstrings`, the matching tests, `docs/ERRORS.md`,
`docs/JOURNEYS.md` J3, `docs/SCHEMA.md` (the device-local capture conveniences, ~line 517),
`docs/PRACTICES.md` (constants table). Nothing under `ios/Sources/TankbookCore/Extraction/PumpReader/`
- another session has uncommitted work there; `PreviewGuidance.swift` may be READ, and changed only
where this row needs a frame signal, never its pump rules.

## Write code first, explore second

## What exists (confirm before you change anything - this is a hypothesis)

- `ios/App/Sources/Capture/CameraCapture.swift`: `CameraController` is `@MainActor`; `start()` calls
  `session.startRunning()` at ~line 120 **on the main thread**, which Apple documents as blocking
  (hundreds of ms on older phones: iPhone 12 / iOS 18 is the floor, `docs/VISION.md`).
- No torch code exists anywhere (`grep -ri torch ios/` is empty).
- The preview already delivers frames to `PreviewGuidance.swift` (pump-display guidance: searching /
  tooSmall / oneRow / ready) and `CaptureGuidanceCaption.swift` renders its captions. Reuse that frame
  path for the new signals; do not open a second video output.
- `docs/ERRORS.md:258` "Too dark / glare detected -> Live hint: 'Dark – tap for torch' -> Torch toggle ·
  shoot anyway"; `:259` "Nothing detected for ~4s -> 'Fill the frame with the receipt – or type it
  instead.' -> Keep trying · Type it".
- `docs/SCHEMA.md:517` lists "torch preference, last capture mode" as device-local capture conveniences.
- `CaptureAlphaNotice` shows a first-run notice on the same screen - the new hints must not stack on it
  unreadably; decide an order and say which.

## What to build

1. **Session start off the main thread**: configure and `startRunning()` on a serial session queue;
   publish readiness back on the main actor. Nothing on screen waits on it (the shutter disables until
   ready, the "Type it" door is always live).
2. **Torch**: a toggle on the capture screen when `device.hasTorch`; its on/off is remembered
   (device-local, per `SCHEMA.md:517`, `UserDefaults` is fine - never synced). Turned off when the
   screen goes away.
3. **"Dark – tap for torch"**: a luminance signal from the preview frames (mean luma of a downsampled
   frame, smoothed over ~1 s so it does not flicker); below a threshold the hint appears with the torch
   action; it never blocks the shutter ("shoot anyway").
4. **"Fill the frame with the receipt – or type it instead."**: after ~4 s with nothing detected
   (document segmentation finds no document AND the pump guidance is `searching`), the hint appears
   with a **Type it** action that opens the manual form. It must not appear while the pump guidance
   says `tooSmall`/`oneRow`/`ready` - those have their own captions.
5. **Auto-shutter (behind a setting, default OFF)**: with the setting on, when document segmentation
   reports a stable document (same quad, high confidence, ~0.7 s) the shutter fires once. A setting row
   in Settings (capture section) with one line explaining it. Off by default: an unexpected shot is
   worse than a tap.
6. The hint logic is a **pure state machine** (inputs: luminance, detection events, time; outputs: which
   hint) so it is tested without a camera. Thresholds (luma, the 4 s, the 0.7 s stability) are tunables
   placed per `docs/PRACTICES.md` -> constants-placement policy, with rows there.
7. Shape-only log events: torch toggled, a hint shown (which), auto-shutter fired (`docs/LOGGING.md`).

Hard rule 15: **"Type it" stays visible and hittable** under every hint and with the torch on.

**Out of scope:** PJ.41, PJ.42, PJ.43; pump-reader rules; any capture-pipeline change after the shutter.

## Docs to read, in order

1. `docs/ERRORS.md` capture rows (authority for wording and next steps).
2. `docs/DESIGN.md` - capture screen, hint styling (amber is attention only), motion.
3. `docs/JOURNEYS.md` J3 Open/Scan - update its torch/hint lines to what ships.
4. `docs/PRACTICES.md` constants policy; `docs/LOGGING.md`; `docs/SCHEMA.md:517`.

## Checks (exit codes; report each)

- `scripts/gate.sh` exit 0; `RELEASE=1 scripts/gate.sh` exit 0 (you will add DEBUG seams to inject
  luminance/detection events).
- `CaptureUITests`, own `-only-testing:` run, COUNT read; also `CaptureGuidanceUITests` (it exercises
  the same frame path) - must stay green.

## Tests you must add

- **L1 state machine:** dark below threshold -> dark hint; light -> none; no detection for 4 s -> fill
  hint; a detection resets the timer; pump guidance `tooSmall` suppresses the fill hint; auto-shutter
  fires once after the stability window and not again. Oracles: the named thresholds. **Mutation:**
  remove the 4 s timer reset on detection - a test must go red.
- **L4 `CaptureUITests`:** with injected events the dark hint and the fill hint render; the torch toggle
  exists on a device with a torch (simulate via a seam - the simulator has none); **"Type it" is
  hittable under both hints** (assert its frame inside the window).
- **L2:** the torch preference persists across a relaunch.

## Vacuous traps

- `startRunning()` moved into a `Task {}` that still runs on the main actor.
- A luminance hint that flickers frame to frame (no smoothing).
- A fill hint that fires while a pump display is in view.
- Auto-shutter on by default, or firing repeatedly.

## Screenshots

EN and RU, dark, outside a test run, with the seams: the dark hint with the torch toggle, and the fill
hint with "Type it". `design/screenshots/PJ.16-dark-hint.png` / `-ru.png`, `PJ.16-fill-hint.png` /
`-ru.png`, and the Settings row `PJ.16-auto-shutter-setting.png` / `-ru.png`. RU strings run 20-30 %
longer - check the hint does not truncate its action.

## Standing fences

- `swiftlint lint` from the repo ROOT. Check test COUNTS. Never stash/move/checkout for a baseline.
- Never `pgrep -f` / `pkill -f`. Never move, rename or revert a file you did not create.
- `simctl launch` on a running app ignores new arguments - `terminate` first.
- Assert frames against the window. Git is read-only for you. You cannot see screenshots.

## Report back

Exit codes; counts before/after; run-or-written per test; the mutation's red-then-green; the thresholds
and where they live; how session start was measured or reasoned off-main; **anything you found and did
not fix**.

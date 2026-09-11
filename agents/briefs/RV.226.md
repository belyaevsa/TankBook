# RV.226 - `.restricted` is told to enable the camera in Settings, where no toggle exists

**Scenario: F8 · permissions and hardware said no.** Filed from F8's second walk. Small; the same
seam `RV.222`/`RV.223` just built.

`SystemCameraAuthorizer.status()` maps `AVAuthorizationStatus.restricted` to `.denied`
(`CaptureCamera.swift:58`), so a user whose device policy forbids the camera - parental controls,
MDM - sees the denied card's *enable in Settings* next step, and there is no such toggle. `RV.164`'s
shape: an error naming a next step that does not exist (hard rule 7).

## Build

Give `.restricted` its own `CaptureCameraStatus` case and its own card copy: the manual door is
the only next step, and the card says why (*the camera is blocked by a device policy*). One more
case in `CaptureSurfaceState.resolve(status:cameraFault:)`; the card is `CapturePermissionCards`'
third state, not a third card. `docs/ERRORS.md` -> Capture: the row and its next step. EN + RU.

## Tests

- **L1 `CaptureSurfaceTests`, FAILS TODAY**: `.restricted` resolves to the restricted card, never
  the Settings one.
- **L4 `CaptureRecoveryUITests` EN + RU**: authorizer seeded `.restricted` (extend the existing
  `-cameraStatusSequence` seam) - the card names the manual door, the Settings button is absent,
  *Type it* reaches the form. Frames; capture lines.

## Mutation - named

Map `.restricted` back to `.denied`; the L1 goes red. Byte-identical restore; verbatim.

## Vacuous trap

A restricted card that still offers Settings.

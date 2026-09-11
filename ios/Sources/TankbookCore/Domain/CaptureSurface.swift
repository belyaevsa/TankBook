import Foundation

/// The camera permission states the capture screen can be in
/// (docs/ERRORS.md -> Capture; F8 in docs/JOURNEYS.md). Permission is
/// AVFoundation's concept; a hardware fault is not a permission state and is
/// modelled separately (`CaptureSurfaceState`).
public enum CaptureCameraStatus: Sendable, Equatable {
    case authorized
    case denied
    case notDetermined
}

/// What the capture surface presents. `denied` is a permission state and wins
/// over a transient fault; `fault` is the hardware refusing while permission
/// stands, and it never names Settings (Settings cannot fix a busy camera).
///
/// Pure so the precedence is pinned at L1: a fault is a presented state, not a
/// fourth `CaptureCameraStatus` case, because a status of `.authorized` and a
/// hardware fault can be true at the same time and conflating them would flip
/// the whole layout to the permission fallback.
public enum CaptureSurfaceState: Sendable, Equatable {
    case live
    case denied
    case fault

    public static func resolve(status: CaptureCameraStatus,
                               cameraFault: Bool) -> CaptureSurfaceState {
        if status == .denied { return .denied }
        if cameraFault { return .fault }
        return .live
    }
}

/// What the shutter does with the camera's answer. A fixture image substitutes
/// the camera entirely, so the fixture path is always usable; a real camera
/// that hands back nothing is a hardware fault with a next step, never silence
/// (hard rule 7).
public enum CaptureShutterOutcome: Sendable, Equatable {
    case review
    case cameraFault

    public static func resolve(usedFixture: Bool, cameraImage: Bool) -> CaptureShutterOutcome {
        if usedFixture { return .review }
        return cameraImage ? .review : .cameraFault
    }
}

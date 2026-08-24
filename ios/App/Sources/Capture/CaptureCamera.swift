import AVFoundation
import Foundation
import TankbookCore

/// The camera permission states the capture screen can be in
/// (docs/ERRORS.md -> Capture; F8 in docs/JOURNEYS.md).
enum CaptureCameraStatus: Sendable, Equatable {
    case authorized
    case denied
    case notDetermined
}

/// Injected permission source so UI tests can drive every state without
/// touching the real system (docs/TESTING.md). `SystemCameraAuthorizer` is the
/// production implementation; the DEBUG `-cameraStatus` override is read inside
/// it so the CaptureView needs no test-only plumbing.
protocol CameraAuthorizing: Sendable {
    func status() -> CaptureCameraStatus
    func request() async -> CaptureCameraStatus
}

/// Production authorizer backed by `AVCaptureDevice`. The DEBUG/test-only
/// override `-cameraStatus denied|authorized|notDetermined` forces the result
/// so the F8 fallback and the camera layout are reachable deterministically on
/// a simulator that has no camera at all.
struct SystemCameraAuthorizer: CameraAuthorizing {
    func status() -> CaptureCameraStatus {
        if let forced = ProcessInfo.processInfo.arguments.cameraStatusOverride {
            return forced
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    func request() async -> CaptureCameraStatus {
        if let forced = ProcessInfo.processInfo.arguments.cameraStatusOverride {
            return forced
        }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
    }
}

extension Array where Element == String {
    /// The DEBUG `-powertrain <value>` override, if present. Lets a UI test or a
    /// screenshot run pin the mode row without seeding a whole vehicle.
    var powertrainOverride: Powertrain? {
        guard let index = firstIndex(of: "-powertrain"), index + 1 < count else { return nil }
        return Powertrain(rawValue: self[index + 1])
    }
}

private extension Array where Element == String {
    /// The DEBUG `-cameraStatus <value>` override, if present.
    var cameraStatusOverride: CaptureCameraStatus? {
        guard let index = firstIndex(of: "-cameraStatus"), index + 1 < count else { return nil }
        switch self[index + 1] {
        case "authorized": return .authorized
        case "denied": return .denied
        case "notDetermined": return .notDetermined
        default: return nil
        }
    }
}

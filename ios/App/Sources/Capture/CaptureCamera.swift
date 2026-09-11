import AVFoundation
import Foundation
import TankbookCore

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
/// a simulator that has no camera at all. `-cameraStatusSequence a,b` is the
/// mid-run variant: each `status()` read advances through the list and repeats
/// the last, so a UI test can model the Settings round-trip - launch denied,
/// background/foreground the app, then read authorized - without a real
/// Settings visit.
struct SystemCameraAuthorizer: CameraAuthorizing {
    #if DEBUG
    /// The current index into `-cameraStatusSequence`. `unsafe` because it is
    /// read only from the main-actor capture view and never concurrently; it
    /// exists solely so a UI test can flip a status mid-run.
    nonisolated(unsafe) private static var sequenceIndex = 0
    /// True once the app has left the foreground. The sequence advances only
    /// after a real background/foreground round-trip, so the launch-time
    /// `.active` transition cannot consume the next value.
    nonisolated(unsafe) private static var didEnterBackground = false
    #endif

    #if DEBUG
    /// Called from the capture view when the scene backgrounds. It arms the
    /// next `status()` read to advance `-cameraStatusSequence`, modelling the
    /// Settings round-trip without a real Settings visit.
    static func noteDidEnterBackground() {
        didEnterBackground = true
    }
    #endif

    func status() -> CaptureCameraStatus {
        #if DEBUG
        if let sequence = ProcessInfo.processInfo.arguments.cameraStatusSequence {
            if Self.didEnterBackground {
                Self.sequenceIndex = min(Self.sequenceIndex + 1, sequence.count - 1)
                Self.didEnterBackground = false
            }
            return sequence[min(Self.sequenceIndex, sequence.count - 1)]
        }
        #endif
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

    /// The DEBUG `-captureMode <rawValue>` override, if present. PJ.6: forces
    /// the selected mode so a UI test (or the denied-permission state, which
    /// has no mode row) can open "Type it" in a mode of its choosing without
    /// tapping a chip. A mode the powertrain does not offer is ignored, exactly
    /// as the real mode row would not show it.
    var captureModeOverride: CaptureMode? {
        guard let index = firstIndex(of: "-captureMode"), index + 1 < count else { return nil }
        return CaptureMode(rawValue: self[index + 1])
    }
}

private extension Array where Element == String {
    /// The DEBUG `-cameraStatus <value>` override, if present.
    var cameraStatusOverride: CaptureCameraStatus? {
        guard let index = firstIndex(of: "-cameraStatus"), index + 1 < count else { return nil }
        return CaptureCameraStatus(argumentValue: self[index + 1])
    }

    /// The DEBUG `-cameraStatusSequence <a,b>` override, if present. Each
    /// `status()` read returns the next value and repeats the last, so a UI
    /// test can flip the status mid-run (see `SystemCameraAuthorizer`).
    var cameraStatusSequence: [CaptureCameraStatus]? {
        guard let index = firstIndex(of: "-cameraStatusSequence"), index + 1 < count else {
            return nil
        }
        let values = self[index + 1].split(separator: ",").compactMap {
            CaptureCameraStatus(argumentValue: String($0))
        }
        return values.isEmpty ? nil : values
    }
}

extension CaptureCameraStatus {
    /// Parses the `-cameraStatus` argument vocabulary. Shared so the single
    /// override and the sequence cannot drift apart.
    init?(argumentValue: String) {
        switch argumentValue {
        case "authorized": self = .authorized
        case "denied": self = .denied
        case "notDetermined": self = .notDetermined
        default: return nil
        }
    }
}

#if EXPERIMENTS
import AVFoundation
import CoreGraphics
import SwiftUI
import TankbookCore

/// PU.39 - the Capture Lab's camera presets. A debug build shoots one scene
/// under every preset back to back so the owner can compare capture latency,
/// bytes, pixel size and what the reader committed, then choose a production
/// setting by measurement instead of argument.
///
/// A preset is a pure value. `plan(capabilities:)` turns it into a
/// `CaptureLabPlan` - the settings to apply and every capability the device
/// lacks, recorded rather than thrown - so an iPhone 12 that cannot do a thing
/// says so in the run log. `CameraController.applyLabPlan` is the only code
/// that touches AVFoundation.

/// The device capabilities a preset must respect. The live value is read from
/// the `AVCaptureDevice`; a unit test injects a fake so the unsupported path is
/// exercisable without hardware.
struct CaptureLabCapabilities: Equatable {
    var focusPointOfInterest = false
    var exposurePointOfInterest = false
    var continuousAutoFocus = false
    var continuousAutoExposure = false
    var lockedFocus = false
    var lockedExposure = false
    var exposureBias = false
    var zoom = false
    /// The zoom factor at which the device switches to its optical telephoto,
    /// when it has one; nil means the zoom preset uses a plain 2×.
    var telephotoSwitchOverZoom: CGFloat?
    var flash = false
    var highSessionPreset = false

    /// Every capability present - the control a unit test starts from.
    static let all = CaptureLabCapabilities(
        focusPointOfInterest: true, exposurePointOfInterest: true,
        continuousAutoFocus: true, continuousAutoExposure: true,
        lockedFocus: true, lockedExposure: true,
        exposureBias: true, zoom: true, telephotoSwitchOverZoom: 2.0,
        flash: true, highSessionPreset: true)

    /// What a device with no camera can do (the simulator): nothing. A preset
    /// resolved against this records every capability it needs.
    static let none = CaptureLabCapabilities()
}

/// What a preset actually applied, as the run log records it. Every value is a
/// stable token or a number; `unsupported` names each capability the device
/// lacked. The strings are the vocabulary, not user copy.
struct CaptureLabApplied: Codable, Equatable {
    var sessionPreset: String
    var qualityPrioritization: String?
    var exposureBias: Float?
    var focusMode: String?
    var exposureMode: String?
    var zoomFactor: Double?
    var flashOff: Bool
    var locked: Bool
    var unsupported: [String]
}

/// The resolved settings for one preset: what `CameraController` should apply.
/// Built from a capability set, so it never carries a setting the device cannot
/// honour - that setting is named in `unsupported` instead.
struct CaptureLabPlan: Equatable {
    var sessionPresetHigh = false
    var qualityPrioritization: AVCapturePhotoOutput.QualityPrioritization?
    var exposureBias: Float?
    var focusPoint: CGPoint?
    var exposurePoint: CGPoint?
    var focusMode: AVCaptureDevice.FocusMode?
    var exposureMode: AVCaptureDevice.ExposureMode?
    var zoomFactor: CGFloat?
    var flashOff = false
    /// `locked` waits for focus and exposure to converge before locking them.
    var waitForConvergence = false
    var unsupported: [String] = []

    var applied: CaptureLabApplied {
        CaptureLabApplied(
            sessionPreset: sessionPresetHigh ? "high" : "photo",
            qualityPrioritization: qualityPrioritization.map(Self.describe),
            exposureBias: exposureBias,
            focusMode: focusMode.map(Self.describe),
            exposureMode: exposureMode.map(Self.describe),
            zoomFactor: zoomFactor.map(Double.init),
            flashOff: flashOff,
            locked: focusMode == .locked || exposureMode == .locked,
            unsupported: unsupported)
    }

    static func describe(_ quality: AVCapturePhotoOutput.QualityPrioritization) -> String {
        switch quality {
        case .quality: return "quality"
        case .balanced: return "balanced"
        case .speed: return "speed"
        @unknown default: return "unknown"
        }
    }

    static func describe(_ mode: AVCaptureDevice.FocusMode) -> String {
        switch mode {
        case .locked: return "locked"
        case .autoFocus: return "autoFocus"
        case .continuousAutoFocus: return "continuousAutoFocus"
        @unknown default: return "unknown"
        }
    }

    static func describe(_ mode: AVCaptureDevice.ExposureMode) -> String {
        switch mode {
        case .locked: return "locked"
        case .autoExpose: return "autoExpose"
        case .continuousAutoExposure: return "continuousAutoExposure"
        case .custom: return "custom"
        @unknown default: return "unknown"
        }
    }
}

/// The seven presets. `default` is exactly today's capture - the control every
/// other preset is measured against. Each knows how to turn itself into a plan
/// (applied by `CameraController`) and how to describe itself for the screen.
enum CaptureLabPreset: String, CaseIterable, Identifiable, Codable {
    case `default`
    case quality
    case speed
    case metered
    case locked
    case zoom2x
    case high1080

    var id: String { rawValue }

    /// One line, localised, of what this preset changes.
    var summary: LocalizedStringKey {
        switch self {
        case .default:
            return "Today's capture – the control."
        case .quality:
            return "Maximum quality prioritisation."
        case .speed:
            return "Fastest capture."
        case .metered:
            return "Centre metering with exposure bias −0.5."
        case .locked:
            return "Metered, then focus and exposure locked, flash off."
        case .zoom2x:
            return "Metered at 2× zoom (or the telephoto)."
        case .high1080:
            return "1080p session preset at speed – the floor."
        }
    }

    /// The settings this preset wants, resolved against `capabilities`. A
    /// capability the device lacks is appended to `unsupported`, never thrown.
    func plan(capabilities: CaptureLabCapabilities) -> CaptureLabPlan {
        var plan = CaptureLabPlan()
        switch self {
        case .default:
            break
        case .quality:
            plan.qualityPrioritization = .quality
        case .speed:
            plan.qualityPrioritization = .speed
        case .metered:
            Self.applyMetered(&plan, capabilities: capabilities)
        case .locked:
            Self.applyMetered(&plan, capabilities: capabilities)
            Self.applyLocked(&plan, capabilities: capabilities)
        case .zoom2x:
            Self.applyMetered(&plan, capabilities: capabilities)
            Self.applyZoom(&plan, capabilities: capabilities)
        case .high1080:
            Self.applyHigh1080(&plan, capabilities: capabilities)
        }
        return plan
    }

    /// `locked`: the metered core, then focus and exposure locked once they
    /// converge, flash off. A device that cannot lock or has no flash records
    /// the gap.
    private static func applyLocked(_ plan: inout CaptureLabPlan,
                                    capabilities: CaptureLabCapabilities) {
        if capabilities.lockedFocus {
            plan.focusMode = .locked
            plan.waitForConvergence = true
        } else {
            plan.unsupported.append("focusLock")
        }
        if capabilities.lockedExposure {
            plan.exposureMode = .locked
            plan.waitForConvergence = true
        } else {
            plan.unsupported.append("exposureLock")
        }
        if capabilities.flash {
            plan.flashOff = true
        } else {
            plan.unsupported.append("flash")
        }
    }

    /// `zoom2x`: the metered core at 2× (the optical switch-over when the
    /// device has a telephoto), or the gap recorded.
    private static func applyZoom(_ plan: inout CaptureLabPlan,
                                  capabilities: CaptureLabCapabilities) {
        if capabilities.zoom {
            plan.zoomFactor = capabilities.telephotoSwitchOverZoom ?? 2.0
        } else {
            plan.unsupported.append("zoom")
        }
    }

    /// `high1080`: the `.high` session preset at speed - the floor a small
    /// photo sets under the reader.
    private static func applyHigh1080(_ plan: inout CaptureLabPlan,
                                      capabilities: CaptureLabCapabilities) {
        if capabilities.highSessionPreset {
            plan.sessionPresetHigh = true
        } else {
            plan.unsupported.append("sessionPreset.high")
        }
        plan.qualityPrioritization = .speed
    }

    /// The shared metered core: centre points, continuous focus and exposure,
    /// exposure bias −0.5. Each piece is guarded by its capability.
    private static func applyMetered(_ plan: inout CaptureLabPlan,
                                     capabilities: CaptureLabCapabilities) {
        let centre = CGPoint(x: 0.5, y: 0.5)
        if capabilities.focusPointOfInterest {
            plan.focusPoint = centre
        } else {
            plan.unsupported.append("focusPointOfInterest")
        }
        if capabilities.exposurePointOfInterest {
            plan.exposurePoint = centre
        } else {
            plan.unsupported.append("exposurePointOfInterest")
        }
        if capabilities.continuousAutoFocus {
            plan.focusMode = .continuousAutoFocus
        } else {
            plan.unsupported.append("continuousAutoFocus")
        }
        if capabilities.continuousAutoExposure {
            plan.exposureMode = .continuousAutoExposure
        } else {
            plan.unsupported.append("continuousAutoExposure")
        }
        if capabilities.exposureBias {
            plan.exposureBias = -0.5
        } else {
            plan.unsupported.append("exposureTargetBias")
        }
    }
}

/// Which pipeline scores a shot. Pump classifies first (exactly as a real
/// capture); receipt forces the receipt path.
enum CaptureLabSource: String, CaseIterable, Identifiable, Codable {
    case pump
    case receipt

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .pump: return "Pump"
        case .receipt: return "Receipt"
        }
    }

    /// The `ExtractionSource` handed to `CapturePipeline.process`: nil for pump
    /// so the classification decides, `.receipt` to force the receipt path.
    var extractionSource: ExtractionSource? {
        switch self {
        case .pump: return nil
        case .receipt: return .receipt
        }
    }
}
#endif

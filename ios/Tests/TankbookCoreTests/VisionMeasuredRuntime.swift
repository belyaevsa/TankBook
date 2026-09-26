import Foundation
import Testing

/// The L5 accuracy numbers - every high-water mark in `high-water.json`, the
/// pump gate's measured counts, RV.56's zero confident-wrong totals and the
/// expense `.txt` dumps - are measurements of ONE Vision runtime, the way the
/// L4 snapshot baselines are measurements of one simulator runtime
/// (`docs/TESTING.md` -> "The OCR accuracy suites are runtime-specific"). On a
/// different OS the recognizer reads the same pixels differently, and a red
/// there says nothing about the parser. The measured runtime is the iOS
/// simulator's - the iOS build of Vision, the nearest this project gets to a
/// phone without one - so these suites run only there
/// (`scripts/vision-suites.sh`) and skip, with this reason, everywhere else.
enum VisionMeasuredRuntime {
    /// The iOS major version the corpus numbers were recorded on.
    static let measuredMajorVersion = 27

    static var isCurrent: Bool {
        if ProcessInfo.processInfo.environment["VISION_MEASURE_ANYWAY"] == "1" { return true }
        #if os(iOS)
        return ProcessInfo.processInfo.operatingSystemVersion.majorVersion == measuredMajorVersion
        #else
        return false
        #endif
    }

    static var skipReason: Comment {
        let current = ProcessInfo.processInfo.operatingSystemVersion
        #if os(iOS)
        let here = "iOS"
        #else
        let here = "macOS"
        #endif
        return Comment(rawValue:
            "OCR accuracy numbers are measured on the iOS \(measuredMajorVersion) simulator; this is "
            + "\(here) \(current.majorVersion).\(current.minorVersion), where Vision reads the corpus "
            + "differently (docs/TESTING.md -> \"The OCR accuracy suites are runtime-specific\"; "
            + "scripts/vision-suites.sh runs them)")
    }
}

extension Trait where Self == ConditionTrait {
    /// Runs the test only on the Vision runtime its numbers were measured on.
    static var visionMeasuredRuntimeOnly: ConditionTrait {
        .enabled(if: VisionMeasuredRuntime.isCurrent, VisionMeasuredRuntime.skipReason)
    }
}

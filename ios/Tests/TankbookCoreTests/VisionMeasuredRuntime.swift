import Foundation
import Testing

/// The L5 accuracy numbers - every high-water mark in `high-water.json`, the
/// pump gate's measured counts, RV.56's zero confident-wrong totals and the
/// expense `.txt` dumps - are measurements of ONE Vision runtime, the way the
/// L4 snapshot baselines are measurements of one simulator runtime
/// (`docs/TESTING.md` -> "The OCR accuracy suites are runtime-specific"). On a
/// different major OS the recognizer reads the same pixels differently, and a
/// red there says nothing about the parser. Those suites therefore run only
/// on the runtime they were measured on and skip, with this reason, elsewhere.
enum VisionMeasuredRuntime {
    /// The macOS major version the corpus numbers were recorded on.
    static let measuredMajorVersion = 26

    static var isCurrent: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion == measuredMajorVersion
    }

    static var skipReason: Comment {
        let current = ProcessInfo.processInfo.operatingSystemVersion
        return Comment(rawValue:
            "OCR accuracy numbers were measured on macOS \(measuredMajorVersion); this is "
            + "macOS \(current.majorVersion).\(current.minorVersion), where Vision reads the corpus "
            + "differently (docs/TESTING.md -> \"The OCR accuracy suites are runtime-specific\")")
    }
}

extension Trait where Self == ConditionTrait {
    /// Runs the test only on the Vision runtime its numbers were measured on.
    static var visionMeasuredRuntimeOnly: ConditionTrait {
        .enabled(if: VisionMeasuredRuntime.isCurrent, VisionMeasuredRuntime.skipReason)
    }
}

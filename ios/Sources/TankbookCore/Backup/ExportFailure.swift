import Foundation

// The outcome-classified failure of building an export (PJ.36, PJ.38).
//
// The disk-full state is a REAL state, never a crash (docs/ERRORS.md ->
// Settings, "Export fails (disk)"): the builder throws a write error, `map`
// classifies it, and the view surfaces the message while the app stays usable
// (hard rule 7 - every error names its next step). `map` is a pure function so
// the classification is testable: the mutation that makes this path throw
// instead of returning a classified failure breaks the L1 test.

public enum ExportFailure: Equatable, Sendable {
    /// The volume ran out of space (CocoaError `.fileWriteOutOfSpace`).
    case insufficientStorage
    /// Anything else - the export failed for a reason the UI does not special-case.
    case underlying

    /// Classifies a write error. A disk-full write throws
    /// `NSCocoaErrorDomain / NSFileWriteOutOfSpaceError`; that becomes the
    /// surfaced insufficient-storage state, everything else stays generic.
    public static func map(_ error: Error) -> ExportFailure {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError {
            return .insufficientStorage
        }
        return .underlying
    }

    /// The default-language sentence (docs/ERRORS.md -> Settings, "Export fails
    /// (disk)"). The app renders the localised catalogue copy; this pins the
    /// English sentence the L1 test and the catalogue must both carry.
    public var defaultMessage: String {
        switch self {
        case .insufficientStorage: "Not enough space to build the export."
        case .underlying: "Couldn't build the export."
        }
    }
}

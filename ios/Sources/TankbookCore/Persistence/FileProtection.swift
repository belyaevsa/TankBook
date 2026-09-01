import Foundation

/// The single seam through which every file-protection promise in
/// docs/SECURITY.md flows - the database `.sqlite`/`-wal`/`-shm` triple, the
/// attachment directories, and every cache/archive the app writes.
///
/// PR.16 applied `completeUntilFirstUserAuthentication` at six call sites
/// directly against `FileManager`, and its test then asked the filesystem what
/// it had stored. The iOS Simulator reports the class as a hard constant no
/// matter what is set, so that test passes whether or not the code applies
/// anything - on the only runtime CI has (PR.16b). This seam is what makes the
/// check discriminating: a test swaps `applier` for a recorder and asserts the
/// promised class was applied per file, instead of asking the filesystem.
public enum FileProtection {
    /// The protection class the app promises (docs/SECURITY.md -> iOS table).
    /// Modeled apart from `FileProtectionType` so the core package compiles -
    /// and this seam is testable - on macOS, where the platform type does not
    /// exist. `none` is present so the class assertion is not degenerate: an
    /// applier that applied `.none` must fail the check rather than pass it as
    /// "a call happened".
    public enum Class: String, Sendable, Equatable {
        case none
        case completeUntilFirstUserAuthentication
    }

    /// The production applier. On iOS it maps `Class` to `FileProtectionType`
    /// and sets it via `FileManager.setAttributes`; on macOS the attribute does
    /// not exist, so it is a no-op and the core tests observe the seam with
    /// their own recorder. Kept as a named constant so tests can restore it.
    public static let defaultApplier: @Sendable (Class, URL) -> Void = { protectionClass, url in
        #if os(iOS)
        let type: FileProtectionType
        switch protectionClass {
        case .none:
            type = .none
        case .completeUntilFirstUserAuthentication:
            type = .completeUntilFirstUserAuthentication
        }
        try? FileManager.default.setAttributes([.protectionKey: type], ofItemAtPath: url.path)
        #endif
    }

    /// The injectable seam. Swapped only by tests.
    public nonisolated(unsafe) static var applier: @Sendable (Class, URL) -> Void = FileProtection.defaultApplier

    /// Applies a protection class to a file. The six appliers call this.
    public static func apply(_ protectionClass: Class, to url: URL) {
        applier(protectionClass, url)
    }

    /// Applies the class SECURITY.md promises (`completeUntilFirstUserAuthentication`).
    public static func protect(_ url: URL) {
        apply(.completeUntilFirstUserAuthentication, to: url)
    }
}

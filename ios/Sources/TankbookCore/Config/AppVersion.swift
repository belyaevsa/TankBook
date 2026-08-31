import Foundation

/// A dotted-numeric version string as used by `appUpdate` in the config
/// document and by `CFBundleShortVersionString` (docs/CONFIG.md -> "App version
/// and the update notice").
///
/// Comparison is **numeric per component, never lexicographic**: `1.10.0` is
/// newer than `1.9.0`, while a string compare says the opposite.
///
/// Parsing accepts exactly three components - `major.minor.patch`, each a
/// non-empty run of ASCII digits - the shape every version in docs/CONFIG.md
/// spells and the shape `CFBundleShortVersionString` carries. Anything else
/// fails to parse rather than guessing: two components (`"1.2"`) and four
/// (`"1.2.0.4"`) are rejected, as are pre-release suffixes (`"1.2.0-beta"`),
/// prefixes (`"v1.2.0"`), signs, whitespace and empty components. A string
/// that fails to parse must never silently become a fact (hard rule 13); at
/// the update-requirement level an unparseable version fails open to `.none`.
public struct AppVersion: Sendable, Equatable, Hashable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `major.minor.patch` dotted numerics, or returns nil for anything
    /// else - nil, not a guess (see the type comment).
    public init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { ("0"..."9").contains($0) } })
        else { return nil }
        guard let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses the bundle's marketing version (`CFBundleShortVersionString` -
    /// `1.0.0` in this product, docs/PRACTICES.md -> constants). A bundle with
    /// no plist value, or a value that is not `major.minor.patch`, is nil - the
    /// same fail-don't-guess rule as the string parser. Defaults to the main
    /// bundle, which is what the running app wants; tests pass a crafted one.
    public init?(bundle: Bundle = .main) {
        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let parsed = AppVersion(version) else { return nil }
        self.major = parsed.major
        self.minor = parsed.minor
        self.patch = parsed.patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

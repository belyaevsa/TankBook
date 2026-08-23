import Foundation

/// Persistence of the rollback floor: the highest-seen config `version`
/// (docs/CONFIG.md -> "Rollback floor in the Keychain").
///
/// Version monotonicity alone fails if an attacker deletes the cache, since a
/// fresh client accepts any version. The floor lives in the Keychain with
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so it is absent from
/// backups and unaffected by container tampering, and a client refuses any
/// document below it. **A fresh install has no floor, and that is correct** -
/// the caller must not invent one.
///
/// A protocol rather than a direct `Security` dependency because the real
/// Keychain is unavailable in a plain `swift test` process; tests inject an
/// in-memory double and therefore do **not** exercise the real Keychain.
public protocol ConfigRollbackFloorStoring: Sendable {
    /// The highest version ever accepted, or nil for a fresh install.
    func highestSeenVersion() -> Int?
    /// Records a newly-accepted version (monotonic: only higher values stick).
    func record(version: Int)
}

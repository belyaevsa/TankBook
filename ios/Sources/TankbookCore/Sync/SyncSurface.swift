import Foundation

/// The pure input to the Settings sync status surface (docs/SYNC.md -> "The
/// Settings sync surface"). A value type so the status decision is testable
/// without a simulator or a network (docs/TESTING.md L1). Counts and flags only
/// - no domain values (hard rule 12).
public struct SyncSurfaceState: Equatable, Sendable {
    public var isSignedIn: Bool
    /// When the last successful cycle finished; nil = never synced yet.
    public var lastSyncDate: Date?
    /// Rows still waiting to push (docs/SYNC.md S7: "Waiting to sync · N changes").
    public var dirtyCount: Int
    /// The last cycle ended in a transport outage (offline / server down).
    public var transportUnavailable: Bool
    /// The device was revoked (410) - a transport issue that belongs here.
    public var deviceRevoked: Bool
    /// Blob-storage quota usage percent; nil = no quota pressure (429).
    public var quotaUsedPercent: Int?
    /// Records carrying a `ConflictState` (derived, never stored).
    public var flaggedCount: Int
    /// A cycle is currently in flight (drives the "Sync now" spinner).
    public var isSyncing: Bool

    public init(
        isSignedIn: Bool,
        lastSyncDate: Date? = nil,
        dirtyCount: Int = 0,
        transportUnavailable: Bool = false,
        deviceRevoked: Bool = false,
        quotaUsedPercent: Int? = nil,
        flaggedCount: Int = 0,
        isSyncing: Bool = false
    ) {
        self.isSignedIn = isSignedIn
        self.lastSyncDate = lastSyncDate
        self.dirtyCount = dirtyCount
        self.transportUnavailable = transportUnavailable
        self.deviceRevoked = deviceRevoked
        self.quotaUsedPercent = quotaUsedPercent
        self.flaggedCount = flaggedCount
        self.isSyncing = isSyncing
    }
}

/// The one status the Settings sync surface is in. The split between
/// reassurance and attention is the load-bearing property: the status row is
/// **reassurance, never a warning** - it does not turn amber with age, and a
/// long queue is not an error state (docs/SYNC.md: "a week offline is the same
/// as an hour").
public enum SyncStatus: Equatable, Sendable {
    /// Nothing pending, nothing failed: "Synced just now" / "Synced N hours ago".
    case synced
    /// A dirty queue exists (S7): "Waiting to sync · N changes".
    case waitingToSync
    /// The last manual cycle ended in a transport outage with nothing pending:
    /// "Sync service unreachable - your data is safe..." (reassurance, not amber).
    case serverUnreachable
    /// The device was signed out (410): an account issue the user can act on.
    case deviceRevoked
    /// Blob storage is near/full (429): an account issue the user can act on.
    case quotaFull

    /// Whether this status is "attention" (amber) or ordinary reassurance
    /// colour. Only the transport issues the user must act on are attention;
    /// age, queue length and a service outage are not.
    public var isAttention: Bool {
        switch self {
        case .deviceRevoked, .quotaFull: return true
        case .synced, .waitingToSync, .serverUnreachable: return false
        }
    }
}

/// The pure status decision behind the Settings sync surface. Every display
/// choice that can be made without a simulator lives here so it tests at L1
/// (docs/TESTING.md) - the SwiftUI layer only renders the verdict.
public enum SyncSurface {
    /// The status, in the priority order that resolves the surface to one row:
    /// transport issues that need the user's action first, then the queue, then
    /// the reassurance default. `lastSyncDate` is deliberately **not** consulted
    /// here: age never changes the verdict (a queue a week old is the same as an
    /// hour old - the "never turns amber with age" rule).
    public static func status(_ state: SyncSurfaceState) -> SyncStatus {
        if state.deviceRevoked { return .deviceRevoked }
        if let quota = state.quotaUsedPercent, quota >= 95 { return .quotaFull }
        if state.transportUnavailable && state.dirtyCount == 0 {
            return .serverUnreachable
        }
        if state.dirtyCount > 0 { return .waitingToSync }
        return .synced
    }

    /// True when the status row should carry the offline suffix
    /// "Will sync when you're back online" (docs/ERRORS.md -> Settings): an
    /// offline device **with a queue**. A queue on a reachable device just
    /// waits; an offline device with nothing to push shows the unreachable
    /// reassurance instead.
    public static func isOfflineWithQueue(_ state: SyncSurfaceState) -> Bool {
        state.transportUnavailable && state.dirtyCount > 0
    }
}

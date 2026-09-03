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
    /// The last cycle could not reach the host: the device is offline. Passive
    /// (docs/ERRORS.md -> Settings) - never an error, "will sync when you're
    /// back online".
    public var offline: Bool
    /// The last cycle got a 5xx: the server is up but failing. Distinct from
    /// `offline` - it names the service being down with a next step.
    public var serverUnavailable: Bool
    /// The device was revoked (410) - a transport issue that belongs here.
    public var deviceRevoked: Bool
    /// The session expired and the refresh failed (PR.1): the user must sign in
    /// again. An account issue, surfaced as a card with its next step - never
    /// "update the app".
    public var authExpired: Bool
    /// Blob-storage quota usage percent; nil = no quota pressure (429).
    public var quotaUsedPercent: Int?
    /// Records carrying a `ConflictState` (derived, never stored).
    public var flaggedCount: Int
    /// A cycle is currently in flight (drives the "Sync now" spinner).
    public var isSyncing: Bool
    /// Low Power Mode is on (docs/SYNC.md -> Low Power Mode), so the background
    /// and opportunistic cycles that would drain the queue are being postponed.
    /// The app fills this from the injected power state - never `ProcessInfo`
    /// read at a call site - so the surface's "the reason is on" decision is
    /// testable exactly like `dirtyCount` and `offline`.
    public var lowPowerModeDeferring: Bool

    public init(
        isSignedIn: Bool,
        lastSyncDate: Date? = nil,
        dirtyCount: Int = 0,
        offline: Bool = false,
        serverUnavailable: Bool = false,
        deviceRevoked: Bool = false,
        authExpired: Bool = false,
        quotaUsedPercent: Int? = nil,
        flaggedCount: Int = 0,
        isSyncing: Bool = false,
        lowPowerModeDeferring: Bool = false
    ) {
        self.isSignedIn = isSignedIn
        self.lastSyncDate = lastSyncDate
        self.dirtyCount = dirtyCount
        self.offline = offline
        self.serverUnavailable = serverUnavailable
        self.deviceRevoked = deviceRevoked
        self.authExpired = authExpired
        self.quotaUsedPercent = quotaUsedPercent
        self.flaggedCount = flaggedCount
        self.isSyncing = isSyncing
        self.lowPowerModeDeferring = lowPowerModeDeferring
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
    /// The last cycle got a 5xx: the server is up but failing. Names the
    /// service being down with a next step ("Sync service unreachable - your
    /// data is safe..." + Try again) - reassurance, not amber, but distinct
    /// from the passive offline row (docs/ERRORS.md -> Settings).
    case serverUnreachable
    /// The device was signed out (410): an account issue the user can act on.
    case deviceRevoked
    /// The session expired and the refresh failed (PR.1): sign in again.
    case authExpired
    /// Blob storage is near/full (429): an account issue the user can act on.
    case quotaFull

    /// Whether this status is "attention" (amber) or ordinary reassurance
    /// colour. Only the transport issues the user must act on are attention;
    /// age, queue length and a service outage are not.
    public var isAttention: Bool {
        switch self {
        case .deviceRevoked, .authExpired, .quotaFull: return true
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
        if state.authExpired { return .authExpired }
        if let quota = state.quotaUsedPercent, quota >= 95 { return .quotaFull }
        if state.serverUnavailable { return .serverUnreachable }
        if state.dirtyCount > 0 { return .waitingToSync }
        return .synced
    }

    /// True when the status row should carry the offline suffix
    /// "Will sync when you're back online" (docs/ERRORS.md -> Settings): an
    /// offline device **with a queue**. A queue on a reachable device just
    /// waits; an offline device with nothing to push shows the ordinary synced
    /// reassurance instead - offline is never an error. A 5xx is deliberately
    /// NOT this row: `serverUnavailable` names the service being down, never
    /// "back online".
    public static func isOfflineWithQueue(_ state: SyncSurfaceState) -> Bool {
        state.offline && state.dirtyCount > 0
    }

    /// True when the status row should carry the Low Power reason (docs/SYNC.md
    /// -> Low Power Mode: "Waiting to sync · 5 changes · Low Power Mode is on"):
    /// the mode is on **and** a queue is waiting for exactly the background
    /// cycle the mode postpones. Nothing waiting means nothing deferred, so no
    /// reason is shown; the moment the mode ends the flag falls and the row
    /// returns to the plain S7 copy. Reassurance, never a warning - this never
    /// turns `isAttention`.
    public static func lowPowerReason(_ state: SyncSurfaceState) -> Bool {
        state.lowPowerModeDeferring && state.dirtyCount > 0
    }
}

/// The sync state chip's one state (RV.22, docs/SYNC.md -> "The sync state
/// chip"). The chip is ONE object changing state: the app layer maps each case
/// to a glyph, a colour and a label, but the decision - the precedence - lives
/// here so it tests at L1 (`SyncChipTests`). Seven cases, not the table's five
/// rows, because the three attention reasons need distinct labels and distinct
/// Settings scroll targets.
public enum SyncChipState: Equatable, Sendable {
    /// `!isSignedIn` with no attention reason: staying local is legitimate
    /// (hard rule 1), so the chip is deliberately colourless and taps to Sign
    /// in - the only state whose destination is not Settings.
    case signedOut
    /// The device was revoked (410): "Device signed out" - sign in again.
    case deviceRevoked
    /// The session expired and the refresh was rejected (PR.1): "Sign in again".
    case authExpired
    /// Blob storage >= 95% (429): "Storage full".
    case quotaFull
    /// A cycle is in flight: the system `ProgressView`, `action` colour.
    case syncing
    /// `dirtyCount > 0`: "Waiting to sync · N changes" - never amber, because a
    /// week of queue looks exactly like an hour of queue.
    case waiting
    /// The reassurance default: "Synced".
    case synced

    /// Whether this state is amber attention. The chip's ONLY amber is the
    /// three transport-issue states (hard rule 5: amber is attention only);
    /// age, queue length and a service outage are never amber.
    public var isAttention: Bool {
        switch self {
        case .deviceRevoked, .authExpired, .quotaFull: return true
        case .signedOut, .syncing, .waiting, .synced: return false
        }
    }
}

extension SyncSurface {
    /// The chip's state (RV.22). Precedence, first match wins, documented in
    /// docs/SYNC.md -> "The sync state chip":
    ///
    /// 1. `deviceRevoked` / `authExpired` / `quota >= 95` -> attention. These
    ///    outrank `!isSignedIn` deliberately: an expired session has cleared the
    ///    Keychain (`isSignedIn` reads false too) but is still an account issue
    ///    the user must act on, never "staying local".
    /// 2. `!isSignedIn` -> signedOut.
    /// 3. `isSyncing` -> syncing.
    /// 4. `dirtyCount > 0` -> waiting.
    /// 5. otherwise -> synced.
    ///
    /// `offline` and `serverUnavailable` are deliberately NOT states: offline
    /// with nothing to push is the ordinary synced reassurance ("offline is
    /// never an error", docs/SYNC.md), and a 5xx is a label variant of
    /// waiting/synced - never a promotion to warning. This is a SEPARATE
    /// function from `status()` on purpose: `status()` is the Settings-surface
    /// verdict and never consults `isSignedIn` or `isSyncing`, while the chip
    /// needs both (docs/SYNC.md -> "The sync state chip", the resolved
    /// `isSignedIn` gap).
    public static func chipState(_ state: SyncSurfaceState) -> SyncChipState {
        if state.deviceRevoked { return .deviceRevoked }
        if state.authExpired { return .authExpired }
        if let quota = state.quotaUsedPercent, quota >= 95 { return .quotaFull }
        if !state.isSignedIn { return .signedOut }
        if state.isSyncing { return .syncing }
        if state.dirtyCount > 0 { return .waiting }
        return .synced
    }

    /// Whether the warn dot rides the chip's corner (RV.22): `flaggedCount > 0`.
    /// Never a sixth state - the dot taps to the Log filtered to flagged entries
    /// over whatever state is showing (hard rule 8 keeps conflict badges where
    /// the data lives, docs/ERRORS.md -> Settings).
    public static func showsChipWarnDot(_ state: SyncSurfaceState) -> Bool {
        state.flaggedCount > 0
    }
}

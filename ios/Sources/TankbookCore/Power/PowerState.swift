import Foundation

// MARK: - P6.8 the injected power state (docs/SYNC.md -> Low Power Mode)

/// Supplies whether iOS Low Power Mode is on. Always injected, never
/// `ProcessInfo` read at a call site - a policy that reads the device directly
/// cannot be tested, and this policy's whole content is *when it says no*. The
/// same reason `TabBarMetrics` and `PumpPhotoGate` are values in core.
/// `ProcessInfo.processInfo` appears in exactly one place in the app: inside
/// `ProcessInfoPowerState`.
public protocol PowerStateProvider: Sendable {
    var isLowPowerModeEnabled: Bool { get }
}

/// The real implementation. Read once per query and never cached: the mode can
/// change while the app is foregrounded, and the deferral decision must track
/// it.
public struct ProcessInfoPowerState: PowerStateProvider {
    public init() {}
    public var isLowPowerModeEnabled: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}

/// Which opportunistic work is asking (docs/SYNC.md -> Low Power Mode table).
/// Distinct from the trigger: a background sync cycle and a "Sync now" tap are
/// the same work through different doors.
public enum PowerWorkKind: Sendable, Equatable {
    case syncCycle
    case blobUpload
    case blobPrefetch
    case ratePackRefresh
    case catalogPackFetch
    case timerJob
}

/// Why the work is happening. The load-bearing distinction (docs/SYNC.md ->
/// Low Power Mode): a policy that cannot tell background from user-initiated
/// will postpone a restore or a "Sync now" tap, and a user staring at a
/// spinner that was silently cancelled has no next step (hard rule 7) and
/// reads as a hang.
public enum PowerWorkTrigger: Sendable, Equatable {
    /// Launch, foreground, a timer, a debounced write, a WiFi change - work
    /// the app schedules for itself.
    case background
    /// A sync, restore, export or retry the user explicitly asked for.
    case userInitiated
}

/// The pure deferral policy: everything the Low Power Mode rule IS. A value in
/// core that never reads the device - the decision is a function of the
/// injected `lowPowerMode` boolean alone (docs/SYNC.md -> "The power state is
/// an injected value, never ProcessInfo read inline").
public enum LowPowerPolicy {
    /// Whether `work`, arriving through `trigger`, defers while the mode is on.
    ///
    /// Blob upload/prefetch and repeating timer jobs defer whenever the mode is
    /// on - the heaviest work there is - even inside a user-asked sync: the
    /// record stays dirty and the entry syncs text-first with the blob pending
    /// (S7), exactly as it does when the blob transport is down. Everything
    /// else defers only when the trigger is background; a sync, restore, export
    /// or retry the user asked for never defers.
    public static func defers(work: PowerWorkKind,
                              trigger: PowerWorkTrigger,
                              lowPowerMode: Bool) -> Bool {
        guard lowPowerMode else { return false }
        switch work {
        case .blobUpload, .blobPrefetch, .timerJob:
            return true
        case .syncCycle, .ratePackRefresh, .catalogPackFetch:
            return trigger == .background
        }
    }
}

import Foundation

// MARK: - RV.57 the reading phase (docs/JOURNEYS.md F4)

/// The gateway session's phase, as the Confirm sheet shows it. Lifted into core
/// so the proceed note's presence rule (`isInFlight`) tests at L1 rather than
/// only through a view. `GatewayScanSession` (app) aliases its `Phase` to this.
public enum GatewayReadingPhase: Equatable, Sendable {
    /// No request is running (no scan, no gateway armed, or signed out).
    case idle
    /// The request is in flight and the 3 s budget has not expired yet.
    case running
    /// The budget expired: the sheet has moved on, the request keeps running.
    case budgetExpired
    /// The request finished and a within-budget answer was applied (or a
    /// transport error left the on-device result standing).
    case answered
    /// The request was refused because the session cannot authenticate (RV.65):
    /// `/extract` 401'd and the refresh could not fix it (it was rejected, or it
    /// handed back the same bearer). The on-device result still stands - the
    /// entry is saveable - but cloud reading stays off until the user signs in
    /// again. `.authExpired` is the capture surface's name for the condition
    /// the Settings account card already calls "sign in again" (RV.26).
    case authExpired
    /// The entry was saved; a late answer is routed to the inbox (RV.38).
    case saved

    /// Whether a request is still in flight - the trigger for the proceed note
    /// (RV.57): a more reliable reading may still arrive while this is true, and
    /// only while this is true. `.idle` is the local-only parse (no transport
    /// was armed), so the note is absent there; `.answered`, `.authExpired` and
    /// `.saved` mean nothing more is coming.
    public var isInFlight: Bool {
        switch self {
        case .running, .budgetExpired: return true
        case .idle, .answered, .authExpired, .saved: return false
        }
    }

    /// The phase a failed reading should land in, named by the failure (RV.65).
    /// An auth-expired refusal - `/extract` 401'd and the refresh could not fix
    /// it (rejected, or it handed back the same bearer) - must surface as
    /// `.authExpired` so the capture can name "sign in" as the next step instead
    /// of failing silently. Every other refusal or transport failure leaves the
    /// on-device result standing as `.answered` (F4): the cloud half is a
    /// head start, never the whole entry.
    public static func phase(after error: any Error) -> GatewayReadingPhase {
        if let sync = error as? SyncServerError, sync == .authExpired {
            return .authExpired
        }
        return .answered
    }
}

// MARK: - RV.57 the proceed note's presence rule

/// The Confirm sheet's "a more reliable reading may still arrive" note. It is a
/// hint, never an error (hard rule 7): it names its next step (proceed now),
/// survives being ignored, and blocks nothing. Its presence is derived from
/// there being an in-flight request - absent on a local-only parse (`.idle`)
/// and once the request has answered or the entry is saved.
public enum GatewayProceedNote {
    public static func shouldShow(phase: GatewayReadingPhase) -> Bool {
        phase.isInFlight
    }
}

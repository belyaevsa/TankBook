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
    /// The entry was saved; a late answer is routed to the inbox (RV.38).
    case saved

    /// Whether a request is still in flight - the trigger for the proceed note
    /// (RV.57): a more reliable reading may still arrive while this is true, and
    /// only while this is true. `.idle` is the local-only parse (no transport
    /// was armed), so the note is absent there; `.answered` and `.saved` mean
    /// nothing more is coming.
    public var isInFlight: Bool {
        switch self {
        case .running, .budgetExpired: return true
        case .idle, .answered, .saved: return false
        }
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

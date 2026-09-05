import Foundation

// RV.68 - the shared classification for a transport-level error (one that
// produced NO HTTP response). Every client that used to throw "transport
// unreachable" for ANY non-HTTP error - import, account, feedback, the gateway
// outbox - now routes the underlying error through this before mapping it, so a
// cancellation never reads as offline, a TLS surprise never reads as "you need
// a connection", and only a genuine connectivity failure does. The distinction
// was already understood in these files (the `TankbookHTTPClientError` branch
// is separated deliberately, "never an offline state"); this type widens that
// line from one case to the whole non-response class.

/// The three outcomes that matter to an owner's error mapping when a request
/// produced no HTTP response (docs/ERRORS.md).
public enum TransportErrorClass: Sendable, Equatable {
    /// The device genuinely could not reach the host: offline, the network path
    /// dropped, DNS failed, or the request timed out. The only class that may
    /// render as an offline/"needs a connection" state.
    case connectivity
    /// The request was stopped before it had a conclusion (`URLError.cancelled`,
    /// `CancellationError`). Not a failure at all - the owner must not surface
    /// an error state and must not report a transport failure to the base-URL
    /// guardrails (docs/CONFIG.md: a cancellation is no evidence the URL is
    /// wrong).
    case cancelled
    /// A transport failure that is NOT a connectivity signal (TLS, a proxy, an
    /// unknown error type). Never "you need a connection": the device's network
    /// was fine, so that next step would send the user to fix something that is
    /// not broken (hard rule 7).
    case other
}

/// Classifies an underlying transport error by its type and `URLError.Code`.
/// Purely structural - hard rule 12: it reads an error *type* and a *code*,
/// never a payload, a URL query or a rendered message (a `localizedDescription`
/// can embed paths or domain values and is deliberately not consulted here).
public enum TransportErrorClassifier {
    public static func classify(_ error: any Error) -> TransportErrorClass {
        if error is CancellationError { return .cancelled }
        guard let urlError = error as? URLError else { return .other }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .timedOut, .dataNotAllowed, .internationalRoamingOff:
            return .connectivity
        case .cancelled:
            return .cancelled
        default:
            return .other
        }
    }
}

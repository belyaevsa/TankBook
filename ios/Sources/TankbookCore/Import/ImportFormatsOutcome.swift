import Foundation

// RV.68 - the source-step outcome of an import error, decided in core so it is
// L1-testable over the wire's error classes (docs/ERRORS.md -> Import wizard).
// The flow model translates this into the view's FormatsState; the view renders
// a distinct card per non-offline outcome. Keeping the decision here means a
// future re-map cannot silently turn a cancellation or a decode break back into
// the offline card without failing these tests.

/// The import wizard's source-step outcome for an import error.
public enum ImportFormatsOutcome: Sendable, Equatable {
    /// A genuine connectivity failure: the offline card, and only this outcome
    /// may reach it.
    case offline
    /// Not an error state at all (a cancelled request) - the wizard draws no
    /// conclusion and must not surface a card.
    case noError
    /// The response was not the expected JSON: a client/server contract break.
    case contractError
    /// The server answered with a non-2xx status.
    case serverError
    /// Anything else: the generic "couldn't load, try again" card.
    case failed
}

extension ImportClientError {
    /// The source-step outcome this error maps to (RV.68). `.offline` is
    /// reserved for `.transportUnreachable` - the ONLY case the client throws
    /// for a genuine connectivity failure; a `.cancelled` error is `.noError`,
    /// never a failure.
    public var formatsOutcome: ImportFormatsOutcome {
        switch self {
        case .transportUnreachable: return .offline
        case .cancelled: return .noError
        case .invalidResponse: return .contractError
        case .server: return .serverError
        case .client, .transportFailure, .oversize, .unrecognisedFormat,
             .doesNotMatchDeclared, .missingIdentity:
            return .failed
        }
    }
}

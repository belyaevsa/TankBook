import Foundation
import os

/// The per-cycle carrier of the wire diagnostics OB.1 added - the server's
/// problem+json `code` and `traceId` - from `RemoteSyncTransport.send`, where
/// they are thrown away today, to the coordinator, which persists them on a
/// failing cycle (OB.3).
///
/// Lock-guarded class for the same reason `SyncCoordinator` is: the transport
/// and the coordinator share one instance across async boundaries. The
/// coordinator **clears** it at the start of every cycle and `take()`s it when
/// the cycle ends in a failure; cycles are serialized by the coordinator's
/// `inFlight` gate, so a clear and a take can never interleave.
///
/// The record distinguishes three shapes on purpose:
/// - `record(code:traceId:)` - the server answered with an `httpError` (the
///   values may both be nil when the body carried no recognisable code, but the
///   server DID answer);
/// - `recordTransportFailure()` - the host was never reached (offline); the
///   explicit nil/nil record clears a PREVIOUS cycle's code so it cannot be
///   attributed to an offline cycle;
/// - nothing recorded at all - a cycle that never reached the transport (a
///   deferred or inert one), which the coordinator never `take()`s.
public final class SyncFailureDiagnostics: @unchecked Sendable {
    private struct Record: Equatable {
        var code: String?
        var traceId: String?
    }

    private let lock = OSAllocatedUnfairLock(initialState: Record?.none)

    public init() {}

    /// Records a server answer: the raw `code` and `traceId` read from the
    /// problem+json body. Both may be nil (a non-problem body) - what matters
    /// is that the server answered, so this is never mistaken for offline.
    public func record(code: String?, traceId: String?) {
        lock.withLock { $0 = Record(code: code, traceId: traceId) }
    }

    /// Records that the failure was transport-level (the host never answered).
    /// Writing nil/nil is deliberate: it clears any earlier cycle's code so a
    /// stale server code cannot ride along on an offline cycle.
    public func recordTransportFailure() {
        record(code: nil, traceId: nil)
    }

    /// Clears any recorded diagnostics at the start of a cycle.
    public func clear() {
        lock.withLock { $0 = nil }
    }

    /// Returns the recorded `(code, traceId)` and clears. Nil when nothing was
    /// recorded this cycle (a cycle that never reached the transport).
    public func take() -> (code: String?, traceId: String?)? {
        lock.withLock { snapshot -> (code: String?, traceId: String?)? in
            guard let record = snapshot else { return nil }
            snapshot = nil
            return (record.code, record.traceId)
        }
    }
}

import Foundation
import Network
import os
import TankbookCore

/// Observes the connectivity path and emits the `network.path` edge (OB.2).
///
/// A drop to unsatisfied mid-cycle is exactly the async edge that is invisible
/// unless it is written when it happens: an in-flight blob upload aborts when
/// the path dies, the record stays dirty, and the next cycle retries (S7) -
/// none of which reads as anything in the log without this line. The monitor
/// emits one `network.path` per transition (from/to are stable NWPath status
/// codes, Safe class) and, on a drop to unsatisfied, an `app.warning`
/// naming the upload abort so "the photo never arrived" has a why.
///
/// Privacy: no interface, no host, no SSID and no reachability *detail* ever
/// reaches a line - the transition is the whole story (hard rule 12). The real
/// abort of an in-flight PUT is the transport's own error path (a dead path
/// fails the socket); this type narrates the moment the device sees the drop.
public final class AppPathMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "tankbook.pathmonitor")
    private let lock = OSAllocatedUnfairLock(initialState: "unknown")
    private var lastStatus: String {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }

    public init() {}

    /// Starts observing. Safe to call once; the path handler runs on a private
    /// queue and only ever touches the thread-safe log facade.
    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let to = Self.status(path.status)
            let from = self.lastStatus
            guard to != from else { return }
            self.lastStatus = to
            AppLog.shared.emit(NetworkPathChange(from: from, to: to))
            if to == "unsatisfied" {
                // OB.2: a drop mid-cycle aborts an in-flight upload; the
                // record is left dirty (S7) and drains on the next cycle.
                // Handled degradation - a warning, never an error.
                AppLog.warning(operation: "blob.upload", category: .sync,
                               reason: "path_unsatisfied")
            }
        }
        monitor.start(queue: queue)
    }

    private static func status(_ status: NWPath.Status) -> String {
        switch status {
        case .satisfied: return "satisfied"
        case .unsatisfied: return "unsatisfied"
        case .requiresConnection: return "requiresConnection"
        @unknown default: return "unknown"
        }
    }
}

import Foundation

// MARK: - RV.215 the deferred recognition boundary (the save, not the answer)
//
// The fuel path has always had this state in `GatewayScanSession`: a read is
// started, the sheet opens on the on-device result, and an answer that lands
// AFTER `markSaved()` is not applied to the editor - it becomes an inbox item
// (RV.38). The service and expense reads used to run inline before their form
// opened, so they could never be late. This holder gives those two sessions the
// SAME state: `start` runs the read in the background, `markSaved` records the
// entry the read is about, and the closure that completes the read decides
// whether it is on time (apply to the open form) or late (the inbox, through
// `GatewayInboxPolicy` - the one policy, never a second producer).
//
// The decision itself is NOT here: this type only knows the boundary (did the
// save happen before the read finished). What a late answer becomes is
// `GatewayInboxPolicy.item(recognition:entry:)`, the same function the fuel
// path and the outbox drain call.

/// Tracks whether a deferred read finished before or after the entry was saved.
/// Main-actor isolated: the session and the view it feeds are main-actor too, so
/// the read's completion and `markSaved` are serialized and the boundary cannot
/// be crossed twice.
///
/// Unlike the fuel path's per-sheet `GatewayScanSession`, the service and expense
/// sessions are long-lived environment objects, so a new scan REPLACES the prior
/// read's state. The generation token is what stops a stale read (started before
/// a newer scan) from routing itself or flipping the newer read's phase.
@MainActor
final class DeferredRecognition {
    enum Phase: Equatable {
        /// No read has been started.
        case idle
        /// The read is in flight; the form is open on whatever it has.
        case running
        /// The read finished before the entry was saved - it went to the form.
        case answered
        /// The entry was saved; a read that finishes now is late (the inbox).
        case saved
    }

    private(set) var phase: Phase = .idle
    /// The entry the read is about, set the moment the user saves. Non-nil is
    /// exactly "the read is late": the closure `start` was given routes to the
    /// inbox with this id instead of the open form.
    private(set) var savedEntryID: UUID?
    /// The current read's token. A closure from an earlier `start` compares its
    /// captured token against this and drops itself when a newer scan began.
    private(set) var generation = 0

    /// Starts one read, replacing any prior read. `work` is handed this read's
    /// token and routes the outcome itself: on time to the open form, or - if
    /// `savedEntryID` was set while it ran - late, to the inbox. The work is the
    /// caller's, so the outcome type never crosses this type.
    func start(_ work: @escaping @MainActor (Int) async -> Void) {
        generation += 1
        let token = generation
        phase = .running
        savedEntryID = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            await work(token)
            guard self.generation == token, self.phase == .running else { return }
            self.phase = .answered
        }
    }

    /// The entry was saved. A read still in flight is now late and will route to
    /// the inbox; a read that already answered keeps its on-time delivery and
    /// produces no item (the form it filled is what the save wrote).
    func markSaved(entryID: UUID) {
        guard phase != .saved else { return }
        savedEntryID = entryID
        phase = .saved
    }
}

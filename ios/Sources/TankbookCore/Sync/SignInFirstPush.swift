import Foundation

/// The J11a first push (docs/JOURNEYS.md J11a -> "First push"): the moment a
/// sign-in must get the local log onto the account. The second device's
/// restore then finds a populated account; without it, the user is asked the
/// wrong-provider question over an account that is empty only because the
/// first device never pushed.
///
/// The sequencing lives in core so the two guarantees test at L1 with a
/// recording seam (docs/TESTING.md), and the app's `SignInFlow` is a thin
/// adapter over it:
///
/// 1. A completion path - signing in with a local log, or accepting the empty
///    restore - runs **exactly one** `.userInitiated` cycle. Never
///    `.background`: `LowPowerPolicy` defers a background cycle while Low
///    Power Mode is on, and a first push the user just asked for by signing in
///    must never be one of the things that waits.
/// 2. The **wrong-provider** path pushes nothing. The user has not accepted
///    this account, and pushing their log into it is the one irreversible
///    mistake on the screen.
public struct SignInFirstPush: Sendable {
    /// The post-sign-in paths the flow can be on when it asks this type to
    /// finish. `.wrongProvider` is a case only to pin the negative half of the
    /// guarantee: it is not a completion path and must never push.
    public enum Path: Sendable, Equatable {
        /// A populated local log signs in - it uploads, never overwritten
        /// (J11a's reverse guard).
        case uploadLocalLog
        /// The user accepted the empty restore ("Start fresh") - the account
        /// is accepted, so it receives the log.
        case acceptEmpty
        /// The restore found an empty account via "Already use Tankbook?" -
        /// the honest question, shown BEFORE the account is accepted.
        case wrongProvider
    }

    /// The sync seam. Production passes the app's one coordinator (which runs
    /// a user-initiated cycle); tests record the trigger. The trigger is the
    /// only thing this type decides about the push, and it is explicit.
    private let sync: @Sendable (PowerWorkTrigger) async -> Void

    public init(sync: @escaping @Sendable (PowerWorkTrigger) async -> Void) {
        self.sync = sync
    }

    /// Completes a sign-in path. Returns whether the flow should finish
    /// (dismiss the sheet): true for the two completion paths, false for the
    /// wrong-provider question.
    ///
    /// The completion paths run exactly one `.userInitiated` cycle first -
    /// docs/SYNC.md -> Low Power Mode: the work a user explicitly asked for
    /// never defers. The wrong-provider path issues no sync at all.
    public func complete(_ path: Path) async -> Bool {
        switch path {
        case .uploadLocalLog, .acceptEmpty:
            await sync(.userInitiated)
            return true
        case .wrongProvider:
            return false
        }
    }
}

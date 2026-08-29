import Foundation
import os
import Testing
@testable import TankbookCore

/// PJ.13 - the first push after sign-in (docs/JOURNEYS.md J11a -> "First
/// push"). The flow's completion paths are pinned at L1 with a recording seam,
/// both halves of the guarantee:
///
/// - a populated local log and an accepted empty restore each run **exactly
///   one** `.userInitiated` cycle - never `.background`, which
///   `LowPowerPolicy` defers while Low Power Mode is on;
/// - the wrong-provider path pushes nothing.
@Suite("SignInFirstPush (PJ.13)")
struct SignInFirstPushTests {

    /// A thread-safe recording seam: the async seam is `@Sendable`, and the
    /// test reads the recorded triggers after `complete` returns.
    private final class RecordingSync: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: [PowerWorkTrigger]())

        var triggers: [PowerWorkTrigger] {
            lock.withLock { $0 }
        }

        func call(_ trigger: PowerWorkTrigger) async {
            lock.withLock { $0.append(trigger) }
        }
    }

    // MARK: - The positive half: exactly one .userInitiated cycle

    /// The local-log branch uploads: one `.userInitiated` cycle, then the flow
    /// finishes. Exactly one - a second call would double-push, and the
    /// assertion is on the recorded triggers, never a count from a mock's
    /// opinion.
    @Test("a local log upload runs exactly one user-initiated cycle")
    func localLogBranchRunsExactlyOneUserInitiatedCycle() async {
        let recording = RecordingSync()
        let firstPush = SignInFirstPush { trigger in await recording.call(trigger) }

        let finished = await firstPush.complete(.uploadLocalLog)

        #expect(finished)
        #expect(recording.triggers == [.userInitiated],
                "a local log upload must run exactly one user-initiated cycle, got \(recording.triggers)")
    }

    /// Accepting the empty restore ("Start fresh") is the same shape: the
    /// account is accepted, so it receives the log - one user-initiated cycle.
    @Test("accepting the empty restore runs exactly one user-initiated cycle")
    func acceptEmptyRunsExactlyOneUserInitiatedCycle() async {
        let recording = RecordingSync()
        let firstPush = SignInFirstPush { trigger in await recording.call(trigger) }

        let finished = await firstPush.complete(.acceptEmpty)

        #expect(finished)
        #expect(recording.triggers == [.userInitiated],
                "accepting the empty restore must run exactly one user-initiated cycle, got \(recording.triggers)")
    }

    /// The trigger is what keeps a first push out of the Low Power queue: a
    /// `.background` cycle defers while the mode is on (docs/SYNC.md -> Low
    /// Power Mode), and the push the user just asked for by signing in must
    /// never wait. The assertion is the policy itself on the recorded trigger.
    @Test("the recorded trigger never defers under Low Power Mode")
    func userInitiatedTriggerIsNotDeferredByLowPower() async {
        let recording = RecordingSync()
        let firstPush = SignInFirstPush { trigger in
            #expect(!LowPowerPolicy.defers(work: .syncCycle, trigger: trigger, lowPowerMode: true),
                    "a user-initiated first push must never defer under Low Power Mode")
            await recording.call(trigger)
        }

        _ = await firstPush.complete(.uploadLocalLog)

        #expect(recording.triggers == [.userInitiated])
    }

    // MARK: - The negative half: wrongProvider pushes nothing

    /// The wrong-provider path is not a completion path: it pushes nothing
    /// into an account the user has not accepted, and the flow must not finish
    /// from it (the sheet stays on the honest question).
    @Test("the wrong-provider path never pushes and never finishes the flow")
    func wrongProviderPushesNothing() async {
        let recording = RecordingSync()
        let firstPush = SignInFirstPush { trigger in await recording.call(trigger) }

        let finished = await firstPush.complete(.wrongProvider)

        #expect(!finished, "the wrong-provider question must not finish the flow")
        #expect(recording.triggers.isEmpty,
                "the wrong-provider path must never push; got \(recording.triggers)")
    }
}

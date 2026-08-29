import Foundation
import os
import Testing
@testable import TankbookCore

// PR.7 - the coordinator half: a retryable outcome actually SCHEDULES the next
// cycle (the original defect: the notice promised "Retrying in N minutes" and
// nothing scheduled a retry), at the policy's delay, and a refusal schedules
// nothing. Every schedule assertion is driven by an injected gate - never a
// real sleep, and never a wall-clock race (the GatewayBudget lesson).

/// A retry waiter that records each delay it is asked to sleep and blocks until
/// `releaseAll()`. Latched: a release before the wait means the wait returns
/// immediately, so no ordering between "the retry task starts" and "the test
/// releases" can deadlock.
private final class GatedRetryWaiter: @unchecked Sendable {
    private struct State {
        var delays: [Duration] = []
        var waiting: [@Sendable () -> Void] = []
        var released = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func wait(_ delay: Duration) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            state.withLock { snapshot in
                snapshot.delays.append(delay)
                if snapshot.released {
                    continuation.resume()
                } else {
                    snapshot.waiting.append { continuation.resume() }
                }
            }
        }
    }

    func releaseAll() {
        let waiters = state.withLock { snapshot -> [@Sendable () -> Void] in
            snapshot.released = true
            defer { snapshot.waiting.removeAll() }
            return snapshot.waiting
        }
        waiters.forEach { $0() }
    }

    var recordedDelays: [Duration] {
        state.withLock { $0.delays }
    }
}

@Suite("Sync coordinator retry (PR.7)")
struct SyncCoordinatorRetryTests {

    /// Polls until `condition` holds, sleeping in 5 ms steps, so a test never
    /// blocks forever on a concurrent retry task that has not fired yet. The
    /// assertion itself is on a deterministic value, never on a wall clock.
    private func waitUntil(_ condition: () -> Bool, maxSleeps: Int = 2000) async {
        for _ in 0..<maxSleeps {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: - A 429 schedules one cycle at Retry-After, none earlier

    @Test("a 429 with Retry-After: 120 schedules one cycle at +120 s, none earlier")
    func rateLimitedSchedulesOneRetryAtRetryAfter() async throws {
        let repo = try makeSyncRepository()
        let vehicle = makeSyncVehicle()
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        try repo.upsertFillUp(makeSyncFillUp(vehicleId: vehicle.id), syncState: .dirty)

        let transport = SyncTransportDouble()
        transport.enqueuePushError(.rateLimited(retryAfterSeconds: 120))

        let waiter = GatedRetryWaiter()
        let coordinator = SyncCoordinator(
            engine: makeSyncEngine(repository: repo, transport: transport),
            jitter: { 0.5 },
            retryWait: { await waiter.wait($0) })

        let outcome = await coordinator.syncNow()
        #expect(outcome.retryAfterSeconds == 120)
        #expect(outcome.refusedByServer == .rateLimited(retryAfterSeconds: 120))

        // Exactly one retry, at the server's 120 s - not the curve's 1 s, and
        // nothing earlier. The scheduled delay is set synchronously, so it is
        // asserted here with no race; the recorded wait is asserted after the
        // retry has actually fired below.
        #expect(coordinator.scheduledRetryDelay() == .seconds(120))

        // Release: the retry re-runs the cycle, which now succeeds (the double's
        // default push), and the pending retry clears.
        waiter.releaseAll()
        await waitUntil { transport.recordedPushBatches.count == 2 }

        #expect(transport.recordedPushBatches.count == 2)
        #expect(waiter.recordedDelays == [.seconds(120)])
        #expect(coordinator.scheduledRetryDelay() == nil)
    }

    // MARK: - A 5xx schedules the policy's backoff and re-runs

    @Test("an outage schedules the policy's first backoff delay and re-runs")
    func outageSchedulesThePolicyBackoffAndReRuns() async throws {
        let repo = try makeSyncRepository()
        let transport = SyncTransportDouble()
        transport.enqueuePullError(.transportUnavailable)

        let waiter = GatedRetryWaiter()
        let coordinator = SyncCoordinator(
            engine: makeSyncEngine(repository: repo, transport: transport),
            jitter: { 1.0 },
            retryWait: { await waiter.wait($0) })

        let outcome = await coordinator.syncNow()
        #expect(outcome.transportUnavailable)

        // jitter 1.0 -> the upper bound, so the first backoff is exactly 1 s.
        #expect(coordinator.scheduledRetryDelay() == .seconds(1))

        waiter.releaseAll()
        await waitUntil { transport.recordedPullRequests.count == 2 }
        #expect(transport.recordedPullRequests.count == 2)
        #expect(coordinator.scheduledRetryDelay() == nil)
    }

    // MARK: - Refusals schedule nothing

    @Test("401, 402, 410 and 426 schedule no retry")
    func refusalsScheduleNoRetry() async throws {
        // Each maps to its own engine catch: 426/402 on push, 401/410 on pull.
        let scenarios: [(error: SyncServerError, viaPush: Bool)] = [
            (.upgradeRequired, true),
            (.tierRefused, true),
            (.authExpired, false),
            (.deviceRevoked, false)
        ]
        for scenario in scenarios {
            let repo = try makeSyncRepository()
            let vehicle = makeSyncVehicle()
            try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))
            try repo.upsertFillUp(makeSyncFillUp(vehicleId: vehicle.id), syncState: .dirty)

            let transport = SyncTransportDouble()
            if scenario.viaPush {
                transport.enqueuePushError(scenario.error)
            } else {
                transport.enqueuePullError(scenario.error)
            }
            let coordinator = SyncCoordinator(
                engine: makeSyncEngine(repository: repo, transport: transport),
                retryWait: { _ in })

            _ = await coordinator.syncNow()
            #expect(coordinator.scheduledRetryDelay() == nil,
                    "\(scenario.error) is a refusal, not a transient fault - it must not be retried")
        }
    }
}

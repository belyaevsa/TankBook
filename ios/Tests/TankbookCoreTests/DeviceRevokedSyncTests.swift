import Foundation
import os
import Testing
@testable import TankbookCore

// RV.58 - a 410 (device revoked) is TERMINAL for the sync cycle. The corrected
// row: the production log shows one device running pull, blob and push traffic
// for ~3 minutes after a `GET /sync/pull -> 410` (14:53:10 -> 14:56:04). 410 is
// the server saying access is gone; the client must end the cycle and route to
// sign-in, not carry on.
//
// What "terminal" must mean, and what the mutations are:
//  - The CYCLE stops: after a 410 on pull no push runs and no page is re-read,
//    and after a 410 on push no further batch runs. Asserted by the REQUEST
//    COUNT on the recording transport - never by a flag or a state enum (the
//    vacuous trap the row names).
//  - It is NEVER retried: the refusal classes are not transient faults. Under
//    the mutation "treat 410 like any other failure", the coordinator schedules
//    a backoff retry and a second request fires - the request-count assertion
//    must go red.
//  - Hard rule 8: nothing local is deleted - the dirty queue stays dirty.

/// A retry waiter that records each delay it is asked to sleep and blocks until
/// `releaseAll()` (the `SyncCoordinatorRetryTests` seam, copied here so this
/// suite's schedule assertions never wait on a wall clock).
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

@Suite("Device revoked (410) is terminal for the cycle (RV.58)")
struct DeviceRevokedSyncTests {

    /// Builds a repository with one synced vehicle and one dirty fill - the
    /// dirty fill is the row a buggy cycle would PUSH after the pull 410, so
    /// the request-count assertions have something to catch.
    private func makeRepoWithDirtyQueue() throws -> (TankbookRepository, UUID) {
        let repository = try makeSyncRepository()
        let vehicle = makeSyncVehicle()
        try repository.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        let fill = makeSyncFillUp(vehicleId: vehicle.id)
        try repository.upsertFillUp(fill, syncState: .dirty)
        return (repository, vehicle.id)
    }

    // MARK: - The headline: a 410 on pull produces NO further request

    /// The headline L1 (docs/TASKS.md RV.58): over a recording transport, a 410
    /// on pull produces no further request in that cycle - asserted by the
    /// cycle STOPPING (the request count never grows), not by a flag. A dirty
    /// queue is present, so a cycle that failed to stop would push it and
    /// re-pull.
    @Test("a 410 on pull stops the cycle: one pull, no push, no retry, no further request")
    func pull410StopsTheCycleWithNoFurtherRequests() async throws {
        let (repo, _) = try makeRepoWithDirtyQueue()
        let transport = SyncTransportDouble()
        transport.enqueuePullError(.deviceRevoked)

        let waiter = GatedRetryWaiter()
        let coordinator = SyncCoordinator(
            engine: makeSyncEngine(repository: repo, transport: transport),
            jitter: { 1.0 },
            retryWait: { await waiter.wait($0) })

        let outcome = await coordinator.syncNow()

        // The outcome is a revocation - never a transport outage, never an auth
        // expiry, and never the queue's own "waiting" state.
        #expect(outcome.deviceRevoked)
        #expect(!outcome.serverUnavailable && !outcome.offline && !outcome.authExpired)

        // The request count after the 410: exactly the ONE pull that answered
        // it. No push of the dirty queue, no second pull page.
        #expect(transport.recordedPullRequests.count == 1,
                "the cycle must not pull again after the 410; got \(transport.recordedPullRequests.count)")
        #expect(transport.recordedPushBatches.isEmpty,
                "the dirty queue must not push after the pull 410")

        // A 410 is a refusal, never retried (SyncRetryPolicy excludes the
        // refusal classes). The deterministic assertion: no retry is scheduled.
        #expect(coordinator.scheduledRetryDelay() == nil,
                "a 410 must not schedule a retry - retrying a revoked device is the three-minute tail")

        // Belt: release any (buggy) retry waiter and give it a bounded moment to
        // fire. Under the mutation "treat 410 like any other failure" a second
        // pull lands here and the count assertion goes red.
        waiter.releaseAll()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(transport.recordedPullRequests.count == 1,
                "after the 410 the cycle must stay stopped; a retry fired a request")
        #expect(transport.recordedPushBatches.isEmpty,
                "after the 410 the dirty queue must stay un-pushed")
        #expect(waiter.recordedDelays.isEmpty,
                "the revoked outcome must not have scheduled any retry delay")
    }

    /// Hard rule 8: a 410 does not delete local entries. The vehicle row and the
    /// dirty fill are still there and still dirty after the cycle - nothing is
    /// destroyed and nothing is silently marked synced.
    @Test("a 410 leaves local rows untouched: the queue stays dirty (hard rule 8)")
    func pull410LeavesLocalEntriesUntouched() async throws {
        let (repo, vehicleID) = try makeRepoWithDirtyQueue()
        let transport = SyncTransportDouble()
        transport.enqueuePullError(.deviceRevoked)

        let outcome = await makeSyncEngine(repository: repo, transport: transport).synchronize()

        #expect(outcome.deviceRevoked)
        let dirty = try repo.fetchDirtyRows()
        #expect(dirty.count == 1, "the unsynced fill stays dirty - nothing is lost (S7)")
        let fills = try repo.liveFillUps(forVehicle: vehicleID)
        #expect(fills.count == 1, "the local fill row is untouched by the 410")
    }

    /// A 410 during PUSH was the quieter half of the defect: it folded into the
    /// generic 5xx catch, surfaced as `serverUnavailable`, and the retry policy
    /// then RETRIED it with backoff - a revoked device kept cycling. It is a
    /// revocation and it is terminal, exactly as on pull.
    @Test("a 410 on push is deviceRevoked, not an outage, and is never retried")
    func push410IsTerminalAndSurfacesDeviceRevoked() async throws {
        let (repo, _) = try makeRepoWithDirtyQueue()
        let transport = SyncTransportDouble()
        transport.enqueuePushError(.deviceRevoked)

        let waiter = GatedRetryWaiter()
        let coordinator = SyncCoordinator(
            engine: makeSyncEngine(repository: repo, transport: transport),
            jitter: { 1.0 },
            retryWait: { await waiter.wait($0) })

        let outcome = await coordinator.syncNow()

        #expect(outcome.deviceRevoked,
                "a push-side 410 is a revocation, not the 'service is down' folding it used to get")
        #expect(!outcome.serverUnavailable, "a 410 must never be misread as a 5xx outage")
        #expect(coordinator.scheduledRetryDelay() == nil,
                "the push-side 410 must not schedule the backoff a 5xx would")

        // One pull (empty page), one push (the dirty batch that answered 410),
        // and then nothing further in the cycle.
        #expect(transport.recordedPullRequests.count == 1)
        #expect(transport.recordedPushBatches.count == 1,
                "the batch that answered 410 is the only push")

        waiter.releaseAll()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(transport.recordedPushBatches.count == 1,
                "after the push 410 the cycle must stay stopped; a retry fired another push")
        let dirty = try repo.fetchDirtyRows()
        #expect(dirty.count == 1, "the row the refused push left stays dirty (S7) - nothing is lost")
    }

    // MARK: - The surface after the drop

    /// RV.58 drops the session on a 410, so `isSignedIn` reads false - but the
    /// revoked device must still read as a revocation, never as the colourless
    /// "Not signed in" (the same precedence rule authExpired already pins:
    /// attention conditions are evaluated before `!isSignedIn`).
    @Test("a revoked device with the session dropped still reads as deviceRevoked, not signed out")
    func revokedOutranksSignedOutAfterTheSessionDrop() {
        let state = SyncSurfaceState(isSignedIn: false, deviceRevoked: true)
        #expect(SyncSurface.chipState(state) == .deviceRevoked)
        #expect(SyncSurface.status(state) == .deviceRevoked)
        #expect(SyncStatus.deviceRevoked.isAttention)
    }
}

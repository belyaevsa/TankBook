import Foundation
import os
import Testing
@testable import TankbookCore

// P4.9b: the Settings sync surface's load-bearing invariants (docs/SYNC.md ->
// "The Settings sync surface"). Four rules, each tested at L1 so they hold
// without a simulator:
//
//  1. The flagged count is DERIVED - recomputed from records carrying a
//     `ConflictState`, never read from a stored field (hard rule 2's principle).
//  2. "Sync now" is IDEMPOTENT - a tap while a cycle is in flight issues no
//     second transport call. Asserted on the push count, not the button state.
//  3. Offline "Sync now" is NOT an error - it produces the waiting copy, no
//     error/attention surface.
//  4. The status never turns amber with age - a queue hours or a week old
//     renders in the ordinary status colour (assert the token, not a pixel).
// MARK: - A transport that can hold a cycle in flight

/// A `SyncTransport` whose `pull` blocks until released, so a test can hold a
/// sync cycle in flight deterministically and observe whether a second trigger
/// issues a transport call. `releasePull` fans out to every waiting `pull`, so
/// a broken idempotency guard (a second cycle starting) fails the count
/// assertion rather than deadlocking the test.
private final class BlockingPullTransport: SyncTransport, @unchecked Sendable {
    private struct State {
        var pullCount = 0
        var waiting: [@Sendable () -> Void] = []
        var pushCount = 0
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func waitUntilPulling() async {
        while true {
            if state.withLock({ $0.pullCount > 0 }) { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    func releasePull() {
        let waiters = state.withLock { snapshot -> [@Sendable () -> Void] in
            defer { snapshot.waiting.removeAll() }
            return snapshot.waiting
        }
        waiters.forEach { $0() }
    }

    var recordedPullCount: Int {
        state.withLock { $0.pullCount }
    }

    var recordedPushCount: Int {
        state.withLock { $0.pushCount }
    }

    func pull(since: Int64, limit: Int) async throws -> SyncPullResponse {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            state.withLock { snapshot in
                snapshot.pullCount += 1
                snapshot.waiting.append { continuation.resume() }
            }
        }
        return SyncPullResponse(records: [], nextSince: since, more: false,
                                schemaPolicy: SyncSchemaPolicy(minSupported: 1, current: 1))
    }

    func push(_ changes: [SyncPushChange]) async throws -> SyncPushResponse {
        state.withLock { $0.pushCount += 1 }
        var scn: Int64 = 1
        return SyncPushResponse(results: changes.map { change in
            defer { scn += 1 }
            return SyncPushResult(id: change.id, status: .accepted(newScn: scn, clamped: false))
        })
    }
}

@Suite("Settings sync surface (P4.9b)")
struct SyncCoordinatorTests {

    // MARK: - 1. The flagged count is derived, never stored

    @Test func flaggedEntryCountIsRecomputedNotStored() throws {
        let repo = try makeSyncRepository()
        let vehicle = makeSyncVehicle()
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))

        var flagged1 = makeSyncFillUp(vehicleId: vehicle.id)
        flagged1.conflict = .flagged(kind: .order, detectedAt: Date())
        var flagged2 = makeSyncFillUp(vehicleId: vehicle.id)
        flagged2.conflict = .flagged(kind: .pace, detectedAt: Date())
        let clean = makeSyncFillUp(vehicleId: vehicle.id)
        try repo.upsertFillUp(flagged1, syncState: .synced(scn: 2))
        try repo.upsertFillUp(flagged2, syncState: .synced(scn: 3))
        try repo.upsertFillUp(clean, syncState: .synced(scn: 4))

        // The expected number is a literal - not the view's own function called
        // back on itself, which would be a vacuous assertion.
        #expect(try repo.flaggedEntryCount() == 2)

        // Resolving a conflict elsewhere (an edit sets conflict -> .none) changes
        // the count with no write to any Settings surface - there is none to
        // write to. The value is recomputed from the records, so the two cannot
        // drift apart.
        var resolved = flagged1
        resolved.conflict = .none
        try repo.upsertFillUp(resolved, syncState: .synced(scn: 2))
        #expect(try repo.flaggedEntryCount() == 1)
    }

    // MARK: - 2. "Sync now" is idempotent

    @Test func syncNowIssuesNoSecondPushWhileInFlight() async throws {
        let repo = try makeSyncRepository()
        let vehicle = makeSyncVehicle()
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        try repo.upsertFillUp(makeSyncFillUp(vehicleId: vehicle.id), syncState: .dirty)

        let transport = BlockingPullTransport()
        let coordinator = SyncCoordinator(engine: makeSyncEngine(repository: repo, transport: transport))

        let first = Task { await coordinator.syncNow() }
        await transport.waitUntilPulling()   // the first cycle is now in flight (blocked in pull)

        // A repeated tap while in flight must be inert: no second cycle starts,
        // so no second transport call (pull OR push) is issued.
        let second = Task { await coordinator.syncNow() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(transport.recordedPullCount == 1,
                "a tap during an in-flight sync must not start a second cycle")

        transport.releasePull()
        _ = await first.value
        _ = await second.value

        // Exactly one push for the one dirty row - the repeated tap did not queue
        // a second. Asserted on the transport call count, never a button state.
        #expect(transport.recordedPushCount == 1,
                "the idempotency assertion is on the push count, not a button state")
    }

    // MARK: - 3. Offline "Sync now" is not an error

    @Test func offlineSyncNowProducesTheWaitingCopyNotAnError() async throws {
        let repo = try makeSyncRepository()
        let vehicle = makeSyncVehicle()
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        try repo.upsertFillUp(makeSyncFillUp(vehicleId: vehicle.id), syncState: .dirty)

        let transport = SyncTransportDouble()
        transport.setFailAll(true)   // offline
        let coordinator = SyncCoordinator(engine: makeSyncEngine(repository: repo, transport: transport))

        let outcome = await coordinator.syncNow()
        #expect(outcome.offline, "the engine reports an outage as a flag, not an error type")

        // The dirty row is untouched - nothing was lost, nothing is an error.
        #expect(try repo.fetchDirtyRows().count == 1)

        let state = SyncSurfaceState(
            isSignedIn: true,
            dirtyCount: try repo.fetchDirtyRows().count,
            offline: outcome.offline)
        let status = SyncSurface.status(state)
        #expect(status == .waitingToSync, "offline sync-now settles back to the waiting copy")
        #expect(status.isAttention == false, "offline is never an error surface")
        #expect(SyncSurface.isOfflineWithQueue(state),
                "an offline device with a queue names its next step: back online")
    }

    // MARK: - 4. The status never turns amber with age

    @Test func statusNeverTurnsAmberWithAge() {
        let now = Date()
        let hoursOld = now.addingTimeInterval(-3 * 3600)
        let weekOld = now.addingTimeInterval(-7 * 86_400)

        let hoursState = SyncSurfaceState(isSignedIn: true, lastSyncDate: hoursOld, dirtyCount: 5)
        let weekState = SyncSurfaceState(isSignedIn: true, lastSyncDate: weekOld, dirtyCount: 5)

        let hoursStatus = SyncSurface.status(hoursState)
        let weekStatus = SyncSurface.status(weekState)
        #expect(hoursStatus == .waitingToSync)
        #expect(weekStatus == .waitingToSync)
        #expect(hoursStatus.isAttention == false, "a 3-hour queue is not attention")
        #expect(weekStatus.isAttention == false, "a week-old queue is not attention - a week offline is an hour (S7)")

        // The attention states are the transport issues the user must act on,
        // never age or queue length.
        #expect(SyncSurface.status(SyncSurfaceState(isSignedIn: true, deviceRevoked: true)).isAttention)
        #expect(SyncSurface.status(SyncSurfaceState(isSignedIn: true, quotaUsedPercent: 95)).isAttention)
        #expect(!SyncSurface.status(SyncSurfaceState(isSignedIn: true, serverUnavailable: true)).isAttention,
                "a service outage is reassurance, not attention")
    }

    // MARK: - 5. The Low Power reason (P6.8, docs/SYNC.md -> Low Power Mode)

    @Test func lowPowerReasonShowsOnlyWhenTheModeIsOnAndAQueueIsWaiting() {
        // The reason belongs on S7's passive row: the mode is on and a queue is
        // waiting for exactly the background cycle the mode postpones.
        #expect(SyncSurface.lowPowerReason(SyncSurfaceState(
            isSignedIn: true, dirtyCount: 5, lowPowerModeDeferring: true)))
        #expect(!SyncSurface.lowPowerReason(SyncSurfaceState(
            isSignedIn: true, dirtyCount: 5, lowPowerModeDeferring: false)),
            "no reason when the mode is off - a plain S7 queue has no Low Power cause")
        #expect(!SyncSurface.lowPowerReason(SyncSurfaceState(
            isSignedIn: true, dirtyCount: 0, lowPowerModeDeferring: true)),
            "nothing waiting means nothing is deferred - no reason")
    }

    @Test func lowPowerReasonIsReassuranceNeverAttention() {
        // Low Power Mode is a state the OS put the device in, not an error
        // (docs/SYNC.md -> Low Power Mode: "reassurance, never a warning"). The
        // reason must not turn the row amber.
        let state = SyncSurfaceState(isSignedIn: true, dirtyCount: 5,
                                     lowPowerModeDeferring: true)
        #expect(SyncSurface.status(state) == .waitingToSync)
        #expect(SyncSurface.status(state).isAttention == false,
                "the Low Power reason is never amber")
    }
}

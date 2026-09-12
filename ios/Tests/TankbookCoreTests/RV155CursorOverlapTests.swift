import Foundation
import os
import Testing
@testable import TankbookCore

// RV.155: a restore and the app's regular sync can run at the same time - the
// restore engine bypasses the coordinator's in-flight gate. The restore's
// cursor advance must be durable at the pull that earned it, so the second
// cycle reads it instead of re-fetching the delta.

private let policy = SyncSchemaPolicy(minSupported: 1, current: 1)

/// A one-shot async signal: `wait()` returns immediately once `signal()` has
/// fired, and otherwise resumes when it does.
private final class Signal: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var fired = false

    func signal() {
        lock.lock()
        fired = true
        let waiting = continuations
        continuations = []
        lock.unlock()
        for continuation in waiting { continuation.resume() }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if fired {
                lock.unlock()
                continuation.resume()
            } else {
                continuations.append(continuation)
                lock.unlock()
            }
        }
    }
}

/// A transport whose push is held open until the test releases it, so a second
/// cycle can start while the first is still mid-cycle.
private final class GatedPushTransport: SyncTransport, @unchecked Sendable {
    private struct State {
        var pullRequests: [Int64] = []
        var pushCount = 0
    }

    private let pullResponse: SyncPullResponse
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let pushEntered = Signal()
    private let releasePush = Signal()

    init(pull: SyncPullResponse) { self.pullResponse = pull }

    func pull(since: Int64, limit: Int) async throws -> SyncPullResponse {
        state.withLock { $0.pullRequests.append(since) }
        return pullResponse
    }

    func push(_ changes: [SyncPushChange]) async throws -> SyncPushResponse {
        state.withLock { $0.pushCount += 1 }
        pushEntered.signal()
        await releasePush.wait()
        return SyncPushResponse(results: changes.map {
            SyncPushResult(id: $0.id, status: .accepted(newScn: 99, clamped: false))
        })
    }

    var recordedPulls: [Int64] { state.withLock { $0.pullRequests } }
    func waitUntilPushing() async { await pushEntered.wait() }
    func release() { releasePush.signal() }
}

@Test func overlappingCyclesShareTheCursorAdvance() async throws {
    let durable = InMemorySyncCursorStore()
    // The restore must pull from 0 even when the durable cursor holds a value,
    // but its advance must reach `durable` at the pull that earned it.
    let restoreCursor = SeededSyncCursorStore(seed: 0, persistingTo: durable)

    // Cycle A is the restore: it pulls from 0 and its push is held open, so the
    // cycle has not finished when cycle B starts.
    let restoreRepo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try restoreRepo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))
    try restoreRepo.upsertFillUp(makeSyncFillUp(id: UUID.v7(), vehicleId: vehicleId))
    let transportA = GatedPushTransport(pull: SyncPullResponse(
        records: [], nextSince: 10, more: false, schemaPolicy: policy))
    let engineA = makeSyncEngine(repository: restoreRepo, transport: transportA, cursor: restoreCursor)

    // Cycle B is the app's regular sync, sharing the durable store.
    let appRepo = try makeSyncRepository()
    let transportB = SyncTransportDouble()
    transportB.enqueuePull(SyncPullResponse(
        records: [], nextSince: 20, more: false, schemaPolicy: policy))
    let engineB = makeSyncEngine(repository: appRepo, transport: transportB, cursor: durable)

    let cycleA = Task { await engineA.synchronize() }
    await transportA.waitUntilPushing()
    // A's pull returned and advanced its cursor to 10; A's cycle is still open
    // in its push. B must not re-fetch the delta.
    _ = await engineB.synchronize()
    #expect(transportB.recordedPullRequests.first?.since == 10,
            "the second overlapping cycle resumes from the first's nextSince")
    #expect(transportA.recordedPulls == [0], "the restore still starts from 0")

    transportA.release()
    _ = await cycleA.value
}

@Test func failedPullDoesNotAdvanceTheCursor() async throws {
    let durable = InMemorySyncCursorStore()
    try durable.save(50)
    let cursor = SeededSyncCursorStore(seed: 0, persistingTo: durable)
    let transport = SyncTransportDouble()
    transport.enqueuePullError(.offline)
    let engine = makeSyncEngine(repository: try makeSyncRepository(),
                                transport: transport, cursor: cursor)

    let outcome = await engine.synchronize()

    #expect(outcome.offline)
    #expect(try durable.load() == 50, "a failed pull never advances the durable cursor")
    #expect(try cursor.load() == 0, "the restore session still starts from the seed")
}

/// The production restore provider must wire the write-through store - the test
/// above proves the store, this proves the wiring, which no package-level test
/// can reach.
@Test func restoreProviderWiresTheWriteThroughCursor() throws {
    let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("App/Sources/SignIn/SignInFlow.swift"), encoding: .utf8)
    #expect(source.contains("SeededSyncCursorStore(seed: 0"),
            "the restore must start from 0 and persist each advance through")
    #expect(!source.contains("InMemorySyncCursorStore()"),
            "the restore must not buffer its cursor in memory until the cycle ends")
}

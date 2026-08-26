import Foundation
import os
@testable import TankbookCore

// Shared sync test doubles (P4.5). `SyncTransportDouble` is a deterministic
// in-memory `SyncTransport`: it records every pull/push it receives and returns
// scripted responses, so the S1-S9 suite asserts against what was actually sent
// rather than a mock's opinion (the same trap named in the P4.4 brief).

/// A scripted, recording `SyncTransport`. The lock makes it a valid `Sendable`
/// double for the async engine.
final class SyncTransportDouble: SyncTransport, @unchecked Sendable {
    private struct State {
        var pullResponses: [Result<SyncPullResponse, SyncServerError>] = []
        var pushResponses: [Result<SyncPushResponse, SyncServerError>] = []
        var pullRequests: [(since: Int64, limit: Int)] = []
        var pushBatches: [[SyncPushChange]] = []
        var callOrder: [String] = []
        var alwaysConflict = false
        var conflictCurrent: SyncPullRecord?
        var failAll = false
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    func enqueuePull(_ response: SyncPullResponse) {
        lock.withLock { $0.pullResponses.append(.success(response)) }
    }

    func enqueuePullError(_ error: SyncServerError) {
        lock.withLock { $0.pullResponses.append(.failure(error)) }
    }

    func enqueuePush(_ response: SyncPushResponse) {
        lock.withLock { $0.pushResponses.append(.success(response)) }
    }

    func enqueuePushError(_ error: SyncServerError) {
        lock.withLock { $0.pushResponses.append(.failure(error)) }
    }

    /// Makes every push answer `conflict(current:)` with the given record - the
    /// S6 "server conflicts forever" harness.
    func setAlwaysConflict(current: SyncPullRecord) {
        lock.withLock {
            $0.alwaysConflict = true
            $0.conflictCurrent = current
        }
    }

    func setFailAll(_ fail: Bool) {
        lock.withLock { $0.failAll = fail }
    }

    var recordedPullRequests: [(since: Int64, limit: Int)] {
        lock.withLock { $0.pullRequests }
    }

    var recordedPushBatches: [[SyncPushChange]] {
        lock.withLock { $0.pushBatches }
    }

    /// The interleaved call order ("pull"/"push"), for the S7 pull-before-push
    /// assertion.
    var recordedCallOrder: [String] {
        lock.withLock { $0.callOrder }
    }

    func pull(since: Int64, limit: Int) async throws -> SyncPullResponse {
        let snapshot = lock.withLock { state -> (failAll: Bool, next: Result<SyncPullResponse, SyncServerError>?) in
            state.pullRequests.append((since, limit))
            state.callOrder.append("pull")
            let next = state.pullResponses.isEmpty ? nil : state.pullResponses.removeFirst()
            return (state.failAll, next)
        }

        if snapshot.failAll { throw SyncServerError.transportUnavailable }
        if let next = snapshot.next { return try next.get() }
        return SyncPullResponse(records: [], nextSince: since, more: false,
                                schemaPolicy: SyncSchemaPolicy(minSupported: 1, current: 1))
    }

    func push(_ changes: [SyncPushChange]) async throws -> SyncPushResponse {
        struct Snapshot {
            var failAll: Bool
            var alwaysConflict: Bool
            var current: SyncPullRecord?
            var next: Result<SyncPushResponse, SyncServerError>?
        }
        let snapshot = lock.withLock { state -> Snapshot in
            state.pushBatches.append(changes)
            state.callOrder.append("push")
            let next = state.pushResponses.isEmpty ? nil : state.pushResponses.removeFirst()
            return Snapshot(failAll: state.failAll, alwaysConflict: state.alwaysConflict,
                            current: state.conflictCurrent, next: next)
        }

        if snapshot.failAll { throw SyncServerError.transportUnavailable }
        if snapshot.alwaysConflict, let current = snapshot.current {
            return SyncPushResponse(results: changes.map {
                SyncPushResult(id: $0.id, status: .conflict(current: current))
            })
        }
        if let next = snapshot.next { return try next.get() }
        var scn: Int64 = 1
        return SyncPushResponse(results: changes.map { change in
            defer { scn += 1 }
            return SyncPushResult(id: change.id, status: .accepted(newScn: scn, clamped: false))
        })
    }
}

// MARK: - Entity/record builders

private let testTimestamp = Date(timeIntervalSinceReferenceDate: 0)

func makeSyncVehicle(id: UUID = UUID.v7(), name: String = "Volvo V60",
                     tankCapacityL: Double? = 71, initialOdometer: Int? = 119_486,
                     homeCurrency: CurrencyCode = .eur,
                     units: Vehicle.Units = Vehicle.Units(distance: .km, volume: .l,
                                                          consumption: .lPer100, energy: .kWhPer100),
                     paceLimitKmPerDay: Double = 1500) -> Vehicle {
    Vehicle(
        id: id, createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: nil,
        name: name, make: "Volvo", model: "V60", year: 2021, plate: "ABC-123",
        powertrain: .hybrid, fuelKinds: [.petrol95], tankCapacityL: tankCapacityL,
        batteryCapacityKWh: nil, homeCurrency: homeCurrency, units: units, photo: nil,
        archived: false, paceLimitKmPerDay: paceLimitKmPerDay, initialOdometer: initialOdometer
    )
}

func makeSyncFillUp(id: UUID = UUID.v7(), vehicleId: UUID, date: Date = testTimestamp,
                    odometer: Int? = 82_400, note: String? = nil, volumeL: Double = 42.3,
                    isFull: Bool = true) -> FillUp {
    FillUp(
        id: id, createdAt: testTimestamp, updatedAt: testTimestamp, deletedAt: nil,
        vehicleId: vehicleId, date: date, odometer: odometer,
        money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
        note: note, attachments: [], provenance: .manual, conflict: .none, purchaseGroupId: nil,
        volumeL: volumeL, unitPrice: Decimal(string: "1.679")!, fuelKind: .petrol95,
        fuelGrade: nil, isFull: isFull, tankLevelAfterPct: 100, stationId: nil,
        crossCheck: .verified, extraction: nil
    )
}

/// Encodes a synced entity into a pull record (what the server would return).
func makePullRecord<E: SyncedEntity>(_ entity: E, scn: Int64, deleted: Bool? = nil) -> SyncPullRecord {
    let envelope = try! PayloadCodec.encode(entity)
    return SyncPullRecord(
        id: entity.id,
        entityType: E.entityType,
        schemaVersion: PayloadCodec.currentSchemaVersion,
        scn: scn,
        payload: envelope.payload,
        clientUpdatedAt: entity.updatedAt,
        deleted: deleted ?? (entity.deletedAt != nil)
    )
}

/// Builds a `SyncRecord` from a synced entity, with explicit per-field versions.
func makeSyncRecord<E: SyncedEntity>(_ entity: E, clientUpdatedAt: Date,
                                     fieldVersions: [String: Date]? = nil) -> SyncRecord {
    let envelope = try! PayloadCodec.encode(entity)
    return SyncRecord(
        id: entity.id,
        entityType: E.entityType,
        schemaVersion: PayloadCodec.currentSchemaVersion,
        payload: envelope.payload,
        clientUpdatedAt: clientUpdatedAt,
        deleted: entity.deletedAt != nil,
        fieldVersions: fieldVersions
    )
}

func makeSyncRepository() throws -> TankbookRepository {
    TankbookRepository(database: try TankbookDatabase.inMemory())
}

func makeSyncEngine(repository: TankbookRepository, transport: any SyncTransport,
                    cursor: SyncCursorStore = InMemorySyncCursorStore(),
                    memory: SyncPayloadMemory = InMemorySyncPayloadMemory(),
                    maxConflictRetries: Int = 3) -> SyncEngine {
    SyncEngine(repository: repository, transport: transport, cursorStore: cursor,
               payloadMemory: memory, maxConflictRetries: maxConflictRetries)
}

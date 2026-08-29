import Foundation
import Testing
@testable import TankbookCore

// PR.4: the persisted `SyncPayloadMemory` (docs/SYNC.md S9). The engine-level
// relaunch test lives in SyncScenarioTests; these pin the store itself - that a
// record is written, that it round-trips through a FRESH instance (the process
// boundary a relaunch is), and that reads are keyed by record id. The in-memory
// double stays a test double only; `InMemorySyncPayloadMemory` and
// `DatabaseSyncPayloadMemory` share the protocol, so these tests would pass
// against a shared instance without proving anything - every store here is a
// fresh instance over the same repository.

private let t0 = Date(timeIntervalSinceReferenceDate: 0)
private let policy = SyncSchemaPolicy(minSupported: 1, current: 1)

private let allAtT0: [String: Date] = [
    "name": t0, "tankCapacityL": t0, "initialOdometer": t0, "homeCurrency": t0,
    "units": t0, "paceLimitKmPerDay": t0, "archived": t0
]

@Test func payloadMemoryWritesSurviveToAFreshInstance() async throws {
    let repo = try makeSyncRepository()
    let vehicle = makeSyncVehicle()

    // One sync pulls the Vehicle; the engine's own write path records the
    // last-synced payload (docs/SYNC.md: after a successful pull).
    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(vehicle, scn: 1, fieldVersions: allAtT0)],
        nextSince: 1, more: false, schemaPolicy: policy))
    _ = await makeSyncEngine(repository: repo, transport: transport,
                             memory: DatabaseSyncPayloadMemory(repository: repo)).synchronize()

    // A FRESH store instance over the same repository - the relaunch. If
    // `recordSynced` wrote nothing, this reads nil and the field-level merge
    // degrades to "every field changed".
    let afterRelaunch = DatabaseSyncPayloadMemory(repository: repo)
    #expect(afterRelaunch.lastSyncedPayload(for: vehicle.id) != nil,
            "recordSynced must be persisted: a fresh engine reads the memory from the repository")
    #expect(afterRelaunch.lastSyncedPayload(for: UUID.v7()) == nil,
            "a record never synced has no memory")
}

@Test func payloadMemoryRoundTripsTheExactPayloadAcrossInstances() throws {
    let repo = try makeSyncRepository()
    let vehicle = makeSyncVehicle()
    let payload = try PayloadCodec.encode(vehicle).payload

    DatabaseSyncPayloadMemory(repository: repo).recordSynced(id: vehicle.id, payload: payload)

    let reread = DatabaseSyncPayloadMemory(repository: repo)
    #expect(reread.lastSyncedPayload(for: vehicle.id) == payload,
            "the persisted memory is the exact payload, not a re-encoding")
}

@Test func payloadMemoryIsKeyedByRecordIdAcrossFreshInstances() throws {
    let repo = try makeSyncRepository()
    let firstID = UUID.v7()
    let secondID = UUID.v7()
    let firstPayload = try PayloadCodec.encode(
        makeSyncVehicle(id: firstID, name: "Volvo")).payload
    let secondPayload = try PayloadCodec.encode(
        makeSyncVehicle(id: secondID, name: "V60", tankCapacityL: 60)).payload
    #expect(firstPayload != secondPayload, "the two payloads must differ for the keying to be asserted")

    let writer = DatabaseSyncPayloadMemory(repository: repo)
    writer.recordSynced(id: firstID, payload: firstPayload)
    writer.recordSynced(id: secondID, payload: secondPayload)

    // Reading back through a fresh instance: each id gets its OWN payload. A
    // store that ignored the key (returning either the first or the last write
    // for every id) must fail here.
    let reader = DatabaseSyncPayloadMemory(repository: repo)
    #expect(reader.lastSyncedPayload(for: firstID) == firstPayload)
    #expect(reader.lastSyncedPayload(for: secondID) == secondPayload)
}

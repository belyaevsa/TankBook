import Foundation
import Testing
@testable import TankbookCore

// RV.14: a device must not push its own records back, forever. The defect was
// that `RecordMerge.mergeVehicle` reported `.fieldMerge` for byte-identical
// live vehicles, and `applyPull` re-stored that merge as `.dirty`, so every
// pull produced a push that produced another pull. These tests pin the fix:
// the merge reports whether it changed anything (at the decoded level, never
// raw payload bytes), and the engine only dirties a genuinely new write.

private let loopT0 = Date(timeIntervalSinceReferenceDate: 0)
private let loopPolicy = SyncSchemaPolicy(minSupported: 1, current: 1)

private func decodeVehicle(_ payload: JSONValue) throws -> Vehicle {
    try PayloadCodec.decode(
        PayloadEnvelope(entityType: Vehicle.entityType,
                        schemaVersion: PayloadCodec.currentSchemaVersion,
                        payload: payload),
        as: Vehicle.self
    ).entity
}

/// All seven mergeable `Vehicle` fields stamped at `t0` - the baseline version
/// map the RV.14 tests share.
private func loopT0Versions() -> [String: Date] {
    ["name": loopT0, "tankCapacityL": loopT0, "initialOdometer": loopT0,
     "homeCurrency": loopT0, "units": loopT0, "paceLimitKmPerDay": loopT0, "archived": loopT0]
}

@Test func rv14TwoIdenticalLiveVehiclesAreNotAFieldMerge() throws {
    // L1: the merge must report "nothing changed", never a field merge that the
    // engine would re-store as a fresh dirty write.
    let id = UUID.v7()
    let vehicle = makeSyncVehicle(id: id)
    let record = makeSyncRecord(vehicle, clientUpdatedAt: loopT0, fieldVersions: loopT0Versions())

    let result = RecordMerge.merge(local: record, remote: record)

    #expect(result.winner == .remote, "identical records are not a field merge")
    #expect(result.keep == record, "the kept record is unchanged, not a re-encoded new write")
    #expect(result.loser == record)
}

@Test func rv14PushedVehiclePulledBackUnchangedDoesNotPushAgain() async throws {
    // L2/L3: one record pushed, then pulled back byte-for-byte, must settle to
    // `.synced` and push no second time. A single pull would not show the loop.
    let repo = try makeSyncRepository()
    let id = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: id))

    let transport = SyncTransportDouble()
    let engine = makeSyncEngine(repository: repo, transport: transport)

    // Cycle 1: the device pushes its vehicle; the server accepts it.
    let outcome1 = await engine.synchronize()
    #expect(outcome1.pushed == 1, "the initial push is the only legitimate write")
    #expect(transport.recordedPushBatches.count == 1)

    // The server echoes exactly what was pushed back at the assigned SCN.
    let pushed = transport.recordedPushBatches[0][0]
    transport.enqueuePull(SyncPullResponse(
        records: [SyncPullRecord(id: pushed.id, entityType: pushed.entityType,
                                 schemaVersion: pushed.schemaVersion, scn: 1,
                                 payload: pushed.payload, clientUpdatedAt: pushed.clientUpdatedAt,
                                 deleted: pushed.deleted)],
        nextSince: 1, more: false, schemaPolicy: loopPolicy))

    // Cycle 2: pulling the unchanged record back must NOT push a second time.
    let outcome2 = await engine.synchronize()
    #expect(outcome2.pushed == 0, "an unchanged vehicle must not be re-pushed (RV.14)")
    #expect(transport.recordedPushBatches.count == 1, "no second push batch")
    #expect(try repo.fetchDirtyRows().isEmpty, "the vehicle settles synced, not dirty")

    guard case .synced = try repo.localSyncRecord(id: id, entityType: Vehicle.entityType)?.syncState else {
        Issue.record("the vehicle must settle to .synced")
        return
    }
}

@Test func rv14ALocalOnlyVehicleEditStillPushes() async throws {
    // The DANGER case: a local edit where the remote is only stale must still
    // push. merged == local here, and the answer must be "already dirty, push",
    // never "record the SCN and swallow the edit".
    let repo = try makeSyncRepository()
    let id = UUID.v7()
    let friday = loopT0.addingTimeInterval(8 * 86_400)
    let baseline = makeSyncVehicle(id: id, name: "Volvo", tankCapacityL: 71)

    let transport1 = SyncTransportDouble()
    transport1.enqueuePull(SyncPullResponse(
        records: [makePullRecord(baseline, scn: 1, fieldVersions: loopT0Versions())],
        nextSince: 1, more: false, schemaPolicy: loopPolicy))
    _ = await makeSyncEngine(repository: repo, transport: transport1,
                             memory: DatabaseSyncPayloadMemory(repository: repo)).synchronize()

    var edited = baseline
    edited.name = "V60"
    edited.updatedAt = friday
    try repo.upsertVehicle(edited)

    let transport2 = SyncTransportDouble()
    transport2.enqueuePull(SyncPullResponse(
        records: [makePullRecord(baseline, scn: 5, fieldVersions: loopT0Versions())],
        nextSince: 5, more: false, schemaPolicy: loopPolicy))
    let outcome = await makeSyncEngine(repository: repo, transport: transport2,
                                       memory: DatabaseSyncPayloadMemory(repository: repo)).synchronize()

    #expect(try repo.vehicle(id: id)?.name == "V60", "the local rename must survive")
    #expect(outcome.pushed == 1, "a local edit must still push, never be swallowed")
    #expect(transport2.recordedPushBatches.count == 1)
}

@Test func rv14FieldMergeStillPushesBothSurvivingChanges() async throws {
    // S9 across the engine: two devices, each a different field, both changes
    // survive AND the merged record is a genuine new write that pushes.
    let repo = try makeSyncRepository()
    let id = UUID.v7()
    let monday = loopT0.addingTimeInterval(4 * 86_400)
    let friday = loopT0.addingTimeInterval(8 * 86_400)
    let baseline = makeSyncVehicle(id: id, name: "Volvo", tankCapacityL: 71)

    let transport1 = SyncTransportDouble()
    transport1.enqueuePull(SyncPullResponse(
        records: [makePullRecord(baseline, scn: 1, fieldVersions: loopT0Versions())],
        nextSince: 1, more: false, schemaPolicy: loopPolicy))
    _ = await makeSyncEngine(repository: repo, transport: transport1,
                             memory: DatabaseSyncPayloadMemory(repository: repo)).synchronize()

    var edited = baseline
    edited.name = "V60"
    edited.updatedAt = friday
    try repo.upsertVehicle(edited)

    var remote = makeSyncVehicle(id: id, name: "Volvo", tankCapacityL: 60)
    remote.updatedAt = monday
    var remoteVersions = loopT0Versions()
    remoteVersions["tankCapacityL"] = monday

    let transport2 = SyncTransportDouble()
    transport2.enqueuePull(SyncPullResponse(
        records: [makePullRecord(remote, scn: 10, fieldVersions: remoteVersions)],
        nextSince: 10, more: false, schemaPolicy: loopPolicy))
    let outcome = await makeSyncEngine(repository: repo, transport: transport2,
                                       memory: DatabaseSyncPayloadMemory(repository: repo)).synchronize()

    let merged = try repo.vehicle(id: id)
    #expect(merged?.name == "V60", "the rename must survive")
    #expect(merged?.tankCapacityL == 60, "the correction must survive (S9)")
    #expect(outcome.pushed == 1, "a genuine field merge is still a new write that pushes")
    #expect(transport2.recordedPushBatches.count == 1)

    let pushedVehicle = try decodeVehicle(transport2.recordedPushBatches[0][0].payload)
    #expect(pushedVehicle.name == "V60", "the push carries both changes")
    #expect(pushedVehicle.tankCapacityL == 60)
}

@Test func rv14EmptyPayloadMemoryStillSettlesWithoutAPushLoop() async throws {
    // A fresh engine over an already-synced vehicle: the in-memory payload store
    // is empty (the state after a relaunch), so `compute` stamps every field
    // changed at the write time. That must still settle, not re-push forever.
    let repo = try makeSyncRepository()
    let id = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: id), syncState: .synced(scn: 1))

    // Server field versions a day older than the freshly-stamped local versions:
    // the empty-memory device claims every field changed, which drives the
    // merged == local branch - and must not turn into a push.
    let older = loopT0.addingTimeInterval(-86_400)
    var serverVersions = loopT0Versions()
    for key in serverVersions.keys { serverVersions[key] = older }

    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(makeSyncVehicle(id: id), scn: 2, fieldVersions: serverVersions)],
        nextSince: 2, more: false, schemaPolicy: loopPolicy))
    let outcome = await makeSyncEngine(repository: repo, transport: transport,
                                       memory: InMemorySyncPayloadMemory()).synchronize()

    #expect(outcome.pushed == 0, "nothing changed locally, so nothing should push")
    #expect(transport.recordedPushBatches.isEmpty)
    #expect(try repo.fetchDirtyRows().isEmpty, "the vehicle settles, not stuck dirty")
}

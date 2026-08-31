import Foundation
import Testing
@testable import TankbookCore

// PR.14: the "Changed by sync" row reads the REAL `syncOverwrite` log, not a
// fixture. These are the L1/L3 guarantees behind it (docs/TESTING.md): the
// overwrite is queried by record id with its device name, "Restore my version"
// round-trips the losing version, and the restored value survives a subsequent
// sync (hard rule 13 - once the user chooses, no later merge overwrites it).

private let policy = SyncSchemaPolicy(minSupported: 1, current: 1)
private let t0 = Date(timeIntervalSinceReferenceDate: 0)

// MARK: - The overwrite log stores and queries the device name

@Test func overwriteIsStoredAndQueriedByRecordIdWithItsDevice() throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))
    let fillUpId = UUID.v7()
    try repo.upsertFillUp(makeSyncFillUp(id: fillUpId, vehicleId: vehicleId),
                          syncState: .synced(scn: 2))

    let losing = makeSyncRecord(makeSyncFillUp(id: fillUpId, vehicleId: vehicleId),
                                clientUpdatedAt: t0.addingTimeInterval(1))
    let replacedAt = t0.addingTimeInterval(10)
    try repo.recordSyncOverwrite(recordId: fillUpId, losingRecord: losing,
                                 deviceName: "iPad", at: replacedAt)

    let overwrite = try repo.syncOverwrite(for: fillUpId)
    #expect(overwrite != nil, "the overwrite is queryable by its record id")
    #expect(overwrite?.recordId == fillUpId)
    #expect(overwrite?.deviceName == "iPad", "the device that overwrote is stored, not invented")
    #expect(overwrite?.replacedAt == replacedAt, "the overwrite date is stored, not invented")
}

@Test func queryReturnsTheNewestOverwriteForARecord() throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))
    let fillUpId = UUID.v7()
    try repo.upsertFillUp(makeSyncFillUp(id: fillUpId, vehicleId: vehicleId),
                          syncState: .synced(scn: 2))

    try repo.recordSyncOverwrite(
        recordId: fillUpId,
        losingRecord: makeSyncRecord(makeSyncFillUp(id: fillUpId, vehicleId: vehicleId),
                                     clientUpdatedAt: t0),
        deviceName: "iPhone", at: t0)
    try repo.recordSyncOverwrite(
        recordId: fillUpId,
        losingRecord: makeSyncRecord(makeSyncFillUp(id: fillUpId, vehicleId: vehicleId),
                                     clientUpdatedAt: t0.addingTimeInterval(1)),
        deviceName: "iPad", at: t0.addingTimeInterval(1))

    let overwrite = try repo.syncOverwrite(for: fillUpId)
    #expect(overwrite?.deviceName == "iPad", "the newest overwrite wins the query")
}

// MARK: - "Restore my version" round-trips

@Test func restoreSyncOverwriteRoundTripsTheUsersVersion() throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))
    let fillUpId = UUID.v7()

    // The synced version (what the other device wrote): odometer 82 400.
    try repo.upsertFillUp(makeSyncFillUp(id: fillUpId, vehicleId: vehicleId, odometer: 82_400),
                          syncState: .synced(scn: 2))
    // The user's losing version: odometer 83 000.
    let userVersion = makeSyncFillUp(id: fillUpId, vehicleId: vehicleId, odometer: 83_000)
    try repo.recordSyncOverwrite(recordId: fillUpId,
                                 losingRecord: makeSyncRecord(userVersion, clientUpdatedAt: t0),
                                 deviceName: "iPad", at: t0)

    #expect(try repo.restoreSyncOverwrite(recordId: fillUpId), "a recorded overwrite restores")

    let fills = try repo.liveFillUps(forVehicle: vehicleId)
    #expect(fills.count == 1)
    #expect(fills[0].odometer == 83_000, "the user's value actually returns")
    #expect(try repo.syncOverwrite(for: fillUpId) == nil, "the log row is consumed by the restore")
    #expect(try repo.fetchDirtyRows().contains { $0.id == fillUpId },
            "the restore is a fresh local edit queued to push")
}

@Test func restoreOfAnUnknownRecordReturnsFalse() throws {
    let repo = try makeSyncRepository()
    #expect(try repo.restoreSyncOverwrite(recordId: UUID.v7()) == false)
}

// MARK: - The restored value survives a subsequent sync

@Test func restoredVersionSurvivesASubsequentSync() async throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))
    let fillUpId = UUID.v7()

    // The iPad's version that overwrote: odometer 82 100.
    let remote = makeSyncFillUp(id: fillUpId, vehicleId: vehicleId, odometer: 82_100, note: "Shell")
    try repo.upsertFillUp(remote, syncState: .synced(scn: 2))
    // The user's losing version: odometer 83 000.
    try repo.recordSyncOverwrite(
        recordId: fillUpId,
        losingRecord: makeSyncRecord(makeSyncFillUp(id: fillUpId, vehicleId: vehicleId, odometer: 83_000),
                                     clientUpdatedAt: t0),
        deviceName: "iPad", at: t0)

    #expect(try repo.restoreSyncOverwrite(recordId: fillUpId))

    // A later sync pulls the iPad's older version again. The restored value is
    // newer (fresh `updatedAt`), so LWW must keep it.
    let transport = SyncTransportDouble()
    var olderRemote = remote
    olderRemote.updatedAt = t0.addingTimeInterval(2)
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(olderRemote, scn: 3)], nextSince: 3, more: false, schemaPolicy: policy))
    _ = await makeSyncEngine(repository: repo, transport: transport).synchronize()

    let fills = try repo.liveFillUps(forVehicle: vehicleId)
    #expect(fills[0].odometer == 83_000, "the restored value survives the next sync (hard rule 13)")
}

// MARK: - The wire carries the overwriting device's name into the log

@Test func aPullThatOverwritesRecordsTheRemoteDeviceName() async throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))
    let fillUpId = UUID.v7()

    // The iPhone's local edit (odometer 82 400), dirty - it will lose.
    var iphoneEdit = makeSyncFillUp(id: fillUpId, vehicleId: vehicleId, odometer: 82_400)
    iphoneEdit.updatedAt = t0.addingTimeInterval(1)
    try repo.upsertFillUp(iphoneEdit, syncState: .dirty)

    // The iPad's edit (newer), pulled with its origin device name.
    var ipadEdit = makeSyncFillUp(id: fillUpId, vehicleId: vehicleId, odometer: 82_100, note: "Shell")
    ipadEdit.updatedAt = t0.addingTimeInterval(2)
    var pull = makePullRecord(ipadEdit, scn: 2)
    pull.originDeviceName = "iPad"

    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [pull], nextSince: 2, more: false, schemaPolicy: policy))
    _ = await makeSyncEngine(repository: repo, transport: transport).synchronize()

    let overwrites = try repo.syncOverwrittenEntries()
    #expect(overwrites.count == 1)
    #expect(overwrites[0].deviceName == "iPad",
            "the losing device learns which device overwrote it from the wire")
}

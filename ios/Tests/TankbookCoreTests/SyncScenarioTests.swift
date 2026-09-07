import Foundation
import Testing
@testable import TankbookCore

// The L3 sync-scenario suite (docs/TESTING.md L3, docs/SYNC.md S1-S9): one
// deterministic test per scenario against the pure merge and the in-memory
// transport double - never `URLSession`, never a live server.

private let policy = SyncSchemaPolicy(minSupported: 1, current: 1)
private let t0 = Date(timeIntervalSinceReferenceDate: 0)

private func decodeVehicle(_ payload: JSONValue) throws -> Vehicle {
    try PayloadCodec.decode(
        PayloadEnvelope(entityType: Vehicle.entityType,
                        schemaVersion: PayloadCodec.currentSchemaVersion,
                        payload: payload),
        as: Vehicle.self
    ).entity
}

private func decodeFillUp(_ payload: JSONValue) throws -> FillUp {
    try PayloadCodec.decode(
        PayloadEnvelope(entityType: FillUp.entityType,
                        schemaVersion: PayloadCodec.currentSchemaVersion,
                        payload: payload),
        as: FillUp.self
    ).entity
}

// MARK: - S9 (the load-bearing invariant)

@Test func s9AStaleDeviceWritingOneFieldDoesNotRevertAnother() throws {
    let monday = t0.addingTimeInterval(4 * 86_400)
    let friday = t0.addingTimeInterval(8 * 86_400)
    let id = UUID.v7()

    // The fresh device (iPhone) corrected all five user-decision fields Monday.
    let fresh = makeSyncVehicle(
        id: id, name: "Volvo", tankCapacityL: 60, initialOdometer: 50_000,
        homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
        paceLimitKmPerDay: 2000
    )
    // The stale device (iPad) renamed the car Friday; every other field is the
    // stale value it still held from t0.
    let stale = makeSyncVehicle(
        id: id, name: "V60", tankCapacityL: 71, initialOdometer: 49_000,
        homeCurrency: .rub,
        units: Vehicle.Units(distance: .mi, volume: .galUS, consumption: .mpgUS, energy: .miPerKWh),
        paceLimitKmPerDay: 1500
    )

    let freshRecord = makeSyncRecord(fresh, clientUpdatedAt: monday, fieldVersions: [
        "name": t0, "tankCapacityL": monday, "initialOdometer": monday,
        "homeCurrency": monday, "units": monday, "paceLimitKmPerDay": monday,
    ])
    let staleRecord = makeSyncRecord(stale, clientUpdatedAt: friday, fieldVersions: [
        "name": friday, "tankCapacityL": t0, "initialOdometer": t0,
        "homeCurrency": t0, "units": t0, "paceLimitKmPerDay": t0,
    ])

    let result = RecordMerge.merge(local: staleRecord, remote: freshRecord)
    let merged = try decodeVehicle(result.keep.payload)

    #expect(merged.name == "V60", "the stale device's newer name must survive")
    #expect(merged.tankCapacityL == 60, "the fresh device's correction must survive (S9)")
    #expect(merged.initialOdometer == 50_000)
    #expect(merged.homeCurrency == .eur)
    #expect(merged.units.distance == .km)
    #expect(merged.units.volume == .l)
    #expect(merged.paceLimitKmPerDay == 2000)
    #expect(result.winner == .fieldMerge)
    #expect(result.loser == nil, "a field merge loses nothing (docs/SYNC.md S9)")
}

// MARK: - S9 across a relaunch (PR.4)

/// PR.4: the payload memory is persisted, so a FRESH engine over the same
/// repository still knows which fields this device changed. The pure merge test
/// above and every engine test hold one memory for their whole life and cannot
/// see the bug: the in-memory double dies with the process, so after a relaunch
/// the first sync diffs against nothing and claims EVERY field changed - a stale
/// device then overwrites a field another device edited in between (hard rule
/// 13). This test rebuilds the second engine over the same repository, exactly
/// the process boundary a relaunch is.
@Test func s9AFreshEngineOverTheSameRepositoryStillMergesOnlyTheChangedField() async throws {
    let monday = t0.addingTimeInterval(4 * 86_400)
    let friday = t0.addingTimeInterval(8 * 86_400)
    let id = UUID.v7()
    let allAtT0: [String: Date] = [
        "name": t0, "tankCapacityL": t0, "initialOdometer": t0, "homeCurrency": t0,
        "units": t0, "paceLimitKmPerDay": t0, "archived": t0,
    ]

    // Yesterday's sync: this device pulled and pushed the baseline, so the
    // persisted memory holds it as the last-synced payload.
    let baseline = makeSyncVehicle(id: id, name: "Volvo", tankCapacityL: 71,
                                   initialOdometer: 49_000, homeCurrency: .eur,
                                   paceLimitKmPerDay: 2000)
    let repo = try makeSyncRepository()
    let transport1 = SyncTransportDouble()
    transport1.enqueuePull(SyncPullResponse(
        records: [makePullRecord(baseline, scn: 5, fieldVersions: allAtT0)],
        nextSince: 5, more: false, schemaPolicy: policy))
    _ = await makeSyncEngine(repository: repo, transport: transport1,
                             memory: DatabaseSyncPayloadMemory(repository: repo)).synchronize()

    // This device (stale since yesterday) renames the car Friday; every other
    // field is still the baseline value.
    var edited = baseline
    edited.name = "V60"
    edited.updatedAt = friday
    try repo.upsertVehicle(edited)

    // The fresh device corrected tankCapacityL and initialOdometer Monday and
    // pushed; this device relaunched and now pulls it with a FRESH engine over
    // the same repository.
    let remote = makeSyncVehicle(id: id, name: "Volvo", tankCapacityL: 60,
                                 initialOdometer: 50_000, homeCurrency: .eur,
                                 paceLimitKmPerDay: 2000)
    let remoteVersions: [String: Date] = [
        "name": t0, "tankCapacityL": monday, "initialOdometer": monday,
        "homeCurrency": t0, "units": t0, "paceLimitKmPerDay": t0, "archived": t0,
    ]
    let transport2 = SyncTransportDouble()
    transport2.enqueuePull(SyncPullResponse(
        records: [makePullRecord(remote, scn: 10, fieldVersions: remoteVersions)],
        nextSince: 10, more: false, schemaPolicy: policy))
    _ = await makeSyncEngine(repository: repo, transport: transport2,
                             memory: DatabaseSyncPayloadMemory(repository: repo)).synchronize()

    let merged = try repo.vehicle(id: id)
    #expect(merged?.name == "V60", "the stale device's newer name must survive")
    #expect(merged?.tankCapacityL == 60,
            "the fresh device's correction must survive the relaunch (S9)")
    #expect(merged?.initialOdometer == 50_000)
    #expect(merged?.homeCurrency == .eur)
}

// MARK: - S1

@Test func s1RecordLevelLWWOnAnEntryLosesTheOlderEditToTheUndoLog() async throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))

    let fillUpId = UUID.v7()
    // iPhone's local edit: odometer changed at 14:02, still dirty.
    var iphoneEdit = makeSyncFillUp(id: fillUpId, vehicleId: vehicleId, odometer: 82_400)
    iphoneEdit.updatedAt = t0.addingTimeInterval(1)
    try repo.upsertFillUp(iphoneEdit, syncState: .dirty)

    // iPad's edit: the note changed at 14:05 (newer) - pulled.
    var ipadEdit = makeSyncFillUp(id: fillUpId, vehicleId: vehicleId, odometer: 82_100, note: "Shell, A4 exit")
    ipadEdit.updatedAt = t0.addingTimeInterval(2)

    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(ipadEdit, scn: 2)], nextSince: 2, more: false, schemaPolicy: policy))

    let engine = makeSyncEngine(repository: repo, transport: transport)
    _ = await engine.synchronize()

    let fills = try repo.liveFillUps(forVehicle: vehicleId)
    #expect(fills.count == 1)
    #expect(fills[0].odometer == 82_100, "the iPhone's odometer edit is lost (documented outcome)")
    #expect(fills[0].note == "Shell, A4 exit")

    let overwrites = try repo.syncOverwrittenEntries()
    #expect(overwrites.count == 1, "the losing version lands in the local undo log")
    let losing = try decodeFillUp(overwrites[0].losingPayload)
    #expect(losing.odometer == 82_400, "the losing version is the iPhone's odometer edit")
}

// MARK: - S4

@Test func s4EditNewerThanDeleteResurrectsWithTheEdit() async throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))
    let fillUpId = UUID.v7()

    // iPhone's edit at 14:10 (newer than the delete), dirty.
    var edit = makeSyncFillUp(id: fillUpId, vehicleId: vehicleId, odometer: 82_400, note: "corrected price")
    edit.updatedAt = t0.addingTimeInterval(2)
    try repo.upsertFillUp(edit, syncState: .dirty)

    // iPad's delete at 14:05 (older): a tombstone.
    var deleted = makeSyncFillUp(id: fillUpId, vehicleId: vehicleId, odometer: 82_400)
    deleted.updatedAt = t0.addingTimeInterval(1)
    deleted.deletedAt = t0.addingTimeInterval(1)

    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(deleted, scn: 2, deleted: true)], nextSince: 2, more: false, schemaPolicy: policy))

    let engine = makeSyncEngine(repository: repo, transport: transport)
    _ = await engine.synchronize()

    let fills = try repo.liveFillUps(forVehicle: vehicleId)
    #expect(fills.count == 1, "the record resurrects with the edit")
    #expect(fills[0].note == "corrected price")
    #expect(try repo.syncOverwrittenEntries().isEmpty, "a lost delete is not an overwritten edit")
}

@Test func s4DeleteNewerThanEditStaysDeletedAndLogsTheEdit() async throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))
    let fillUpId = UUID.v7()

    // iPhone's edit at 14:10 (older than the delete), dirty.
    var edit = makeSyncFillUp(id: fillUpId, vehicleId: vehicleId, odometer: 82_400, note: "corrected price")
    edit.updatedAt = t0.addingTimeInterval(1)
    try repo.upsertFillUp(edit, syncState: .dirty)

    // iPad's delete at 14:15 (newer): a tombstone.
    var deleted = makeSyncFillUp(id: fillUpId, vehicleId: vehicleId, odometer: 82_400)
    deleted.updatedAt = t0.addingTimeInterval(2)
    deleted.deletedAt = t0.addingTimeInterval(2)

    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(deleted, scn: 2, deleted: true)], nextSince: 2, more: false, schemaPolicy: policy))

    let engine = makeSyncEngine(repository: repo, transport: transport)
    _ = await engine.synchronize()

    #expect(try repo.liveFillUps(forVehicle: vehicleId).isEmpty, "it stays deleted")
    let overwrites = try repo.syncOverwrittenEntries()
    #expect(overwrites.count == 1, "the iPhone's edit lands in the undo log")
    let losing = try decodeFillUp(overwrites[0].losingPayload)
    #expect(losing.note == "corrected price")
}

// MARK: - S6

@Test func s6ConflictReMergeIsAutomaticAndBounded() async throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))

    let fillUpId = UUID.v7()
    var fillUp = makeSyncFillUp(id: fillUpId, vehicleId: vehicleId)
    fillUp.updatedAt = t0.addingTimeInterval(1)
    try repo.upsertFillUp(fillUp, syncState: .synced(scn: 5))

    // A local edit (dirty) preserves its base SCN of 5. It is the NEWEST write:
    // the other device pushed first (server current at scn 7), so the stale
    // baseScn collides and the client must re-merge and re-push.
    var edited = fillUp
    edited.note = "edited offline"
    edited.updatedAt = t0.addingTimeInterval(3)
    try repo.upsertFillUp(edited, syncState: .dirty)

    // Another device's write, older in client-clock but already on the server.
    var current = makeSyncFillUp(id: fillUpId, vehicleId: vehicleId, note: "iPad's edit")
    current.updatedAt = t0.addingTimeInterval(2)

    let transport = SyncTransportDouble()
    transport.setAlwaysConflict(current: makePullRecord(current, scn: 7))
    let engine = makeSyncEngine(repository: repo, transport: transport, maxConflictRetries: 3)

    _ = await engine.synchronize()

    // The client re-merged and re-pushed, automatically, then STOPPED at the
    // bound: 1 initial push + maxConflictRetries re-pushes.
    #expect(transport.recordedPushBatches.count == 4, "the retry count must equal 1 + maxConflictRetries")
    #expect(transport.recordedPushBatches[0][0].baseScn == 5, "the initial push names its real base")
    #expect(transport.recordedPushBatches[1][0].baseScn == 7, "the re-push names the server's current SCN")
    #expect(try repo.fetchDirtyRows().count == 1, "the row is left dirty, not looping forever")
}

// MARK: - S3

@Test func s3OutOfOrderOdometersAreFlaggedAndExcluded() async throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))

    let saturday = t0
    let sunday = t0.addingTimeInterval(86_400)
    let monday = t0.addingTimeInterval(2 * 86_400)

    // Driver A logged Saturday (odo 119 486) and a later Monday fill (120 000).
    let a = makeSyncFillUp(id: UUID.v7(), vehicleId: vehicleId, date: saturday, odometer: 119_486)
    let c = makeSyncFillUp(id: UUID.v7(), vehicleId: vehicleId, date: monday, odometer: 120_000)
    try repo.upsertFillUp(a, syncState: .synced(scn: 2))
    try repo.upsertFillUp(c, syncState: .synced(scn: 3))

    // Driver B, offline in the countryside, logged Sunday at a LOWER odo - pulled.
    let b = makeSyncFillUp(id: UUID.v7(), vehicleId: vehicleId, date: sunday, odometer: 119_210)
    var bPull = b
    bPull.updatedAt = sunday

    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(bPull, scn: 4)], nextSince: 4, more: false, schemaPolicy: policy))

    let engine = makeSyncEngine(repository: repo, transport: transport)
    let outcome = await engine.synchronize()

    let fills = try repo.liveFillUps(forVehicle: vehicleId)
    let storedB = fills.first { $0.id == b.id }
    #expect(storedB != nil, "both records are accepted - no transport conflict")
    if case .flagged(let kind, _) = storedB?.conflict {
        #expect(kind == .order, "the out-of-order entry carries the amber ConflictState")
    } else {
        Issue.record("B must be flagged after merge")
    }

    // Its segment is excluded from consumption (docs/SYNC.md S3).
    let segments = ConsumptionEngine.segments(for: fills, tankCapacityL: nil)
    #expect(segments.allSatisfy { $0.openingFillID != b.id && $0.closingFillID != b.id },
            "the flagged entry's segment is excluded from the headline")
    #expect(outcome.flaggedEntries >= 1)
}

// MARK: - S7

@Test func s7OutageNeverGatesWritesAndTheQueueDrainsPullBeforePush() async throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))

    let transport = SyncTransportDouble()
    transport.setFailAll(true)
    let engine = makeSyncEngine(repository: repo, transport: transport)

    // Local writes land while the backend is down.
    let f1 = makeSyncFillUp(id: UUID.v7(), vehicleId: vehicleId, date: t0, odometer: 1000)
    let f2 = makeSyncFillUp(id: UUID.v7(), vehicleId: vehicleId, date: t0.addingTimeInterval(86_400), odometer: 2000)
    try repo.upsertFillUp(f1)
    try repo.upsertFillUp(f2)

    let outcome1 = await engine.synchronize()
    #expect(outcome1.offline)
    #expect(try repo.liveFillUps(forVehicle: vehicleId).count == 2, "nothing is sync-gated")
    #expect(try repo.fetchDirtyRows().count == 2, "rows remain queued, not stuck in pushing")

    // Recovery: the queue drains, pull before push.
    transport.setFailAll(false)
    let outcome2 = await engine.synchronize()
    #expect(!outcome2.offline)
    #expect(try repo.fetchDirtyRows().isEmpty, "the queue drained on recovery")
    #expect(!transport.recordedCallOrder.isEmpty)
    #expect(transport.recordedCallOrder.first == "pull", "the cycle pulls before it pushes")
    #expect(transport.recordedCallOrder.contains("push"), "the dirty rows are pushed after the pull")
}

// MARK: - Cursor safety

@Test func cursorIsPersistedOnlyAfterThePageIsAppliedAndResumeDoesNotSkip() async throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))

    let f1 = makeSyncFillUp(id: UUID.v7(), vehicleId: vehicleId, date: t0, odometer: 1000)
    let f2 = makeSyncFillUp(id: UUID.v7(), vehicleId: vehicleId, date: t0.addingTimeInterval(86_400), odometer: 2000)
    let cursor = InMemorySyncCursorStore()

    // First run: page 1 applied, then the transport fails before page 2.
    let transport1 = SyncTransportDouble()
    transport1.enqueuePull(SyncPullResponse(
        records: [makePullRecord(f1, scn: 10)], nextSince: 10, more: true, schemaPolicy: policy))
    transport1.enqueuePullError(.offline)

    let engine1 = makeSyncEngine(repository: repo, transport: transport1, cursor: cursor)
    let outcome1 = await engine1.synchronize()
    #expect(outcome1.offline)
    #expect(try cursor.load() == 10, "the cursor is persisted only after the page is applied")
    #expect(try repo.liveFillUps(forVehicle: vehicleId).count == 1)

    // Second run (a fresh client): resume from the persisted cursor.
    let transport2 = SyncTransportDouble()
    transport2.enqueuePull(SyncPullResponse(
        records: [makePullRecord(f2, scn: 20)], nextSince: 20, more: false, schemaPolicy: policy))
    let engine2 = makeSyncEngine(repository: repo, transport: transport2, cursor: cursor)
    _ = await engine2.synchronize()

    #expect(try repo.liveFillUps(forVehicle: vehicleId).count == 2, "no record is skipped")
    #expect(transport2.recordedPullRequests.first?.since == 10, "resumes from the persisted cursor")
}

// MARK: - Batch cap

/// The 200-record bound in isolation. Since RV.97 a push batch is bounded by
/// records AND by encoded bytes, and ~700 B of fillUp payload times 250 already
/// exceeds the 64 KB byte cap - so this fixture widens the byte cap past where
/// it can bind and pins the record bound alone. The byte bound has its own
/// suite (`SyncPushByteBoundTests`).
@Test func batchCapSplitsTwoHundredFiftyDirtyRowsIntoTwoBatches() async throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))
    for index in 0 ..< 250 {
        let fill = makeSyncFillUp(id: UUID.v7(), vehicleId: vehicleId,
                                  date: t0.addingTimeInterval(Double(index) * 86_400),
                                  odometer: 1000 + index)
        try repo.upsertFillUp(fill)
    }

    let transport = SyncTransportDouble()
    let engine = SyncEngine(repository: repo, transport: transport,
                            cursorStore: InMemorySyncCursorStore(),
                            maxBatchBytes: 16 * 1024 * 1024)
    _ = await engine.synchronize()

    #expect(transport.recordedPushBatches.count == 2, "250 dirty rows produce two batches, not one")
    #expect(transport.recordedPushBatches[0].count == 200)
    #expect(transport.recordedPushBatches[1].count == 50)
}

// MARK: - S2

@Test func s2DuplicateFillUpsBothSyncAndTheHeuristicFlagsThem() async throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))

    let f1 = makeSyncFillUp(id: UUID.v7(), vehicleId: vehicleId, date: t0, volumeL: 42.3)
    let f2 = makeSyncFillUp(id: UUID.v7(), vehicleId: vehicleId, date: t0.addingTimeInterval(60), volumeL: 42.3)

    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(f1, scn: 2), makePullRecord(f2, scn: 3)],
        nextSince: 3, more: false, schemaPolicy: policy))

    let engine = makeSyncEngine(repository: repo, transport: transport)
    _ = await engine.synchronize()

    let fills = try repo.liveFillUps(forVehicle: vehicleId)
    #expect(fills.count == 2, "both records sync everywhere - different ids, no transport conflict")
    let pairs = DuplicateDetector.pairs(in: fills)
    #expect(pairs.count == 1, "the heuristic flags the pair, which counts once until resolved")
}

// MARK: - S5

@Test func s5EntryArrivingForADeletedVehicleResurrectsItAsArchived() async throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))

    // Device A deletes the Volvo.
    try repo.softDeleteVehicle(id: vehicleId)

    // Device B, offline, logged one last fill-up to it - it arrives via pull.
    let fillUp = makeSyncFillUp(id: UUID.v7(), vehicleId: vehicleId,
                                date: t0.addingTimeInterval(86_400), odometer: 121_000)

    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(fillUp, scn: 2)], nextSince: 2, more: false, schemaPolicy: policy))

    let engine = makeSyncEngine(repository: repo, transport: transport)
    _ = await engine.synchronize()

    let vehicle = try repo.vehicle(id: vehicleId)
    #expect(vehicle?.deletedAt == nil, "the vehicle resurrects")
    #expect(vehicle?.archived == true, "...but as ARCHIVED, never active")
    #expect(try repo.liveFillUps(forVehicle: vehicleId).count == 1, "the entry is attached")
}

// MARK: - S5a (RV.101)

/// S5a: the deletion cascade is itself a stream of tombstones. A co-tombstoned
/// entry that arrives after the vehicle tombstone must NOT resurrect the car it
/// was deleted with - `deletedAt` alone is not the assertion, because a dirty
/// tombstone still echoes. The row must be tombstoned AND not dirty
/// (docs/SYNC.md S5a).
@Test func s5aDeletionCascadeDoesNotResurrectTheCarItJustTombstoned() async throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))

    // Device B holds one fill the cascade will tombstone (exercises the merge
    // `.remote` path) and one it has never seen (exercises the local==nil path).
    let knownId = UUID.v7()
    try repo.upsertFillUp(makeSyncFillUp(id: knownId, vehicleId: vehicleId, odometer: 121_000),
                          syncState: .synced(scn: 2))
    let unknownId = UUID.v7()

    // Device A deleted the car: every tombstone shares the one stamp, so the
    // vehicle tombstone pushes first and its cascade follows.
    let stamp = t0.addingTimeInterval(86_400)
    var tombVehicle = makeSyncVehicle(id: vehicleId)
    tombVehicle.updatedAt = stamp
    tombVehicle.deletedAt = stamp
    var tombKnown = makeSyncFillUp(id: knownId, vehicleId: vehicleId, odometer: 121_000)
    tombKnown.updatedAt = stamp
    tombKnown.deletedAt = stamp
    var tombUnknown = makeSyncFillUp(id: unknownId, vehicleId: vehicleId, odometer: 122_000)
    tombUnknown.updatedAt = stamp
    tombUnknown.deletedAt = stamp

    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [
            makePullRecord(tombVehicle, scn: 3),
            makePullRecord(tombKnown, scn: 4),
            makePullRecord(tombUnknown, scn: 5)
        ], nextSince: 5, more: false, schemaPolicy: policy))

    let engine = makeSyncEngine(repository: repo, transport: transport)
    let outcome = await engine.synchronize()

    let vehicle = try repo.vehicle(id: vehicleId)
    #expect(vehicle?.deletedAt != nil,
            "the vehicle stays tombstoned - the cascade must not resurrect its own victim (S5a)")
    let vehicleLocal = try repo.localSyncRecord(id: vehicleId, entityType: Vehicle.entityType)
    #expect(vehicleLocal?.syncState != .dirty,
            "a tombstoned vehicle that is NOT dirty cannot echo back to the server")
    #expect(vehicle?.archived == false, "it never became the S5 'came back' archive state")
    #expect(try repo.liveFillUps(forVehicle: vehicleId).isEmpty, "the cascade entries stay tombstoned")
    #expect(try repo.fetchDirtyRows().isEmpty, "nothing is queued - the resurrection is not pushed back")
    #expect(outcome.pushed == 0, "the push half has no work: the car stays gone")
}

/// S5 must keep working: a NEW, LIVE entry arriving for a car this device
/// deleted still resurrects it as archived, still marks it dirty (so it pushes
/// and every device sees the Garage banner), and still attaches the entry
/// (docs/SYNC.md S5). Distinguishing fixture: the delete has already reached
/// the server, so the vehicle is tombstoned but NOT dirty before the entry
/// arrives - the dirty flag the test asserts is the resurrection's own.
@Test func s5aLiveEntryStillResurrectsACarDeletedOnAnotherDevice() async throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))

    // Device A deleted the car; this device already pulled AND pushed that
    // tombstone, so the vehicle is tombstoned and synced.
    try repo.softDeleteVehicle(id: vehicleId)
    _ = await makeSyncEngine(repository: repo, transport: SyncTransportDouble()).synchronize()
    var vehicleLocal = try repo.localSyncRecord(id: vehicleId, entityType: Vehicle.entityType)
    #expect(vehicleLocal?.record.deleted == true, "the vehicle is tombstoned on this device")
    #expect(vehicleLocal?.syncState != .dirty, "the delete already reached the server")

    // Device B, offline before the delete, logged one last LIVE fill-up. The
    // pull applies it, but the push half is offline (S7), so the resurrected
    // car's own dirty flag must SURVIVE the cycle - it is the queue entry that
    // pushes the archived car (and the banner) to every device once online.
    let fill = makeSyncFillUp(id: UUID.v7(), vehicleId: vehicleId,
                              date: t0.addingTimeInterval(86_400), odometer: 121_000)
    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(fill, scn: 2)], nextSince: 2, more: false, schemaPolicy: policy))
    transport.enqueuePushError(.offline)

    let outcome = await makeSyncEngine(repository: repo, transport: transport).synchronize()
    #expect(outcome.offline, "the pull applied and the push failed - the fixture that shows the dirty flag")

    let vehicle = try repo.vehicle(id: vehicleId)
    #expect(vehicle?.deletedAt == nil, "the vehicle resurrects (S5)")
    #expect(vehicle?.archived == true, "...as ARCHIVED, never active")
    vehicleLocal = try repo.localSyncRecord(id: vehicleId, entityType: Vehicle.entityType)
    #expect(vehicleLocal?.syncState == .dirty,
            "the resurrection is a new local write - it must stay queued and push once online")
    #expect(try repo.liveFillUps(forVehicle: vehicleId).count == 1, "the live entry is attached")
}

/// S5a round trip (L2/L1): device A deletes its last car, device B pulls the
/// vehicle tombstone AND its cascade in push order, the car stays gone on B,
/// B pushes nothing back, and A never gets it back. The server is the push
/// order itself: B's pull is built from what A actually pushed.
@Test func s5aFullRoundTripACarDeletedOnOneDeviceStaysGoneOnEveryDevice() async throws {
    // Both devices hold the same car and fill, synced.
    let vehicleId = UUID.v7()
    let fillId = UUID.v7()
    let repoA = try makeSyncRepository()
    let repoB = try makeSyncRepository()
    for repo in [repoA, repoB] {
        try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))
        try repo.upsertFillUp(makeSyncFillUp(id: fillId, vehicleId: vehicleId, odometer: 121_000),
                              syncState: .synced(scn: 2))
    }

    // A deletes its last car and syncs: the vehicle tombstone pushes first,
    // the co-tombstoned fill after it (one stamp, registry order).
    try repoA.softDeleteVehicle(id: vehicleId)
    let transportA = SyncTransportDouble()
    let outcomeA = await makeSyncEngine(repository: repoA, transport: transportA).synchronize()
    let pushes = transportA.recordedPushBatches.flatMap { $0 }
    #expect(outcomeA.pushed == 2, "the vehicle tombstone and its cascade push")
    #expect(pushes.count == 2)
    #expect(pushes.first?.entityType == Vehicle.entityType, "the vehicle tombstone reaches the server first")
    #expect(pushes.allSatisfy { $0.deleted }, "both pushed changes are tombstones")

    // The server stores them in push order; B pulls exactly that stream.
    let records = pushes.enumerated().map { index, change in
        SyncPullRecord(id: change.id, entityType: change.entityType,
                       schemaVersion: change.schemaVersion,
                       scn: Int64(10 + index), payload: change.payload,
                       clientUpdatedAt: change.clientUpdatedAt, deleted: change.deleted,
                       originDeviceName: "device A")
    }
    let transportB = SyncTransportDouble()
    transportB.enqueuePull(SyncPullResponse(records: records, nextSince: 12,
                                            more: false, schemaPolicy: policy))
    let outcomeB = await makeSyncEngine(repository: repoB, transport: transportB).synchronize()

    // The car stays gone on B, and B does not push the deletion back.
    let vehicleB = try repoB.vehicle(id: vehicleId)
    #expect(vehicleB?.deletedAt != nil, "the vehicle stays tombstoned on B")
    #expect(try repoB.localSyncRecord(id: vehicleId, entityType: Vehicle.entityType)?.syncState != .dirty,
            "B does not re-dirty the tombstone")
    #expect(try repoB.liveFillUps(forVehicle: vehicleId).isEmpty, "the cascade entries stay tombstoned on B")
    #expect(outcomeB.pushed == 0 && transportB.recordedPushBatches.isEmpty,
            "B pushes nothing back - no newer record can overwrite A's tombstone")

    // A syncs again; the server has nothing new, so the car never comes back.
    _ = await makeSyncEngine(repository: repoA, transport: transportA).synchronize()
    #expect(try repoA.liveVehicles().isEmpty, "the empty garage survives on A")
    #expect(try repoA.vehicle(id: vehicleId)?.deletedAt != nil, "A never pulls its own deleted car back")
}

// MARK: - S8

@Test func s8MergeNeverRecomputesAMoneySnapshot() throws {
    // Both devices backfilled the same fill-up from the same feed: the merged
    // record's home amount is whichever side LWW kept, byte-for-byte - the merge
    // never recomputes a third value (docs/SYNC.md S8).
    let pln = CurrencyCode(rawValue: "PLN")!
    let rate = Decimal(string: "4.2706")!
    let money = Money(amount: Decimal(string: "289.50")!, currency: pln, homeCurrency: .eur)
        .converted(using: RateSnapshot(rate: rate, rateDate: t0, source: .ecb))

    var fill = makeSyncFillUp(id: UUID.v7(), vehicleId: UUID.v7())
    fill.money = money

    let older = makeSyncRecord(fill, clientUpdatedAt: t0)
    let newer = makeSyncRecord(fill, clientUpdatedAt: t0.addingTimeInterval(1))

    let result = RecordMerge.merge(local: older, remote: newer)
    let merged = try decodeFillUp(result.keep.payload)

    #expect(merged.money?.homeAmount == Decimal(string: "67.79"),
            "the home-currency snapshot survives the merge exactly, never recomputed")
    #expect(merged.money?.rate == rate)
}

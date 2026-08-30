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
    let engine = makeSyncEngine(repository: repo, transport: transport)
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

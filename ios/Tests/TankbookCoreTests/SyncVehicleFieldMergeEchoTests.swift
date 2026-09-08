import Foundation
import os
import Testing
@testable import TankbookCore

// RV.136: the `Vehicle` field-merge path could still echo a device's own record
// back on an idle account. RV.14 stopped the loop when the two sides' per-field
// version maps agree; RV.35 stopped the record-level byte-comparison echo. This
// file covers the third shape: two sides whose VERSION MAPS disagree while the
// decoded `Vehicle` is identical. `mergeVehicle` builds the merged map as the
// element-wise max of the two sides' maps, where a missing stamp falls back to
// that side's whole `clientUpdatedAt` - so one side stamped per-field and the
// other not yields a THIRD map no side holds even when the content never
// changed. The RV.14 guards demanded the merged map equal one side's map, so
// that phantom was reported as `.fieldMerge`, the unchanged row was re-stored
// `.dirty`, and the pull manufactured a push of content the server already had.
// The fix judges "did the merge change anything" on the decoded content alone;
// the version map is bookkeeping and is never a "new write".

private let fieldMergeT0 = Date(timeIntervalSinceReferenceDate: 0)
private let fieldMergePolicy = SyncSchemaPolicy(minSupported: 1, current: 1)

private func fieldMergeDay(_ day: Int) -> Date {
    fieldMergeT0.addingTimeInterval(Double(day) * 86_400)
}

/// The seven mergeable field names, each stamped at `date`.
private func fullVersions(_ date: Date) -> [String: Date] {
    var result: [String: Date] = [:]
    for field in VehicleMergeFields.all { result[field] = date }
    return result
}

/// A server double that stores what it accepts and hands every pull everything
/// at an SCN above the cursor - the honest single-device echo. Cycle N+1's pull
/// returns cycle N's push, exactly what the production log shows.
private final class EchoServerTransport: SyncTransport, @unchecked Sendable {
    private struct State {
        var store: [UUID: (scn: Int64, record: SyncPullRecord)] = [:]
        var pushBatches: [[SyncPushChange]] = []
        var nextScn: Int64 = 1
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    var recordedPushBatches: [[SyncPushChange]] {
        lock.withLock { $0.pushBatches }
    }

    func seed(_ record: SyncPullRecord) {
        lock.withLock { $0.store[record.id] = (record.scn, record) }
    }

    func pull(since: Int64, limit: Int) async throws -> SyncPullResponse {
        lock.withLock { state in
            let records = state.store.values
                .filter { $0.scn > since }
                .sorted { $0.scn < $1.scn }
                .map { $0.record }
            let nextSince = records.last?.scn ?? since
            return SyncPullResponse(records: records, nextSince: nextSince,
                                    more: false, schemaPolicy: fieldMergePolicy)
        }
    }

    func push(_ changes: [SyncPushChange]) async throws -> SyncPushResponse {
        let results = lock.withLock { state -> [SyncPushResult] in
            state.pushBatches.append(changes)
            var results: [SyncPushResult] = []
            for change in changes {
                let scn = state.nextScn
                state.nextScn += 1
                state.store[change.id] = (scn, SyncPullRecord(
                    id: change.id, entityType: change.entityType,
                    schemaVersion: change.schemaVersion, scn: scn,
                    payload: change.payload, clientUpdatedAt: change.clientUpdatedAt,
                    deleted: change.deleted))
                results.append(SyncPushResult(id: change.id,
                                              status: .accepted(newScn: scn, clamped: false)))
            }
            return results
        }
        return SyncPushResponse(results: results)
    }
}

// MARK: - The pure merge, at the level it decides

/// L1: one side carries per-field stamps, the other carries none, both decode
/// to the same `Vehicle`. The merged version map is a phantom neither side
/// holds, so the merge must report "nothing to push" - judged on content.
@Test func asymmetricVersionMapsWithIdenticalContentAreNotAFieldMerge() throws {
    let id = UUID.v7()
    let localWhole = fieldMergeDay(5)
    let remoteWhole = fieldMergeDay(9)
    var localVehicle = makeSyncVehicle(id: id, name: "Volvo")
    localVehicle.updatedAt = localWhole
    var remoteVehicle = makeSyncVehicle(id: id, name: "Volvo")
    remoteVehicle.updatedAt = remoteWhole

    let local = makeSyncRecord(localVehicle, clientUpdatedAt: localWhole, fieldVersions: nil)
    var remoteVersions = fullVersions(fieldMergeDay(3))
    remoteVersions["tankCapacityL"] = remoteWhole
    remoteVersions["archived"] = remoteWhole
    let remote = makeSyncRecord(remoteVehicle, clientUpdatedAt: remoteWhole,
                                fieldVersions: remoteVersions)

    let result = RecordMerge.merge(local: local, remote: remote)

    #expect(result.winner == .remote,
            "identical decoded content is not a field merge, whatever the maps say")
    #expect(result.keep == remote, "the server already holds exactly this content")
}

/// L1: the general asymmetric shape - both sides carry maps, but of different
/// coverage (each side lacks a field the other stamped), decoding to the same
/// vehicle. The element-wise max is again a third map.
@Test func partialMapsOnBothSidesWithIdenticalContentAreNotAFieldMerge() throws {
    let id = UUID.v7()
    let whole = fieldMergeDay(5)
    var vehicle = makeSyncVehicle(id: id, name: "Volvo")
    vehicle.updatedAt = whole

    // Local knows only `name` and `tankCapacityL`; remote knows the other five.
    var localMap = fullVersions(fieldMergeDay(2))
    localMap["name"] = whole
    localMap["tankCapacityL"] = whole
    var remoteMap = fullVersions(fieldMergeDay(2))
    remoteMap["initialOdometer"] = whole
    remoteMap["archived"] = whole

    let local = makeSyncRecord(vehicle, clientUpdatedAt: whole, fieldVersions: localMap)
    let remote = makeSyncRecord(vehicle, clientUpdatedAt: whole, fieldVersions: remoteMap)

    let result = RecordMerge.merge(local: local, remote: remote)

    #expect(result.winner == .remote, "identical content resolves to nothing to push")
}

// MARK: - L1: a pull that changes nothing must leave the row CLEAN

/// The reported defect, one pull: applying a row equivalent to the local
/// vehicle re-dirtied it and pushed it back. The fixture is the exact state a
/// pre-PR.4 synced row meets after a relaunch - no payload-memory row, while
/// the server copy carries per-field stamps straddling the local whole.
@Test func pullingBackAContentEquivalentVehicleLeavesItClean() async throws {
    let repo = try makeSyncRepository()
    let id = UUID.v7()
    let localWhole = fieldMergeDay(5)
    var vehicle = makeSyncVehicle(id: id, name: "Volvo")
    vehicle.updatedAt = localWhole
    try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))

    let remoteWhole = fieldMergeDay(9)
    var remote = makeSyncVehicle(id: id, name: "Volvo")
    remote.updatedAt = remoteWhole
    var remoteVersions = fullVersions(fieldMergeDay(3))
    remoteVersions["tankCapacityL"] = remoteWhole
    remoteVersions["archived"] = remoteWhole

    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(remote, scn: 2, fieldVersions: remoteVersions)],
        nextSince: 2, more: false, schemaPolicy: fieldMergePolicy))

    let engine = makeSyncEngine(repository: repo, transport: transport,
                                memory: DatabaseSyncPayloadMemory(repository: repo))
    let outcome = await engine.synchronize()

    #expect(outcome.pushed == 0, "an unchanged vehicle must not be re-pushed (RV.136)")
    #expect(transport.recordedPushBatches.isEmpty, "the pull must not manufacture a push")
    guard case .synced = try repo.localSyncRecord(id: id, entityType: Vehicle.entityType)?.syncState else {
        Issue.record("the vehicle must settle CLEAN, never re-dirtied by its own echo")
        return
    }
    #expect(try repo.fetchDirtyRows().isEmpty)
}

// MARK: - L3: idle across two foreground cycles pushes nothing

/// The row's whole point, at the cadence that shows a loop: two idle cycles
/// over the same asymmetric state must push ZERO records. One cycle cannot show
/// this - the echo only exists because the previous push assigned an SCN.
@Test func idleAccountAcrossTwoForegroundCyclesPushesNothing() async throws {
    let repo = try makeSyncRepository()
    let id = UUID.v7()
    let localWhole = fieldMergeDay(5)
    var vehicle = makeSyncVehicle(id: id, name: "Volvo")
    vehicle.updatedAt = localWhole
    try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))

    let remoteWhole = fieldMergeDay(9)
    var remote = makeSyncVehicle(id: id, name: "Volvo")
    remote.updatedAt = remoteWhole
    var remoteVersions = fullVersions(fieldMergeDay(3))
    remoteVersions["tankCapacityL"] = remoteWhole
    remoteVersions["archived"] = remoteWhole

    let transport = EchoServerTransport()
    transport.seed(makePullRecord(remote, scn: 2, fieldVersions: remoteVersions))
    let engine = makeSyncEngine(repository: repo, transport: transport,
                                memory: DatabaseSyncPayloadMemory(repository: repo))

    let first = await engine.synchronize()
    let second = await engine.synchronize()

    #expect(first.pushed == 0, "foreground cycle 1 on an idle account must push nothing")
    #expect(second.pushed == 0, "foreground cycle 2 on an idle account must push nothing")
    #expect(transport.recordedPushBatches.isEmpty,
            "the transport push count is zero - sync.push still means something changed")
    #expect(try repo.fetchDirtyRows().isEmpty, "the vehicle settles synced, never dirty")
}

// MARK: - The over-fix guard: S9 must still push a genuine field merge

/// A genuinely merged Vehicle - the local side renamed at day 8, the remote
/// corrected the tank at day 4 - produces content neither side had. That must
/// STILL be stored dirty and STILL push (S9, hard rule 8). Closing the loop by
/// never dirtying a `.fieldMerge` would lose the local rename.
@Test func aGenuineFieldMergeIsStillStoredDirtyAndStillPushes() async throws {
    let repo = try makeSyncRepository()
    let id = UUID.v7()
    let baseline = makeSyncVehicle(id: id, name: "Volvo", tankCapacityL: 71)

    let transport1 = SyncTransportDouble()
    transport1.enqueuePull(SyncPullResponse(
        records: [makePullRecord(baseline, scn: 1, fieldVersions: fullVersions(fieldMergeDay(0)))],
        nextSince: 1, more: false, schemaPolicy: fieldMergePolicy))
    _ = await makeSyncEngine(repository: repo, transport: transport1,
                             memory: DatabaseSyncPayloadMemory(repository: repo)).synchronize()

    let friday = fieldMergeDay(8)
    var edited = baseline
    edited.name = "V60"
    edited.updatedAt = friday
    try repo.upsertVehicle(edited)

    let monday = fieldMergeDay(4)
    var remoteVehicle = makeSyncVehicle(id: id, name: "Volvo", tankCapacityL: 60)
    remoteVehicle.updatedAt = monday
    var remoteVersions = fullVersions(fieldMergeDay(0))
    remoteVersions["tankCapacityL"] = monday

    let transport2 = SyncTransportDouble()
    transport2.enqueuePull(SyncPullResponse(
        records: [makePullRecord(remoteVehicle, scn: 5, fieldVersions: remoteVersions)],
        nextSince: 5, more: false, schemaPolicy: fieldMergePolicy))
    let outcome = await makeSyncEngine(repository: repo, transport: transport2,
                                       memory: DatabaseSyncPayloadMemory(repository: repo)).synchronize()

    let merged = try repo.vehicle(id: id)
    #expect(merged?.name == "V60", "the local rename must survive (S9)")
    #expect(merged?.tankCapacityL == 60, "the remote correction must survive (S9)")
    #expect(outcome.pushed == 1, "a genuine field merge is still a new write that pushes")
    #expect(transport2.recordedPushBatches.count == 1)
}

// MARK: - Shape-only observability (docs/LOGGING.md §4)

/// `sync.merge`'s `dirtiedByPull` count is the echo-loop signal: a pull that
/// left a row queued for push. A genuine S9 field merge must record it...
@Test func aGenuineFieldMergeRecordsDirtiedByPullOnTheMergeLine() async throws {
    let sink = InMemorySink()
    let log = TankbookLog(sink: sink, context: {
        LogContext(deviceId: "device-rv136", appVersion: "9.9.9-test", platform: "ios")
    }, breadcrumbs: nil)
    let repo = try makeSyncRepository()
    let id = UUID.v7()
    let baseline = makeSyncVehicle(id: id, name: "Volvo", tankCapacityL: 71)

    let transport1 = SyncTransportDouble()
    transport1.enqueuePull(SyncPullResponse(
        records: [makePullRecord(baseline, scn: 1, fieldVersions: fullVersions(fieldMergeDay(0)))],
        nextSince: 1, more: false, schemaPolicy: fieldMergePolicy))
    _ = await makeSyncEngine(repository: repo, transport: transport1,
                             memory: DatabaseSyncPayloadMemory(repository: repo)).synchronize()

    let friday = fieldMergeDay(8)
    var edited = baseline
    edited.name = "V60"
    edited.updatedAt = friday
    try repo.upsertVehicle(edited)

    let monday = fieldMergeDay(4)
    var remoteVehicle = makeSyncVehicle(id: id, name: "Volvo", tankCapacityL: 60)
    remoteVehicle.updatedAt = monday
    var remoteVersions = fullVersions(fieldMergeDay(0))
    remoteVersions["tankCapacityL"] = monday
    let transport2 = SyncTransportDouble()
    transport2.enqueuePull(SyncPullResponse(
        records: [makePullRecord(remoteVehicle, scn: 5, fieldVersions: remoteVersions)],
        nextSince: 5, more: false, schemaPolicy: fieldMergePolicy))
    let engine = SyncEngine(repository: repo, transport: transport2,
                            cursorStore: InMemorySyncCursorStore(),
                            payloadMemory: DatabaseSyncPayloadMemory(repository: repo),
                            log: log)

    _ = await engine.synchronize()

    let text = sink.rendered().joined(separator: "\n")
    #expect(text.contains("dirtiedByPull=1"),
            "a genuine field merge is a pull that dirtied the merged row")
}

/// ...while an idle echo of this device's own content must NOT: the signal that
/// would have made the production loop diagnosable from one session's log.
@Test func anIdleContentEqualEchoRecordsNoDirtiedByPull() async throws {
    let sink = InMemorySink()
    let log = TankbookLog(sink: sink, context: {
        LogContext(deviceId: "device-rv136", appVersion: "9.9.9-test", platform: "ios")
    }, breadcrumbs: nil)
    let repo = try makeSyncRepository()
    let id = UUID.v7()
    let localWhole = fieldMergeDay(5)
    var vehicle = makeSyncVehicle(id: id, name: "Volvo")
    vehicle.updatedAt = localWhole
    try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))

    let remoteWhole = fieldMergeDay(9)
    var remote = makeSyncVehicle(id: id, name: "Volvo")
    remote.updatedAt = remoteWhole
    var remoteVersions = fullVersions(fieldMergeDay(3))
    remoteVersions["tankCapacityL"] = remoteWhole
    remoteVersions["archived"] = remoteWhole
    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(remote, scn: 2, fieldVersions: remoteVersions)],
        nextSince: 2, more: false, schemaPolicy: fieldMergePolicy))
    let engine = SyncEngine(repository: repo, transport: transport,
                            cursorStore: InMemorySyncCursorStore(),
                            payloadMemory: DatabaseSyncPayloadMemory(repository: repo),
                            log: log)

    _ = await engine.synchronize()

    let mergeLines = sink.all().filter { $0.event == "sync.merge" }
    #expect(!mergeLines.isEmpty, "the pull applied one record, so the aggregate line exists")
    let text = sink.rendered().joined(separator: "\n")
    #expect(!text.contains("dirtiedByPull"),
            "a content-equal echo dirties nothing - the loop signal must stay silent")
    #expect(text.contains("recordsApplied=1"))
}

// MARK: - The launch recompute must never write the vehicle

/// S3's post-merge recompute (`revalidateTimeline`) runs after every batch. It
/// may flag an entry and leave it queued - it must NEVER touch the vehicle row:
/// stats are derived, never stored (hard rule 2), and a recompute that wrote
/// the car would re-dirty it and echo the whole vehicle back on an idle account.
@Test func thePostMergeRecomputeFlagsEntriesButNeverWritesTheVehicle() async throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    var vehicle = makeSyncVehicle(id: vehicleId, name: "Volvo", initialOdometer: 119_486)
    vehicle.updatedAt = fieldMergeDay(0)
    try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))

    // A clean Saturday fill and a Monday fill, both synced.
    try repo.upsertFillUp(
        makeSyncFillUp(id: UUID.v7(), vehicleId: vehicleId, date: fieldMergeDay(0),
                       odometer: 119_486),
        syncState: .synced(scn: 2))
    try repo.upsertFillUp(
        makeSyncFillUp(id: UUID.v7(), vehicleId: vehicleId, date: fieldMergeDay(2),
                       odometer: 120_000),
        syncState: .synced(scn: 3))

    // A Sunday fill at a LOWER odometer arrives by pull - the S3 shape that
    // forces the recompute to flag it.
    var sunday = makeSyncFillUp(id: UUID.v7(), vehicleId: vehicleId, date: fieldMergeDay(1),
                                odometer: 119_210)
    sunday.updatedAt = fieldMergeDay(1)
    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(sunday, scn: 4)], nextSince: 4, more: false,
        schemaPolicy: fieldMergePolicy))

    let outcome = await makeSyncEngine(repository: repo, transport: transport).synchronize()

    #expect(outcome.flaggedEntries >= 1, "the out-of-order entry is flagged (S3)")
    let vehicleLocal = try repo.localSyncRecord(id: vehicleId, entityType: Vehicle.entityType)
    #expect(vehicleLocal?.syncState != .dirty,
            "the recompute must never write the vehicle (hard rule 2)")
    #expect(try repo.vehicle(id: vehicleId)?.updatedAt == vehicle.updatedAt,
            "the vehicle row is untouched by the recompute")
}

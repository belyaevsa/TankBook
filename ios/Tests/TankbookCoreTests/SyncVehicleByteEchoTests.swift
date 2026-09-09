import Foundation
import os
import Testing
@testable import TankbookCore

// RV.136 (third arm): `RecordMerge.recordsEqual` switches over every synced
// entity type and had no `Vehicle` case, so a Vehicle fell to `default:` and was
// compared by raw payload bytes - exactly the comparison RV.35 removed for every
// other entity. A Vehicle whose only difference is a lossy server round-trip (a
// date re-serialised without fractional seconds, a normalised number token)
// decodes equal but byte-differs, so `.local` re-dirtied it on every pull and
// the same vehicle pushed forever. These tests pin the fix: a Vehicle is
// compared at the decoded level like everything else, every synced entity has a
// case (the enumeration test is the guard that stops a fourth arm), and a
// genuinely edited Vehicle still re-dirties and pushes (S9, hard rule 8).

private let byteT0 = Date(timeIntervalSinceReferenceDate: 0)
private let bytePolicy = SyncSchemaPolicy(minSupported: 1, current: 1)

private func byteDay(_ day: Double) -> Date {
    byteT0.addingTimeInterval(day * 86_400)
}

/// The server's lossy re-encode of a date string: fractional seconds dropped
/// ("…T00:00:00.000Z" -> "…T00:00:00Z"). The bytes differ; the parsed `Date`
/// does not.
private func dropFractionalSeconds(_ string: String) -> String {
    string.hasSuffix(".000Z") ? String(string.dropLast(5)) + "Z" : string
}

/// Rewrites one top-level date string the way the server's re-encode would.
private func dropFractionalSeconds(_ payload: JSONValue, key: String) -> JSONValue {
    guard case .object(var dict) = payload, case .string(let raw)? = dict[key] else { return payload }
    dict[key] = .string(dropFractionalSeconds(raw))
    return .object(dict)
}

/// The server's lossy copy of a whole payload: every whole-second date string
/// loses its fractional suffix. Recurses, so the `fieldVersions` map and nested
/// stamps are covered too.
private func lossyServerCopy(_ payload: JSONValue) -> JSONValue {
    switch payload {
    case .object(let dict):
        return .object(dict.mapValues(lossyServerCopy))
    case .array(let items):
        return .array(items.map(lossyServerCopy))
    case .string(let raw):
        return .string(dropFractionalSeconds(raw))
    default:
        return payload
    }
}

// MARK: - The comparison itself, at the level it reasons (L1)

/// The headline: two Vehicle records whose decoded content is identical but
/// whose payload bytes differ must be `recordsEqual`. Today the missing
/// `Vehicle` case sends them to `default:` and compares bytes, so this reports
/// `false` - the third arm of the echo loop.
@Test func twoDecodedEqualVehiclesWhosePayloadBytesDifferAreEqual() throws {
    let id = UUID.v7()
    let vehicle = makeSyncVehicle(id: id, name: "V60", tankCapacityL: 71)
    let local = makeSyncRecord(vehicle, clientUpdatedAt: byteT0)

    // The lossy round-trip: `updatedAt` re-serialised without fractional
    // seconds. Bytes differ, the decoded Vehicle is identical.
    let remote = SyncRecord(
        id: local.id, entityType: local.entityType, schemaVersion: local.schemaVersion,
        payload: dropFractionalSeconds(local.payload, key: "updatedAt"),
        clientUpdatedAt: local.clientUpdatedAt, deleted: false)

    #expect(local.payload != remote.payload,
            "the fixture must differ in bytes - byte-identical payloads cannot show the bug")
    #expect(RecordMerge.recordsEqual(local, remote),
            "a Vehicle whose only difference is a lossy re-encode is the same record")
}

/// A re-formatted number token is the same decoded Vehicle too - the other
/// real lossy case from the record-level loop.
@Test func aVehicleWithANormalisedNumberTokenIsRecordsEqual() throws {
    let id = UUID.v7()
    let vehicle = makeSyncVehicle(id: id, name: "V60", tankCapacityL: 71, paceLimitKmPerDay: 1500)
    let local = makeSyncRecord(vehicle, clientUpdatedAt: byteT0)
    guard case .object(var dict) = local.payload, case .number(let token)? = dict["tankCapacityL"] else {
        Issue.record("fixture payload must carry tankCapacityL as a number")
        return
    }
    #expect(token == "71", "the encoder emits the canonical whole-number token")
    dict["tankCapacityL"] = .number("71.0")
    let remote = SyncRecord(
        id: local.id, entityType: local.entityType, schemaVersion: local.schemaVersion,
        payload: .object(dict), clientUpdatedAt: local.clientUpdatedAt, deleted: false)

    #expect(RecordMerge.recordsEqual(local, remote),
            "71 and 71.0 are the same Double, whatever the bytes say")
}

/// The S9 counterpart, at the level `recordsEqual` reasons: a genuinely
/// different decoded Vehicle is still a different record. Making the `Vehicle`
/// case too lax would stop a real edit from re-dirtying and pushing (hard
/// rule 8).
@Test func twoDecodedDifferentVehiclesAreNotEqual() throws {
    let id = UUID.v7()
    let local = makeSyncRecord(makeSyncVehicle(id: id, name: "V60"), clientUpdatedAt: byteT0)
    let edited = makeSyncRecord(makeSyncVehicle(id: id, name: "V60 Cross Country"),
                                clientUpdatedAt: byteT0)
    #expect(RecordMerge.recordsEqual(local, edited) == false,
            "a genuinely different Vehicle must still count as different (S9)")
}

// MARK: - Every synced entity has a case (L1)

/// The guard that stops a fourth arm: `recordsEqual`'s switch must carry one
/// case per synced entity type. A type without a case falls to `default:` and
/// compares bytes, which never converge across a lossy round-trip - the bug
/// this file fixes. The test walks the closed catalog (`SyncedEntityCatalog`)
/// and asserts each type is compared at the decoded level, so a future entity
/// added to the catalog but not to the switch fails here.
@Test func everySyncedEntityTypeIsComparedAtTheDecodedLevel() throws {
    let vehicleId = UUID.v7()
    let charge = ChargeSession(
        id: UUID.v7(), createdAt: byteT0, updatedAt: byteT0, vehicleId: vehicleId,
        date: byteT0, provenance: .manual, energyKWh: 43.2, chargeType: .dcPublic)
    let service = ServiceRecord(
        id: UUID.v7(), createdAt: byteT0, updatedAt: byteT0, vehicleId: vehicleId,
        date: byteT0, provenance: .manual)
    let expense = Expense(
        id: UUID.v7(), createdAt: byteT0, updatedAt: byteT0, vehicleId: vehicleId,
        date: byteT0, provenance: .manual, category: .insurance, title: "Insurance")
    let reminder = Reminder(
        id: UUID.v7(), createdAt: byteT0, updatedAt: byteT0, vehicleId: vehicleId,
        title: "Oil change", category: .oil, status: .scheduled)
    let station = Station(
        id: UUID.v7(), createdAt: byteT0, updatedAt: byteT0, name: "Shell",
        favorite: false, defaults: Station.Defaults(fuelKind: nil, fuelGrade: nil))
    let tariff = Tariff(
        id: UUID.v7(), createdAt: byteT0, updatedAt: byteT0, name: "Home night",
        pricePerKWh: Decimal(string: "0.24")!, currency: .eur, validFrom: byteT0)
    let tireSet = TireSet(
        id: UUID.v7(), createdAt: byteT0, updatedAt: byteT0, vehicleId: vehicleId,
        name: "Winter Nokian", purchaseExpenseId: nil)

    let fixtures: [(label: String, record: SyncRecord)] = [
        ("vehicle", makeSyncRecord(makeSyncVehicle(id: UUID.v7(), name: "V60"), clientUpdatedAt: byteT0)),
        ("fillUp", makeSyncRecord(makeSyncFillUp(vehicleId: vehicleId), clientUpdatedAt: byteT0)),
        ("chargeSession", makeSyncRecord(charge, clientUpdatedAt: byteT0)),
        ("serviceRecord", makeSyncRecord(service, clientUpdatedAt: byteT0)),
        ("expense", makeSyncRecord(expense, clientUpdatedAt: byteT0)),
        ("reminder", makeSyncRecord(reminder, clientUpdatedAt: byteT0)),
        ("station", makeSyncRecord(station, clientUpdatedAt: byteT0)),
        ("tariff", makeSyncRecord(tariff, clientUpdatedAt: byteT0)),
        ("tireSet", makeSyncRecord(tireSet, clientUpdatedAt: byteT0)),
        ("attachment", makeSyncRecord(
            makeSyncAttachment(sha256: "ab12", relativePath: "photos/x.jpg"),
            clientUpdatedAt: byteT0)),
        ("preferences", makeSyncRecord(Preferences(createdAt: byteT0, updatedAt: byteT0),
                                       clientUpdatedAt: byteT0))
    ]

    #expect(fixtures.count == SyncedEntityCatalog.all.count,
            "the test itself must enumerate every synced entity")

    for fixture in fixtures {
        let remote = SyncRecord(
            id: fixture.record.id, entityType: fixture.record.entityType,
            schemaVersion: fixture.record.schemaVersion,
            payload: dropFractionalSeconds(fixture.record.payload, key: "updatedAt"),
            clientUpdatedAt: fixture.record.clientUpdatedAt, deleted: fixture.record.deleted)
        #expect(fixture.record.payload != remote.payload,
                "\(fixture.label): the lossy copy must differ in bytes or the test is vacuous")
        #expect(RecordMerge.recordsEqual(fixture.record, remote),
                "\(fixture.label): a type without a recordsEqual case re-dirties its own echo")
    }
}

// MARK: - The engine loop (L3): an idle account pushes nothing

/// A server double that re-forms the loop's asymmetry on every store: it clamps
/// each accepted `clientUpdatedAt` a second older (the server's clock behind
/// the device, docs/SYNC.md -> Clock skew) and re-encodes the stored payload
/// lossily (whole-second dates lose their fractional suffix). Without BOTH the
/// second cycle's echo is this device's own bytes and the bug self-heals - the
/// vacuous trap named in the RV.35 brief.
private final class ClampingEchoTransport: SyncTransport, @unchecked Sendable {
    private struct State {
        var store: [UUID: (scn: Int64, record: SyncPullRecord)] = [:]
        var pushBatches: [[SyncPushChange]] = []
        var nextScn: Int64 = 1
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    var recordedPushBatches: [[SyncPushChange]] {
        lock.withLock { $0.pushBatches }
    }

    /// Seeds the server's copy of a record the device pushed in an earlier
    /// session, run through the same clamp + lossy copy every store applies, so
    /// the seed and a fresh push are byte-identical shapes.
    func seed(_ record: SyncRecord, at scn: Int64) {
        lock.withLock { state in
            state.store[record.id] = (scn, serverCopy(of: record, scn: scn))
            state.nextScn = max(state.nextScn, scn + 1)
        }
    }

    func pull(since: Int64, limit: Int) async throws -> SyncPullResponse {
        lock.withLock { state in
            let records = state.store.values
                .filter { $0.scn > since }
                .sorted { $0.scn < $1.scn }
                .map { $0.record }
            let nextSince = records.last?.scn ?? since
            return SyncPullResponse(records: records, nextSince: nextSince,
                                    more: false, schemaPolicy: bytePolicy)
        }
    }

    func push(_ changes: [SyncPushChange]) async throws -> SyncPushResponse {
        let results = lock.withLock { state -> [SyncPushResult] in
            state.pushBatches.append(changes)
            var results: [SyncPushResult] = []
            for change in changes {
                let scn = state.nextScn
                state.nextScn += 1
                let record = SyncRecord(id: change.id, entityType: change.entityType,
                                        schemaVersion: change.schemaVersion,
                                        payload: change.payload,
                                        clientUpdatedAt: change.clientUpdatedAt,
                                        deleted: change.deleted)
                state.store[change.id] = (scn, serverCopy(of: record, scn: scn))
                results.append(SyncPushResult(id: change.id,
                                              status: .accepted(newScn: scn, clamped: true)))
            }
            return results
        }
        return SyncPushResponse(results: results)
    }

    private func serverCopy(of record: SyncRecord, scn: Int64) -> SyncPullRecord {
        SyncPullRecord(
            id: record.id, entityType: record.entityType,
            schemaVersion: record.schemaVersion, scn: scn,
            payload: lossyServerCopy(record.payload),
            clientUpdatedAt: record.clientUpdatedAt.addingTimeInterval(-1),
            deleted: record.deleted)
    }
}

/// The row's whole point, at the cadence that shows a loop: a tombstoned
/// Vehicle whose server echo the pull keeps re-serving must settle after ONE
/// foreground cycle, and two idle cycles must push ZERO records. One cycle
/// cannot show this - the loop only exists because each re-push earns a new SCN
/// that the next cycle's pull returns. (A live Vehicle never reaches the
/// byte-compare arm - RV.14's `.local` short-circuit keeps it - so the honest
/// fixture is the tombstone, which is exactly the case that reaches it.)
@Test func anIdleTombstonedVehicleAcrossTwoForegroundCyclesPushesNothing() async throws {
    let repo = try makeSyncRepository()
    let id = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: id, name: "V60"), syncState: .synced(scn: 1))
    try repo.softDeleteVehicle(id: id, at: byteDay(10))
    try repo.markSynced(id: id, entityType: Vehicle.entityType, scn: 2)

    let local = try repo.localSyncRecord(id: id, entityType: Vehicle.entityType)
    guard let local else {
        Issue.record("the tombstoned vehicle must read back as a local record")
        return
    }
    #expect(local.record.deleted, "the fixture must be a tombstone to reach the byte arm")

    let transport = ClampingEchoTransport()
    transport.seed(local.record, at: 2)
    let engine = makeSyncEngine(repository: repo, transport: transport,
                                memory: DatabaseSyncPayloadMemory(repository: repo))

    let first = await engine.synchronize()
    let second = await engine.synchronize()

    #expect(first.pushed == 0, "foreground cycle 1 on an idle account must push nothing")
    #expect(second.pushed == 0, "foreground cycle 2 on an idle account must push nothing")
    #expect(transport.recordedPushBatches.isEmpty,
            "the transport push count is zero - sync.push still means something changed")
    #expect(try repo.fetchDirtyRows().isEmpty,
            "the tombstone settles synced, never re-dirtied by its own echo")
    guard case .synced = try repo.localSyncRecord(id: id, entityType: Vehicle.entityType)?.syncState else {
        Issue.record("the vehicle must settle synced, never dirty")
        return
    }
}

// MARK: - The log signal (L1)

/// `dirtiedByPull` is the counter the first RV.136 fix added, and it is the one
/// that caught the arm that fix did not close. On an idle single-device account
/// a content-equal echo - whatever its bytes look like - must leave it at zero.
@Test func anIdleLossyVehicleEchoRecordsNoDirtiedByPull() async throws {
    let sink = InMemorySink()
    let log = TankbookLog(sink: sink, context: {
        LogContext(deviceId: "device-rv136", appVersion: "9.9.9-test", platform: "ios")
    }, breadcrumbs: nil)
    let repo = try makeSyncRepository()
    let id = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: id, name: "V60"), syncState: .synced(scn: 1))
    try repo.softDeleteVehicle(id: id, at: byteDay(10))
    try repo.markSynced(id: id, entityType: Vehicle.entityType, scn: 2)

    let local = try repo.localSyncRecord(id: id, entityType: Vehicle.entityType)
    guard let local else {
        Issue.record("the tombstoned vehicle must read back as a local record")
        return
    }
    let transport = ClampingEchoTransport()
    transport.seed(local.record, at: 2)
    let engine = SyncEngine(repository: repo, transport: transport,
                            cursorStore: InMemorySyncCursorStore(),
                            payloadMemory: DatabaseSyncPayloadMemory(repository: repo),
                            log: log)

    _ = await engine.synchronize()

    let mergeLines = sink.all().filter { $0.event == "sync.merge" }
    #expect(!mergeLines.isEmpty, "the pull applied one record, so the aggregate line exists")
    let text = sink.rendered().joined(separator: "\n")
    #expect(text.contains("recordsApplied=1"))
    #expect(!text.contains("dirtiedByPull"),
            "a content-equal echo dirties nothing - the loop signal must stay silent")
}

// MARK: - The over-fix guard: S9 must still push a genuine edit (hard rule 8)

/// The `.local` byte arm also serves the deletion scenarios (S4/S5): a live,
/// genuinely edited Vehicle newer than a remote tombstone must still re-dirty
/// and push. A `Vehicle` case that swallowed real decoded differences - or an
/// over-tightened arm that stopped re-dirtying - would lose the edit.
@Test func aGenuinelyEditedVehicleStillRedirtiesAndPushes() async throws {
    let repo = try makeSyncRepository()
    let id = UUID.v7()
    var edited = makeSyncVehicle(id: id, name: "V60 Cross Country")
    edited.updatedAt = byteDay(12)
    try repo.upsertVehicle(edited, syncState: .synced(scn: 1))

    // A stale tombstone from another device (S4 in the local-wins direction):
    // older stamp, same decoded content apart from the deletion.
    var tombstone = makeSyncVehicle(id: id, name: "V60 Cross Country")
    tombstone.updatedAt = byteDay(10)
    tombstone.deletedAt = byteDay(10)

    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(tombstone, scn: 2, deleted: true)],
        nextSince: 2, more: false, schemaPolicy: bytePolicy))
    let outcome = await makeSyncEngine(repository: repo, transport: transport).synchronize()

    #expect(outcome.pushed == 1, "the newer live edit must still re-dirty and push (S9)")
    #expect(transport.recordedPushBatches.count == 1)
    let live = try repo.vehicle(id: id)
    #expect(live?.deletedAt == nil, "the live vehicle survives the stale tombstone")
    #expect(live?.name == "V60 Cross Country")
    guard case .synced = try repo.localSyncRecord(id: id, entityType: Vehicle.entityType)?.syncState else {
        Issue.record("after the push the row settles synced")
        return
    }
}

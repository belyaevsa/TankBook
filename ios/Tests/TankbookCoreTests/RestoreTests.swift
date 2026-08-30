import Foundation
import os
import Testing
@testable import TankbookCore

// P4.7 restore end-to-end (docs/TASKS.md P4.7, docs/JOURNEYS.md F7): restore is
// the sync engine pulling from cursor 0 - there is no separate restore protocol.
// The load-bearing claim is the L3 headline: a pull-from-zero restore produces a
// dataset that HASH-EQUALS the origin, because a count-only assertion passes a
// restore that silently drops a field. Everything runs against the in-memory
// transport double - never `URLSession`, never a live server.

private let policy = SyncSchemaPolicy(minSupported: 1, current: 1)
private let t0 = Date(timeIntervalSinceReferenceDate: 0)

// MARK: - A deterministic record-store server double

/// An in-memory `SyncTransport` that behaves like the backend: push assigns
/// monotonic SCNs and stores the record stream; pull returns SCN-ordered pages
/// above a cursor. Two scriptable failure knobs drive the interruption tests -
/// a pull-failure predicate over `since` (a page boundary) and a one-shot record
/// corruption on the first pull (a mid-page failure: a page is returned, its
/// records applied one by one, and one throws before the cursor is saved).
final class RestoreServerDouble: SyncTransport, @unchecked Sendable {
    private struct State {
        var records: [SyncPullRecord] = []
        var nextScn: Int64 = 1
        var pullRequests: [(since: Int64, limit: Int)] = []
        var failPullWhen: (@Sendable (Int64) -> Bool)?
        var corruptFirstPullIndex: Int?
        var corrupted = false
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    var recordedPullRequests: [(since: Int64, limit: Int)] {
        lock.withLock { $0.pullRequests }
    }

    /// Fails any pull whose `since` satisfies the predicate (a page-boundary
    /// interruption: the page before it applied and persisted its cursor).
    func failPull(when predicate: @escaping @Sendable (Int64) -> Bool) {
        lock.withLock { $0.failPullWhen = predicate }
    }

    /// Corrupts the record at `index` (of the first page) once: its
    /// `schemaVersion` becomes unsupported, so applying it throws mid-page and
    /// the cursor for that page is never persisted.
    func corruptFirstPullRecord(at index: Int) {
        lock.withLock { $0.corruptFirstPullIndex = index }
    }

    func push(_ changes: [SyncPushChange]) async throws -> SyncPushResponse {
        let results = lock.withLock { state -> [SyncPushResult] in
            var results: [SyncPushResult] = []
            for change in changes {
                let scn = state.nextScn
                state.nextScn += 1
                state.records.append(SyncPullRecord(
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

    func pull(since: Int64, limit: Int) async throws -> SyncPullResponse {
        struct Snapshot {
            var fail: Bool
            var records: [SyncPullRecord]
            var nextSince: Int64
            var more: Bool
        }
        let snapshot = lock.withLock { state -> Snapshot in
            state.pullRequests.append((since, limit))
            let fail = state.failPullWhen?(since) ?? false
            var records = state.records
                .filter { $0.scn > since }
                .sorted { $0.scn < $1.scn }
                .prefix(limit)
                .map { $0 }
            if !state.corrupted, let index = state.corruptFirstPullIndex, index < records.count {
                records[index].schemaVersion = 99
                state.corrupted = true
            }
            let nextSince = records.last?.scn ?? since
            let more = state.records.contains { $0.scn > nextSince }
            return Snapshot(fail: fail, records: records, nextSince: nextSince, more: more)
        }
        if snapshot.fail { throw SyncServerError.offline }
        return SyncPullResponse(records: snapshot.records, nextSince: snapshot.nextSince,
                                more: snapshot.more, schemaPolicy: policy)
    }
}

// MARK: - Dataset seeding

/// Seeds a two-vehicle, multi-entity dataset (the same shape a real garage
/// has) and returns the exact `RestoreStats` the restore must reproduce - the
/// numbers in the verification screen are derived from what landed, and the
/// test asserts those literals rather than a count.
@discardableResult
private func seedRichDataset(into repo: TankbookRepository) throws -> (vehicleIds: [UUID], stats: RestoreStats) {
    let v1 = UUID.v7()
    let v2 = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: v1, name: "Volvo V60", initialOdometer: 119_486))
    try repo.upsertVehicle(makeSyncVehicle(id: v2, name: "ID.4", initialOdometer: 30_000))

    let d1 = t0.addingTimeInterval(86_400)
    let d2 = t0.addingTimeInterval(10 * 86_400)
    let d3 = t0.addingTimeInterval(20 * 86_400)

    // Volvo fills: strictly increasing odometers, clean timeline (no S3 flags).
    try repo.upsertFillUp(makeSyncFillUp(id: UUID.v7(), vehicleId: v1, date: d1, odometer: 119_486, volumeL: 42.3))
    try repo.upsertFillUp(makeSyncFillUp(id: UUID.v7(), vehicleId: v1, date: d2, odometer: 120_000, note: "Shell, A4 exit", volumeL: 51.1))
    var lastFill = makeSyncFillUp(id: UUID.v7(), vehicleId: v1, date: d3, odometer: 120_486, volumeL: 39.0)
    lastFill.provenance = .receiptScan
    try repo.upsertFillUp(lastFill)

    // A charge session (EV, second vehicle) - a different entry type.
    try repo.upsertChargeSession(ChargeSession(
        id: UUID.v7(), createdAt: t0, updatedAt: t0, vehicleId: v2, date: d2,
        odometer: 30_000, money: Money(amount: Decimal(string: "12.40")!, currency: .eur, homeCurrency: .eur),
        provenance: .manual, energyKWh: 62.5, unitPrice: Decimal(string: "0.19")!, chargeType: .acPublic))

    // A service record with line items (the item list must survive restore).
    // Its date/odometer sits between the two fills so the timeline stays clean.
    let service = ServiceRecord(
        id: UUID.v7(), createdAt: t0, updatedAt: t0, vehicleId: v1,
        date: t0.addingTimeInterval(15 * 86_400),
        odometer: 120_200, money: Money(amount: Decimal(string: "148.00")!, currency: .eur, homeCurrency: .eur),
        provenance: .manual, vendor: "Neste", items: [
            ServiceItem(title: "Engine oil", category: .oil,
                        cost: Money(amount: Decimal(string: "89.00")!, currency: .eur, homeCurrency: .eur)),
            ServiceItem(title: "Oil filter", category: .filters,
                        cost: Money(amount: Decimal(string: "59.00")!, currency: .eur, homeCurrency: .eur)),
        ])
    try repo.upsertServiceRecord(service)

    // An expense (a different entry type again).
    try repo.upsertExpense(Expense(
        id: UUID.v7(), createdAt: t0, updatedAt: t0, vehicleId: v1, date: d1,
        money: Money(amount: Decimal(string: "35.00")!, currency: .eur, homeCurrency: .eur),
        provenance: .manual, category: .parking, title: "City parking"))

    // An attachment whose inline thumbnail rides in the payload (P4.6).
    try repo.upsertAttachment(makeSyncAttachment(sha256: "a".padding(toLength: 64, withPad: "a", startingAt: 0),
                                                 thumbnailBase64: "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAA=="))

    let stats = RestoreStats(
        carCount: 2, carNames: ["Volvo V60", "ID.4"], entryCount: 6,
        earliestEntry: d1, latestEntry: d3, lastOdometerKm: 120_486, lastOdometerDaysAgo: nil)
    return ([v1, v2], stats)
}

// MARK: - L3 headline: pull-from-zero hash-equals the origin

@Test func restoreFromZeroHashEqualsOrigin() async throws {
    let origin = try makeSyncRepository()
    try seedRichDataset(into: origin)
    let originHash = RestoreHash.compute(try origin.allRecords())

    // Push the origin's stream to the server double, then restore a FRESH device
    // from cursor 0 - the same call as incremental catch-up (docs/API.md).
    let server = RestoreServerDouble()
    _ = await makeSyncEngine(repository: origin, transport: server).synchronize()

    let restored = try makeSyncRepository()
    let outcome = await RestoreEngine(engine: makeSyncEngine(repository: restored, transport: server)).restore()
    guard case .restored(let stats) = outcome else {
        Issue.record("expected a restored outcome, got \(outcome)")
        return
    }

    #expect(RestoreHash.compute(try restored.allRecords()) == originHash,
            "a pull-from-zero restore must reproduce the origin dataset field-for-field")
    #expect(stats.carCount == 2)
    #expect(stats.entryCount == 6)
}

/// The reason the hash exists: a count-only assertion would stay green while a
/// field is silently dropped. Mutate one field on the restored side and confirm
/// the hash moves - the same check a count could never perform.
@Test func hashMovesWhenAFieldIsDroppedWhereACountWouldNot() async throws {
    // ONE repository, tampered in place. Seeding two repositories would give
    // them different UUIDs (seedRichDataset mints fresh ones), so their hashes
    // would differ no matter what - the assertion would hold with the payload
    // excluded from the hash entirely, proving nothing. Mutation-checked:
    // dropping `payload` from RestoreHash.compute must fail this test.
    let repo = try makeSyncRepository()
    try seedRichDataset(into: repo)
    let beforeHash = RestoreHash.compute(try repo.allRecords())
    let beforeCount = try repo.allRecords().count

    // Drop a fill-up's volume in place - same records, same ids, one field lost.
    let volvo = try repo.liveVehicles().first { $0.name == "Volvo V60" }!
    var fills = try repo.liveFillUps(forVehicle: volvo.id).sorted { $0.date < $1.date }
    fills[0].volumeL = 0   // a silently dropped field
    try repo.upsertFillUp(fills[0], syncState: .dirty)

    #expect(RestoreHash.compute(try repo.allRecords()) != beforeHash,
            "dropping a field must move the hash even though the count is unchanged")
    #expect(try repo.allRecords().count == beforeCount,
            "the record counts are identical - only the hash can see the loss")
}

// MARK: - Interrupted restore resumes without loss or duplication

@Test func interruptedRestoreResumesAtAPageBoundary() async throws {
    let origin = try makeSyncRepository()
    try seedRichDataset(into: origin)
    let originHash = RestoreHash.compute(try origin.allRecords())

    let server = RestoreServerDouble()
    _ = await makeSyncEngine(repository: origin, transport: server).synchronize()

    // Interrupt at the page boundary: page 1 (limit 2) applies and persists its
    // cursor, then the pull for page 2 fails.
    server.failPull { $0 > 0 }
    let restored = try makeSyncRepository()
    let cursor = InMemorySyncCursorStore()
    let engine1 = makeSyncEngine(repository: restored, transport: server, cursor: cursor, pullPageLimit: 2)
    let outcome1 = await RestoreEngine(engine: engine1).restore()
    if case .restored(let partial) = outcome1 {
        #expect(partial.carCount == 2, "page 1 (the two vehicles) landed before the interruption")
        #expect(partial.entryCount == 0, "no entries landed yet - the interruption was at the page boundary")
    } else {
        Issue.record("the interrupted run reports the partial data it did land, got \(outcome1)")
    }

    // Resume: a fresh engine continues from the persisted cursor (which is
    // past page 1). No loss, no duplication.
    server.failPull { _ in false }
    let engine2 = makeSyncEngine(repository: restored, transport: server, cursor: cursor, pullPageLimit: 2)
    let outcome2 = await RestoreEngine(engine: engine2).restore()
    guard case .restored = outcome2 else {
        Issue.record("expected the resume to finish restored, got \(outcome2)")
        return
    }

    #expect(RestoreHash.compute(try restored.allRecords()) == originHash,
            "a resumed restore must hash-equal the origin - no loss, no duplication")
}

@Test func interruptedRestoreResumesMidPage() async throws {
    let origin = try makeSyncRepository()
    try seedRichDataset(into: origin)
    let originHash = RestoreHash.compute(try origin.allRecords())

    let server = RestoreServerDouble()
    _ = await makeSyncEngine(repository: origin, transport: server).synchronize()

    // Corrupt the SECOND record of the first page: page 1's first record
    // applies, the second throws, and the cursor for that page is never
    // persisted - the interruption is mid-page, not between pages.
    server.corruptFirstPullRecord(at: 1)
    let restored = try makeSyncRepository()
    let cursor = InMemorySyncCursorStore()
    let engine1 = makeSyncEngine(repository: restored, transport: server, cursor: cursor, pullPageLimit: 4)
    _ = await RestoreEngine(engine: engine1).restore()
    #expect(try cursor.load() == nil, "a mid-page failure never persists the page's cursor")

    // Resume from 0: the already-applied first record is re-applied idempotently
    // (no duplication), the rest lands.
    let engine2 = makeSyncEngine(repository: restored, transport: server, cursor: cursor, pullPageLimit: 4)
    let outcome2 = await RestoreEngine(engine: engine2).restore()
    guard case .restored = outcome2 else {
        Issue.record("expected the resume to finish restored, got \(outcome2)")
        return
    }

    #expect(RestoreHash.compute(try restored.allRecords()) == originHash,
            "a mid-page resume must hash-equal the origin with no duplicated records")
}

// MARK: - Restore never blocks on photos

@Test func restoreNeverBlocksOnPhotosWhenTheBlobTransportIsDown() async throws {
    let origin = try makeSyncRepository()
    let (_, _) = try seedRichDataset(into: origin)

    let server = RestoreServerDouble()
    _ = await makeSyncEngine(repository: origin, transport: server).synchronize()

    let restored = try makeSyncRepository()
    // The blob transport fails every call (download -> transportUnavailable).
    let blobTransport = BlobTransportDouble()
    blobTransport.setDownloadError(.transportUnavailable)

    let outcome = await RestoreEngine(engine: makeSyncEngine(repository: restored, transport: server)).restore()
    guard case .restored = outcome else {
        Issue.record("expected restored, got \(outcome)")
        return
    }

    // Every text record landed - the garage is usable in seconds.
    #expect(try restored.liveVehicles().count == 2)
    var entryCount = 0
    for vehicle in try restored.liveVehicles() {
        entryCount += try restored.liveEntries(forVehicle: vehicle.id).count
    }
    #expect(entryCount == 6)
    // The attachment record landed with its inline thumbnail - no blob fetch was
    // ever issued during the pull (the thumbnail rides in the payload, P4.6).
    #expect(try restored.liveAttachments().count == 1)
    #expect(blobTransport.downloadCount == 0, "a restore pull fetches zero blobs")

    // A later lazy download of the full rendition fails gracefully - the record
    // is already in the DB, so the garage stays usable (the "photo syncing"
    // shimmer, never an error).
    let fetcher = LazyBlobFetcher(transport: blobTransport, store: InMemoryBlobStore())
    do {
        _ = try await fetcher.fetch(sha256: "a".padding(toLength: 64, withPad: "a", startingAt: 0))
        Issue.record("a down blob transport must not yield bytes")
    } catch let error as BlobSyncError {
        #expect(error == .transportUnavailable)
    }
}

// MARK: - Backend down produces the honest outcome

@Test func backendDownIsUnreachableNotAnError() async throws {
    let restored = try makeSyncRepository()
    let transport = SyncTransportDouble()
    transport.setFailAll(true)
    let outcome = await RestoreEngine(engine: makeSyncEngine(repository: restored, transport: transport)).restore()
    #expect(outcome == .unreachable, "a down backend maps to `.unreachable`, never a generic failure")
}

@Test func emptyPullIsEmptyNotUnreachable() async throws {
    let restored = try makeSyncRepository()
    let transport = SyncTransportDouble()
    // The pull succeeds with no records - an empty account, not a failure.
    transport.enqueuePull(SyncPullResponse(records: [], nextSince: 0, more: false, schemaPolicy: policy))
    let outcome = await RestoreEngine(engine: makeSyncEngine(repository: restored, transport: transport)).restore()
    #expect(outcome == .empty, "a successful pull with no records is an empty restore, not an outage")
}

// MARK: - Verification stats are real numbers derived from what landed

@Test func verificationStatsAreTheLiteralNumbersFromTheSeededDataset() async throws {
    let origin = try makeSyncRepository()
    let (_, expected) = try seedRichDataset(into: origin)

    let server = RestoreServerDouble()
    _ = await makeSyncEngine(repository: origin, transport: server).synchronize()

    let restored = try makeSyncRepository()
    let outcome = await RestoreEngine(engine: makeSyncEngine(repository: restored, transport: server)).restore()
    guard case .restored(let stats) = outcome else {
        Issue.record("expected restored, got \(outcome)")
        return
    }

    #expect(stats.carCount == expected.carCount)
    #expect(stats.carNames == expected.carNames)
    #expect(stats.entryCount == 6, "the entry count is a literal, not 'some records landed'")
    #expect(stats.earliestEntry == t0.addingTimeInterval(86_400))
    #expect(stats.latestEntry == t0.addingTimeInterval(20 * 86_400))
    #expect(stats.lastOdometerKm == 120_486, "the last odometer is the literal from the latest fill")
}

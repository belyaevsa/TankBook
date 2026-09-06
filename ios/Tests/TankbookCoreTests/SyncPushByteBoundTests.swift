import Foundation
import Testing
@testable import TankbookCore

// RV.97 - the push batch is bounded by ENCODED BYTES as well as by record
// count. `batchLimit` counts records, so 200 records of imported history made
// an unbounded ~150 KB body that outlived the push request's upload budget and
// was rebuilt identically every cycle. These tests pin the second bound:
// batches split when the encoded request body (`SyncPushWire.wireBytes` - the
// exact bytes `RemoteSyncTransport` puts on the wire) would exceed
// `SyncEngine.maxBatchBytes`, every record lands exactly once, and a single
// record bigger than the cap still ships alone rather than being dropped
// (hard rule 8).

private let byteBoundT0 = Date(timeIntervalSinceReferenceDate: 0)

private func makeByteBoundFillUp(id: UUID, vehicleId: UUID, index: Int,
                                 note: String) -> FillUp {
    makeSyncFillUp(id: id, vehicleId: vehicleId,
                   date: byteBoundT0.addingTimeInterval(Double(index) * 86_400),
                   odometer: 1000 + index, note: note)
}

@Suite("Sync push batch byte bound (RV.97)")
struct SyncPushByteBoundTests {

    @Test("a dirty set whose encoded size exceeds the cap splits into several pushes, each under the cap, every record exactly once")
    func sizeBoundSplitsAnOversizedBatch() async throws {
        // The SIZE bound must bind while the 200-record bound does not: 16 rows
        // (well under batchLimit) whose ~8 KB notes each make the total ~140 KB
        // of encoded body - the observed production livelock body was ~150 KB.
        let repo = try makeSyncRepository()
        let vehicleId = UUID.v7()
        try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))
        let note = String(repeating: "x", count: 8_000)
        var expected = Set<UUID>()
        for index in 0 ..< 16 {
            let id = UUID.v7()
            expected.insert(id)
            try repo.upsertFillUp(makeByteBoundFillUp(id: id, vehicleId: vehicleId,
                                                      index: index, note: note))
        }

        let transport = SyncTransportDouble()
        let engine = makeSyncEngine(repository: repo, transport: transport)
        _ = await engine.synchronize()

        let batches = transport.recordedPushBatches
        #expect(batches.count >= 2, "an oversized dirty set must split into several pushes")
        var pushedIds = Set<UUID>()
        for batch in batches {
            #expect(!batch.isEmpty, "never an empty batch")
            let encodedBytes = SyncPushWire.wireBytes(for: batch)
            #expect(encodedBytes <= SyncEngine.defaultMaxBatchBytes,
                    "each batch must fit the byte cap; this one is \(encodedBytes) bytes")
            pushedIds.formUnion(batch.map(\.id))
        }
        #expect(pushedIds == expected, "every record lands exactly once")
        #expect(try repo.fetchDirtyRows().isEmpty, "the queue drains - nothing is lost")
    }

    @Test("the count bound still binds first when records are small")
    func countBoundBindsFirstForSmallRecords() async throws {
        // The counterpart fixture: a byte cap wide enough that it can never bind
        // over 205 fillUps, so the 200-record bound is what splits - both bounds
        // stay live (the split fixture above drives the byte bound alone).
        let repo = try makeSyncRepository()
        let vehicleId = UUID.v7()
        try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))
        let total = 200 + 5
        var expected = Set<UUID>()
        for index in 0 ..< total {
            let id = UUID.v7()
            expected.insert(id)
            try repo.upsertFillUp(makeByteBoundFillUp(id: id, vehicleId: vehicleId,
                                                      index: index, note: "tiny"))
        }

        let transport = SyncTransportDouble()
        let engine = SyncEngine(
            repository: repo,
            transport: transport,
            cursorStore: InMemorySyncCursorStore(),
            maxBatchBytes: 16 * 1024 * 1024)
        _ = await engine.synchronize()

        let batches = transport.recordedPushBatches
        #expect(batches.count == 2, "the count bound splits \(total) rows into 200 + \(total - 200)")
        #expect(batches[0].count == 200)
        #expect(batches[1].count == total - 200)
        for batch in batches {
            #expect(SyncPushWire.wireBytes(for: batch) <= 16 * 1024 * 1024)
        }
        let pushedIds = Set(batches.flatMap { $0.map(\.id) })
        #expect(pushedIds == expected)
    }

    @Test("a single record larger than the cap still ships, in a batch of its own")
    func singleOversizeRecordShipsAlone() async throws {
        // The record cannot be pushed whole with anything else, and a record that
        // cannot be pushed is a record lost silently (hard rule 8) - so it must
        // ship alone, never be skipped and never be deferred forever.
        let repo = try makeSyncRepository()
        let vehicleId = UUID.v7()
        try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))
        let smallId = UUID.v7()
        try repo.upsertFillUp(makeByteBoundFillUp(id: smallId, vehicleId: vehicleId,
                                                  index: 0, note: "small"))
        let bigId = UUID.v7()
        let bigNote = String(repeating: "x", count: 70_000)
        try repo.upsertFillUp(makeByteBoundFillUp(id: bigId, vehicleId: vehicleId,
                                                  index: 1, note: bigNote))
        let expected = Set([smallId, bigId])

        let transport = SyncTransportDouble()
        let engine = makeSyncEngine(repository: repo, transport: transport)
        let outcome = await engine.synchronize()

        #expect(outcome.pushed == 2, "both rows push - the oversize one is not dropped")
        let batches = transport.recordedPushBatches
        #expect(batches.count == 2, "the oversize record ships in a batch of its own")
        let pushedIds = Set(batches.flatMap { $0.map(\.id) })
        #expect(pushedIds == expected)
        #expect(batches.contains { $0.count == 1 && $0[0].id == bigId },
                "the oversize record is in a one-record batch, alone")
        #expect(try repo.fetchDirtyRows().isEmpty, "nothing is left dirty forever")
    }
}

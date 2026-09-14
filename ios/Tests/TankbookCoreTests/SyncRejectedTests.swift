import Foundation
import Testing
@testable import TankbookCore

// RV.284: a push result of `.rejected` is TERMINAL for that payload, not a
// transient failure. The server refused the bytes structurally, so re-pushing
// them unchanged is a loop that never ends (the production log: two fillUps
// rejected on every push, twice a minute). The engine marks the row `rejected`,
// leaves it out of the next cycle's push batch, and counts it in the summary;
// only an edit (which re-dirties the row) or a new app build (a different
// payload) puts it back on the wire.

@Suite struct SyncRejectedTests {
    private func makeRejectedFillUp() throws -> (TankbookRepository, FillUp, SyncTransportDouble) {
        let repo = try makeSyncRepository()
        let vehicle = makeSyncVehicle()
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        let fill = makeSyncFillUp(vehicleId: vehicle.id)
        try repo.upsertFillUp(fill)
        return (repo, fill, SyncTransportDouble())
    }

    @Test func rejectedPushMarksTheRowRejectedAndTheSummaryCountsIt() async throws {
        let (repo, fill, transport) = try makeRejectedFillUp()
        transport.enqueuePush(SyncPushResponse(results: [
            SyncPushResult(id: fill.id, status: .rejected(code: "payload_schema_violation",
                                                         pointer: "/conflict/kind")),
        ]))
        let engine = makeSyncEngine(repository: repo, transport: transport)

        let outcome = await engine.synchronize()

        #expect(outcome.rejected == 1)
        #expect(outcome.pushed == 0)
        guard let local = try repo.localSyncRecord(id: fill.id, entityType: FillUp.entityType) else {
            Issue.record("the row must still exist locally")
            return
        }
        if case .rejected = local.syncState {} else {
            Issue.record("the row must be marked rejected, not \(local.syncState)")
        }
        #expect(try repo.rejectedEntryCount() == 1)
        #expect(try repo.fetchDirtyRows().isEmpty, "a rejected row is not dirty, so it stops re-pushing")
    }

    @Test func rejectedRowDoesNotPushAgainUntilEdited() async throws {
        let (repo, fill, transport) = try makeRejectedFillUp()
        transport.enqueuePush(SyncPushResponse(results: [
            SyncPushResult(id: fill.id, status: .rejected(code: "payload_schema_violation",
                                                         pointer: "/conflict/kind")),
        ]))
        let engine = makeSyncEngine(repository: repo, transport: transport)

        _ = await engine.synchronize()
        #expect(transport.recordedPushBatches.count == 1)

        // A second cycle must not contain the rejected row.
        _ = await engine.synchronize()
        #expect(transport.recordedPushBatches.count == 1, "no second push batch for an unchanged rejected row")

        // Editing the entry re-dirties it, and it pushes again.
        var edited = fill
        edited.note = "edited"
        edited.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        try repo.upsertFillUp(edited)
        guard let local = try repo.localSyncRecord(id: fill.id, entityType: FillUp.entityType) else {
            Issue.record("the row must still exist locally")
            return
        }
        #expect(local.syncState == .dirty, "an edit re-dirties the rejected row")

        _ = await engine.synchronize()
        #expect(transport.recordedPushBatches.count == 2, "the edited row pushes again")
        #expect(try repo.rejectedEntryCount() == 0)
    }
}

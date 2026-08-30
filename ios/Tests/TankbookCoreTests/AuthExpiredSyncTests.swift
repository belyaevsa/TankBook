import Foundation
import Testing
@testable import TankbookCore

// PR.1 - an expired session is an auth outcome that leaves the queue intact
// (S7, hard rule 8): the sync engine surfaces `authExpired` and every dirty row
// stays dirty, so nothing is lost and the user re-signs in to resume.

@Suite("Auth-expired sync outcome (PR.1)")
struct AuthExpiredSyncTests {

    @Test func anExpiredSessionSetsAuthExpiredAndLeavesDirtyRowsDirty() async throws {
        let repository = try makeSyncRepository()
        let vehicle = makeSyncVehicle()
        try repository.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        let fill = makeSyncFillUp(vehicleId: vehicle.id)
        try repository.upsertFillUp(fill, syncState: .dirty)

        let transport = SyncTransportDouble()
        transport.enqueuePullError(.authExpired)
        let engine = makeSyncEngine(repository: repository, transport: transport)

        let outcome = await engine.synchronize()

        #expect(outcome.authExpired, "a rejected refresh surfaces as authExpired, not an outage")
        #expect(!outcome.offline && !outcome.serverUnavailable)
        #expect(!outcome.deviceRevoked)

        let dirty = try repository.fetchDirtyRows()
        #expect(dirty.count == 1, "the queue is untouched - nothing is lost (S7)")
        #expect(dirty.first?.id == fill.id)
    }
}

import Foundation
import Testing
@testable import TankbookCore

// The S5 return notice (docs/SYNC.md S5, docs/SCHEMA.md -> The S5 return
// notice): the resurrect writes it, "Delete again" tombstones and consumes it,
// "Keep" only consumes it. The notice is what the Garage/Home card renders, so
// a resurrection that wrote no row would be a car that came back silently -
// exactly what hard rule 8 forbids.

private let t0 = Date(timeIntervalSinceReferenceDate: 0)
private let policy = SyncSchemaPolicy(minSupported: 1, current: 1)

@Suite("S5 return notice")
struct VehicleReturnNoticeTests {

    private func deletedVehicle(in repo: TankbookRepository) throws -> UUID {
        let id = UUID.v7()
        try repo.upsertVehicle(makeSyncVehicle(id: id), syncState: .synced(scn: 1))
        try repo.softDeleteVehicle(id: id)
        return id
    }

    @Test func theResurrectWritesTheNoticeAndCountsEveryArrivingEntry() throws {
        let repo = try makeSyncRepository()
        let id = try deletedVehicle(in: repo)

        try repo.resurrectArchivedIfTombstoned(vehicleId: id)
        var notices = try repo.vehicleReturnNotices()
        #expect(notices.map(\.vehicleId) == [id], "the resurrection opens the notice")
        #expect(notices.first?.entryCount == 1)

        // A second arriving entry finds the car live - it raises the count on
        // the SAME notice rather than opening a second card.
        try repo.resurrectArchivedIfTombstoned(vehicleId: id)
        notices = try repo.vehicleReturnNotices()
        #expect(notices.count == 1)
        #expect(notices.first?.entryCount == 2, "N entries are one notice with a count")
    }

    @Test func aLiveCarWithNoNoticeIsNeverNoticed() throws {
        let repo = try makeSyncRepository()
        let id = UUID.v7()
        try repo.upsertVehicle(makeSyncVehicle(id: id), syncState: .synced(scn: 1))

        // The pull path calls this for every touched vehicle; a car that was
        // never deleted must not grow a "came back" card.
        try repo.resurrectArchivedIfTombstoned(vehicleId: id)
        #expect(try repo.vehicleReturnNotices().isEmpty)
    }

    @Test func deleteAgainTombstonesTheCarDirtyAndConsumesTheNotice() throws {
        let repo = try makeSyncRepository()
        let id = try deletedVehicle(in: repo)
        try repo.resurrectArchivedIfTombstoned(vehicleId: id)
        try repo.upsertFillUp(makeSyncFillUp(id: UUID.v7(), vehicleId: id, date: t0, odometer: 121_000),
                              syncState: .synced(scn: 2))

        try repo.deleteReturnedVehicleAgain(id: id)

        let vehicle = try repo.vehicle(id: id)
        #expect(vehicle?.deletedAt != nil, "the car goes back where the user put it")
        let local = try repo.localSyncRecord(id: id, entityType: Vehicle.entityType)
        #expect(local?.syncState == .dirty, "the second tombstone pushes")
        #expect(try repo.liveFillUps(forVehicle: id).isEmpty, "its rows are tombstoned with it")
        #expect(try repo.rowCount(in: TankbookSchema.fillUp) == 1, "...not purged - the undo window holds them")
        #expect(try repo.vehicleReturnNotices().isEmpty, "the notice is answered")
    }

    @Test func keepConsumesOnlyTheNotice() throws {
        let repo = try makeSyncRepository()
        let id = try deletedVehicle(in: repo)
        try repo.resurrectArchivedIfTombstoned(vehicleId: id)

        try repo.keepReturnedVehicle(id: id)

        let vehicle = try repo.vehicle(id: id)
        #expect(vehicle?.deletedAt == nil, "the car stays")
        #expect(vehicle?.archived == true, "...archived, as it came back")
        #expect(try repo.vehicleReturnNotices().isEmpty)
    }

    /// The S5 pull itself (not the repository seam) leaves the notice behind:
    /// the engine's resurrect is the only writer, so the L3 scenario proves the
    /// card has data on the device that pulled the entry.
    @Test func theS5PullLeavesTheNoticeForTheCard() async throws {
        let repo = try makeSyncRepository()
        let id = try deletedVehicle(in: repo)
        let transport = SyncTransportDouble()
        transport.enqueuePull(SyncPullResponse(
            records: [makePullRecord(makeSyncFillUp(id: UUID.v7(), vehicleId: id,
                                                    date: t0.addingTimeInterval(86_400), odometer: 121_000),
                                     scn: 2)],
            nextSince: 2, more: false, schemaPolicy: policy))
        _ = await makeSyncEngine(repository: repo, transport: transport).synchronize()

        let notices = try repo.vehicleReturnNotices()
        #expect(notices.map(\.vehicleId) == [id])
        #expect(notices.first?.entryCount == 1)
    }
}

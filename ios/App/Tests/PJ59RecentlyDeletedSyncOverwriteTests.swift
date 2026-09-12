import Foundation
import TankbookCore
import XCTest
@testable import Tankbook

/// PJ.59: Recently deleted's "Overwritten by sync" section renders the REAL
/// `syncOverwrite` undo log, not a launch-argument fixture. The L1 goes through
/// the real S8 merge path (a pulled record that wins record-level LWW over a
/// local dirty edit) and then the section's own presenter, so the writer and
/// the reader are exercised together. `docs/SYNC.md` S1/S4 is the contract:
/// `SyncEngine.applyPull` records the losing version, and the section reads it.
@MainActor
final class PJ59RecentlyDeletedSyncOverwriteTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    // MARK: - The real S8 path -> the section's rows

    /// An entry overwritten by a real sync merge appears in Recently deleted's
    /// overwritten section with the LOSING (user's) version. Fails if the
    /// section reads anything but the repository's undo log.
    func testEntryOverwrittenByTheRealMergeAppearsInTheSection() async throws {
        let repo = try TankbookRepository(database: try TankbookDatabase.inMemory())
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))

        // The iPhone's local edit (odometer 121 400), dirty - it will lose.
        let fillUpId = UUID.v7()
        let localEdit = makeFillUp(id: fillUpId, vehicleId: vehicle.id, odometer: 121_400,
                                   updatedAt: t0.addingTimeInterval(1))
        try repo.upsertFillUp(localEdit, syncState: .dirty)

        // The iPad's newer edit (odometer 121 500) arrives on the wire.
        let remoteEdit = makeFillUp(id: fillUpId, vehicleId: vehicle.id, odometer: 121_500,
                                    updatedAt: t0.addingTimeInterval(2))
        var pull = SyncPullRecord(
            id: remoteEdit.id, entityType: FillUp.entityType,
            schemaVersion: PayloadCodec.currentSchemaVersion, scn: 2,
            payload: try PayloadCodec.encode(remoteEdit).payload,
            clientUpdatedAt: remoteEdit.updatedAt, deleted: false)
        pull.originDeviceName = "iPad"
        let transport = OnePullTransport(SyncPullResponse(
            records: [pull], nextSince: 2, more: false,
            schemaPolicy: SyncSchemaPolicy(minSupported: 1, current: 1)))

        _ = await SyncEngine(repository: repo, transport: transport,
                             cursorStore: InMemorySyncCursorStore()).synchronize()

        // The writer: the merge kept the losing version (hard rule 8).
        XCTAssertEqual(try repo.syncOverwrittenEntries().count, 1,
                       "the real S8 merge records the overwritten edit")

        // The reader: the section's presenter turns that log into a row.
        let rows = try RecentlyDeletedSyncOverwrites.rows(from: repo)
        XCTAssertEqual(rows.count, 1, "the overwritten entry appears in the section")
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.recordId, fillUpId)
        XCTAssertEqual(row.deviceName, "iPad", "the winning device is attributed, not invented")
        let losing = try XCTUnwrap(row.entry as? FillUp)
        XCTAssertEqual(losing.odometer, 121_400,
                       "the section shows the user's LOSING version, not the winner")
    }

    /// With nothing overwritten the section is empty - it does not exist. This
    /// is the honest empty state, and it fails if the presenter fabricates rows.
    func testNoOverwriteMeansNoSectionRows() throws {
        let repo = try TankbookRepository(database: try TankbookDatabase.inMemory())
        try repo.upsertVehicle(makeVehicle(), syncState: .synced(scn: 1))

        XCTAssertTrue(try RecentlyDeletedSyncOverwrites.rows(from: repo).isEmpty,
                      "no log row means no section")
    }

    // MARK: - Builders

    private func makeVehicle() -> Vehicle {
        Vehicle(id: UUID.v7(), createdAt: t0, updatedAt: t0, deletedAt: nil,
                name: "Volvo V60", make: "Volvo", model: "V60", year: 2015, plate: nil,
                powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: 71,
                batteryCapacityKWh: nil, homeCurrency: .eur,
                units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                     energy: .kWhPer100),
                photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 118_000)
    }

    private func makeFillUp(id: UUID, vehicleId: UUID, odometer: Int,
                            updatedAt: Date) -> FillUp {
        FillUp(id: id, createdAt: t0, updatedAt: updatedAt, deletedAt: nil,
               vehicleId: vehicleId, date: t0, odometer: odometer,
               money: Money(amount: Decimal(string: "71.02")!, currency: .eur,
                            homeCurrency: .eur),
               note: nil, attachments: [], provenance: .manual, conflict: .none,
               purchaseGroupId: nil, volumeL: 42.3, unitPrice: Decimal(string: "1.679")!,
               fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
               stationId: nil, crossCheck: .verified, extraction: nil)
    }
}

/// A minimal `SyncTransport`: answers every pull with the one scripted response
/// and accepts every push. Enough to drive the real merge path without the
/// core test target's doubles (which are not visible to the app bundle).
private final class OnePullTransport: SyncTransport, @unchecked Sendable {
    private let response: SyncPullResponse

    init(_ response: SyncPullResponse) {
        self.response = response
    }

    func pull(since: Int64, limit: Int) async throws -> SyncPullResponse {
        response
    }

    func push(_ changes: [SyncPushChange]) async throws -> SyncPushResponse {
        SyncPushResponse(results: changes.map {
            SyncPushResult(id: $0.id, status: .accepted(newScn: 99, clamped: false))
        })
    }
}

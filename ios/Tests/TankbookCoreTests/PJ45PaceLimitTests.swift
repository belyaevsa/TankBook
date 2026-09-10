import Testing
import Foundation
@testable import TankbookCore

// PJ.45: `paceLimitKmPerDay` is an input to CHECK 2, so editing it on Vehicle
// detail must re-derive the stored flags from the entries and the new limit -
// no entry is re-saved. The row's own trap is "a setting that changes nothing
// visible" (the Station.favorite shape, PJ.55); these pin that the edit lands
// and that a raised limit clears a flag that only existed under the old one.

@Suite("PJ.45 editable pace limit")
struct PJ45PaceLimitTests {
    private static let day: TimeInterval = 86_400
    private static let epoch = Date(timeIntervalSince1970: 1_752_451_200)

    @Test func raisingTheLimitClearsAFlagThatOnlyExistedUnderTheOldOne() throws {
        let repository = try makeSyncRepository()
        let vehicle = makeSyncVehicle(paceLimitKmPerDay: 100)
        try repository.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        // 200 km in one day: flagged under the 100 limit, clean under 500.
        let first = makeSyncFillUp(vehicleId: vehicle.id, date: Self.epoch, odometer: 100_000)
        let second = makeSyncFillUp(vehicleId: vehicle.id, date: Self.epoch + Self.day,
                                    odometer: 100_200)
        try repository.upsertFillUp(first, syncState: .synced(scn: 2))
        try repository.upsertFillUp(second, syncState: .synced(scn: 3))

        #expect(try repository.revalidateTimeline(vehicleIds: [vehicle.id]) == 2,
                "200 km/day flags both entries under a 100 km/day limit")

        // The edit Vehicle detail's Save makes: the same entries, a higher limit.
        var raised = vehicle
        raised.paceLimitKmPerDay = 500
        try repository.upsertVehicle(raised)

        #expect(try repository.revalidateTimeline(vehicleIds: [vehicle.id]) == 0)
        #expect(try repository.liveFillUps(forVehicle: vehicle.id)
            .allSatisfy { $0.conflict == .none },
            "a raised limit clears the flags the old limit produced, without re-saving entries")
        #expect(try repository.vehicle(id: vehicle.id)?.paceLimitKmPerDay == 500,
                "the edited limit is the car's own value and persists")
    }

    @Test func loweringTheLimitFlagsAnEntryThatWasCleanUnderTheOldOne() throws {
        // The other direction, so the test cannot pass by the limit being
        // ignored: the same entries flag once the bound is lowered under them.
        let repository = try makeSyncRepository()
        let vehicle = makeSyncVehicle(paceLimitKmPerDay: 500)
        try repository.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        let first = makeSyncFillUp(vehicleId: vehicle.id, date: Self.epoch, odometer: 100_000)
        let second = makeSyncFillUp(vehicleId: vehicle.id, date: Self.epoch + Self.day,
                                    odometer: 100_200)
        try repository.upsertFillUp(first, syncState: .synced(scn: 2))
        try repository.upsertFillUp(second, syncState: .synced(scn: 3))
        #expect(try repository.revalidateTimeline(vehicleIds: [vehicle.id]) == 0)

        var lowered = vehicle
        lowered.paceLimitKmPerDay = 100
        try repository.upsertVehicle(lowered)
        #expect(try repository.revalidateTimeline(vehicleIds: [vehicle.id]) == 2)
    }

    @Test func sameDayPairStaysCleanThroughTheRepositoryPath() throws {
        // RV.192 through the write path: the same-day pair the owner reported
        // must not flag, even at a low limit.
        let repository = try makeSyncRepository()
        let vehicle = makeSyncVehicle(paceLimitKmPerDay: 100)
        try repository.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        let morning = makeSyncFillUp(vehicleId: vehicle.id,
                                     date: Self.epoch + 9 * 3_600, odometer: 100_000)
        let evening = makeSyncFillUp(vehicleId: vehicle.id,
                                     date: Self.epoch + 18 * 3_600, odometer: 100_300)
        try repository.upsertFillUp(morning, syncState: .synced(scn: 2))
        try repository.upsertFillUp(evening, syncState: .synced(scn: 3))

        #expect(try repository.revalidateTimeline(vehicleIds: [vehicle.id]) == 0)
        #expect(try repository.liveFillUps(forVehicle: vehicle.id)
            .allSatisfy { $0.conflict == .none })
    }
}

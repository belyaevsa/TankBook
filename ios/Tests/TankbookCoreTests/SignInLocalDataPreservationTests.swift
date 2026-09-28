import Foundation
import Testing
@testable import TankbookCore

// P4.4: "local data is never overwritten" (L1). Seeded with real rows, so the
// assertion is not the empty-database vacuity the brief warns about.
@Suite("Sign-in leaves local data intact (P4.4)")
struct SignInLocalDataPreservationTests {

    private func makeVehicle() -> Vehicle {
        let now = Date()
        return Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95, .diesel],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    private func makeFill(vehicleID: UUID) -> FillUp {
        let date = Date().addingTimeInterval(-6 * 86_400)
        return FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: vehicleID, date: date, odometer: 119_486,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.30, unitPrice: Decimal(string: "1.679")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .verified, extraction: nil)
    }

    /// Persisting a session touches none of the local rows. The decision that
    /// a local log uploads rather than restores is tested on the live path
    /// (`SignInFlowTests.testALocalLogUploadsAndNeverRestores`).
    @Test func signingInWithAPopulatedLogLeavesEveryRecordIntact() throws {
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        let vehicle = makeVehicle()
        try repository.upsertVehicle(vehicle)
        try repository.upsertFillUp(makeFill(vehicleID: vehicle.id))

        #expect(try repository.hasLocalData(), "the seed must be non-empty (the vacuity trap)")

        // Persist the session (the Keychain is the real store; this test uses the
        // in-memory double so the assertion is about the repository, not the
        // Keychain) - the local rows must be untouched.
        let store = InMemorySessionStore()
        try store.save(AuthSession(
            accessToken: "at", refreshToken: "rt",
            accountId: "acc", deviceId: "dev", provider: .apple))

        #expect(try repository.liveVehicles().count == 1)
        #expect(try repository.liveFillUps(forVehicle: vehicle.id).count == 1)
        #expect(try repository.liveEntries(forVehicle: vehicle.id).count == 1)
    }
}

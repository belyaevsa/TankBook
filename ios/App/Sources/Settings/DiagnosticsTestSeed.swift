#if DEBUG
import Foundation
import TankbookCore

/// UI-test/screenshot DB seeding for the About diagnostics row (OB.4): the same
/// launch-argument hook pattern as `HomeTestSeed`. `-seedDiagnosticsData` writes
/// one car, one station and one fill holding deliberately DISTINCTIVE values
/// (the L4 preview privacy test sweeps for exactly these - a preview over an
/// empty database proves nothing), and `-seedDiagnosticsSync` plants the
/// persisted sync state (OB.3) so the bundle's sync section has real content.
/// The consent flag itself is handled by `DiagnosticsService.makeModel`.
enum DiagnosticsTestSeed {
    static let stationName = "Zvezda-Lubricants-77"
    static let note = "timing-belt-service-ob4"
    static let amount = "64.20"

    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-seedDiagnosticsData") || arguments.contains("-seedDiagnosticsSync")
            || arguments.contains("-homeResetDatabase") else { return }
        if arguments.contains("-homeResetDatabase") {
            AppStore.resetForTestsOncePerLaunch()
        }
        guard let repository = try? AppStore.repository() else { return }
        if arguments.contains("-seedDiagnosticsData") {
            seedData(repository)
        }
        if arguments.contains("-seedDiagnosticsSync") {
            seedSyncState()
        }
    }

    /// One car, one station, one fill with the sweep's needles. Guarded so a
    /// second launch in the same run (or another seed's vehicle) never doubles
    /// the rows the preview's row counts must show exactly.
    @MainActor
    private static func seedData(_ repository: TankbookRepository) {
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }
        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "OB4 Fixture Car", make: "Volvo", model: "V60", year: 2019,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil)
        try? repository.upsertVehicle(vehicle)
        let station = Station(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: stationName, brand: nil, location: nil, favorite: true,
            defaults: Station.Defaults(fuelKind: .petrol95, fuelGrade: nil))
        try? repository.upsertStation(station)
        let fill = FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 119_486,
            money: Money(amount: Decimal(string: amount)!, currency: .eur, homeCurrency: .eur),
            note: note, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.3, unitPrice: Decimal(string: "1.529")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: station.id, crossCheck: .verified, extraction: nil)
        try? repository.upsertFillUp(fill)
    }

    /// Plants the persisted sync state the preview reads (OB.3): a success three
    /// hours back and a failure holding kind + code + traceId, so the bundle's
    /// sync section renders real content and the screenshot shows what support
    /// would actually see. The store is keyed by account id (RV.256), so this
    /// also plants the stub session the bundle's read needs - the sync section
    /// is empty for a guest, who has no state to export.
    private static func seedSyncState() {
        let sessionStore = KeychainSessionStore()
        if (try? sessionStore.load()) == nil {
            try? sessionStore.save(SettingsTestSeed.stubSession())
        }
        guard let accountId = (try? sessionStore.load())?.accountId else { return }
        UserDefaultsSyncStateStore(accountId: accountId).save(PersistedSyncState(
            lastSuccessAt: Date().addingTimeInterval(-3 * 3600),
            lastFailure: SyncFailureRecord(at: Date().addingTimeInterval(-3600),
                                           kind: .upgradeRequired,
                                           code: "upgrade_required",
                                           traceId: "ob4-screenshot-0001")))
    }
}
#endif

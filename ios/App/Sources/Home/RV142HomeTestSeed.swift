#if DEBUG
import Foundation
import TankbookCore

/// RV.142's deterministic Log states (screenshots + UI tests). Two seeds share
/// the same Drivvo-flavoured diesel history; they differ in the car's fuel set.
///
/// `-seedHomeRV142Log` is the owner's screenshot state: a single-fuel diesel
/// car whose imported rows read `Газпром` (or `Neste`) as the title where the
/// file carried a station, `Diesel` where it did not, and each closing fill's
/// consumption on the row. No fuel kind repeats anywhere (a diesel-only car
/// printing "Diesel" beside a Diesel title was the reported defect).
///
/// `-seedHomeRV142KindRepeat` is the L4 duplicate state: a TWO-fuel car
/// (diesel + petrol, so the kind genuinely earns its subtitle place on a
/// station-titled row - docs/DESIGN.md) whose station-less rows title
/// themselves with the fuel kind. Those rows must NEVER repeat the kind in the
/// subtitle; the station-titled rows may show it.
enum RV142HomeTestSeed {

    /// Row shape: when the file's station column was blank the row stays
    /// station-less and the Log falls back to the fuel kind for its title.
    private struct RowSpec {
        let daysAgo: Int
        let odometer: Int
        let litres: Double
        let stationName: String?
    }

    private static let logRows: [RowSpec] = [
        RowSpec(daysAgo: 0, odometer: 375_963, litres: 53.0, stationName: nil),
        RowSpec(daysAgo: 1, odometer: 375_340, litres: 49.5, stationName: "Газпром"),
        RowSpec(daysAgo: 2, odometer: 374_720, litres: 55.0, stationName: "Газпром"),
        RowSpec(daysAgo: 3, odometer: 374_080, litres: 47.2, stationName: nil),
        RowSpec(daysAgo: 4, odometer: 373_460, litres: 51.8, stationName: "Neste")
    ]

    static func seedLog(_ repository: TankbookRepository) {
        seed(repository, rows: logRows, fillKind: .diesel, fuelKinds: [.diesel])
    }

    static func seedKindRepeat(_ repository: TankbookRepository) {
        // A physically real two-fuel set (petrol + LPG, the seedHomeFullHistory
        // shape - docs/DESIGN.md). The kind earns its subtitle place on a
        // station-titled row, so the station-less rows' suppression is the
        // measurable half of the RV.142 fix.
        seed(repository, rows: logRows, fillKind: .petrol95, fuelKinds: [.petrol95, .lpg])
    }

    private static func seed(_ repository: TankbookRepository,
                             rows: [RowSpec],
                             fillKind: FuelKind,
                             fuelKinds: [FuelKind]) {
        let vehicle = makeVehicle(fuelKinds: fuelKinds)
        try? repository.upsertVehicle(vehicle)
        let gazprom = makeStation(repository, name: "Газпром")
        let neste = makeStation(repository, name: "Neste")

        for row in rows {
            let date = Date().addingTimeInterval(-Double(row.daysAgo) * 86_400)
            let stationID: UUID? = switch row.stationName {
            case "Газпром": gazprom.id
            case "Neste": neste.id
            default: nil
            }
            let money = Money(amount: unitAmount(row), currency: .eur, homeCurrency: .eur)
            try? repository.upsertFillUp(FillUp(
                id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
                vehicleId: vehicle.id, date: date, odometer: row.odometer,
                money: money, note: nil, attachments: [],
                provenance: .import(source: "drivvo"), conflict: .none,
                purchaseGroupId: nil, volumeL: row.litres,
                unitPrice: Decimal(string: "1.60"), fuelKind: fillKind,
                fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
                stationId: stationID, crossCheck: .verified, extraction: nil))
        }
    }

    private static func unitAmount(_ row: RowSpec) -> Decimal {
        Decimal(row.litres) * Decimal(string: "1.60")!
    }

    private static func makeVehicle(fuelKinds: [FuelKind]) -> Vehicle {
        let now = Date()
        return Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Škoda Octavia", make: "Škoda", model: "Octavia", year: 2020,
            plate: nil, powertrain: .ice, fuelKinds: fuelKinds,
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 375_000)
    }

    private static func makeStation(_ repository: TankbookRepository, name: String) -> Station {
        let now = Date()
        let station = Station(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: name, brand: nil, location: nil, favorite: true,
            defaults: Station.Defaults(fuelKind: .diesel, fuelGrade: nil),
            lastUsedAt: now)
        try? repository.upsertStation(station)
        return station
    }
}
#endif

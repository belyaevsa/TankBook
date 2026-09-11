import Foundation
import Testing
@testable import TankbookCore

// RV.221 - F6b promises the review row renders "date, station, litres, price,
// total, odometer, note", but the station was rendered nowhere: it was carried
// end to end and only appeared in the Log after the commit, so a wrong mapping
// could not be caught while reviewing. These tests pin the name onto the review
// row; the L4 test pins it to the screen.

@Suite("RV.221 the review row carries the station name")
struct RV221ImportStationReviewTests {

    private static let longName = "Газпромнефть на Ленинградском проспекте, 63"

    private static let vehicle = Vehicle(
        id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
        name: "Volvo V60", make: "Volvo", model: "V60", year: 2015, plate: nil,
        powertrain: .ice, fuelKinds: [.petrol92], tankCapacityL: 60,
        batteryCapacityKWh: nil, homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                             energy: .kWhPer100),
        photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 0)

    private static func fill(station: String?) -> ImportCandidate {
        ImportCandidate(
            entityType: "fillUp",
            date: Date(timeIntervalSince1970: 1_786_924_800),
            odometer: nil, volumeL: 40, unitPrice: "220",
            money: ImportMoney(amount: "8800", currency: "EUR"),
            fuelKind: "petrol92", isFull: true, tankLevelAfterPct: nil, note: nil,
            vehicleName: "Volvo", provenance: ImportProvenance(tag: "import", source: "drivvo"),
            sourceRow: 1, station: station)
    }

    /// The file's station name rides onto the review row, so the screen can
    /// render the name the fill will resolve to before the commit.
    @Test func aStationNamedFillCarriesItsNameOntoTheReviewRow() throws {
        let (ready, review) = ImportReviewClassifier.partition(
            candidates: [Self.fill(station: Self.longName)],
            unparsed: [], rawLinesByRow: [:], vehicle: Self.vehicle, source: "drivvo")

        #expect(ready.isEmpty)
        let row = try #require(review.first)
        #expect(row.kind == .missingOdometer)
        #expect(row.stationName == Self.longName,
                "the review row must carry the file's station name, not just the fill's id")
    }

    /// A fill whose file named no station carries no name - an honest absence,
    /// never a guessed or empty one (hard rule 13).
    @Test func aFillWithNoStationCarriesNoName() throws {
        let (_, review) = ImportReviewClassifier.partition(
            candidates: [Self.fill(station: nil)],
            unparsed: [], rawLinesByRow: [:], vehicle: Self.vehicle, source: "drivvo")

        let row = try #require(review.first)
        #expect(row.stationName == nil)
    }
}

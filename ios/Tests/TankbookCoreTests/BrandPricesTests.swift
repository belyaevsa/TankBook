import Testing
import Foundation
@testable import TankbookCore

/// Price per unit by station brand (docs/JOURNEYS.md J8). The properties: a
/// brand needs two fills to show, the comparison needs two brands, a fill
/// with no station or no home price never counts, and the sentence is the
/// dearest against the cheapest at a whole percent.
struct BrandPricesTests {

    private static let asOf = Date(timeIntervalSince1970: 1_752_000_000)
    private static let day: TimeInterval = 86_400

    private static func station(name: String, brand: String? = nil) -> Station {
        Station(id: UUID.v7(), createdAt: asOf, updatedAt: asOf, deletedAt: nil,
                name: name, brand: brand, location: nil, favorite: false,
                defaults: Station.Defaults(fuelKind: .petrol95, fuelGrade: nil), lastUsedAt: nil)
    }

    /// A foreign `currency` with no snapshot is rate-pending: its home price
    /// is unknown (`HomeStats.unitPriceFigure` returns nil).
    private static func fill(daysAgo: Double, price: String, station: Station?,
                             currency: CurrencyCode = .eur) -> FillUp {
        let date = asOf - daysAgo * day
        let money = Money(amount: 60, currency: currency, homeCurrency: .eur)
        return FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: 100_000,
            money: money, note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 40, unitPrice: Decimal(string: price)!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: station?.id, crossCheck: .notApplicable, extraction: nil)
    }

    @Test("two brands with two fills each: cheapest first, and the gap names the dearest")
    func twoBrandsCompare() throws {
        let shell = Self.station(name: "Shell Järvevana", brand: "Shell")
        let neste = Self.station(name: "Neste Sikupilli", brand: "Neste")
        let fills = [
            Self.fill(daysAgo: 60, price: "1.700", station: shell),
            Self.fill(daysAgo: 40, price: "1.660", station: neste),
            Self.fill(daysAgo: 20, price: "1.740", station: shell),
            Self.fill(daysAgo: 5, price: "1.640", station: neste)
        ]
        let series = BrandPrices.series(entries: fills, stations: [shell, neste], vehicleHome: .eur, asOf: Self.asOf)
        #expect(series.map(\.brand) == ["Neste", "Shell"])
        #expect(series.map(\.fillCount) == [2, 2])
        let gap = try #require(BrandPrices.gap(series))
        #expect(gap.dearest == "Shell")
        #expect(gap.cheapest == "Neste")
        #expect(gap.percent == 4)   // 1.72 vs 1.65
    }

    @Test("a station without a brand is grouped under its own name")
    func brandlessStationUsesItsName() {
        let prima = Self.station(name: "Prima Auto")
        let circle = Self.station(name: "Circle K Jugla", brand: "Circle K")
        let fills = [
            Self.fill(daysAgo: 30, price: "1.60", station: prima),
            Self.fill(daysAgo: 20, price: "1.62", station: prima),
            Self.fill(daysAgo: 10, price: "1.70", station: circle),
            Self.fill(daysAgo: 1, price: "1.72", station: circle)
        ]
        let series = BrandPrices.series(entries: fills, stations: [prima, circle], vehicleHome: .eur, asOf: Self.asOf)
        #expect(series.map(\.brand) == ["Prima Auto", "Circle K"])
    }

    @Test("a brand with one fill, a fill with no station, and a rate-pending fill never count")
    func thinAndUnknownFillsAreLeftOut() {
        let shell = Self.station(name: "Shell", brand: "Shell")
        let neste = Self.station(name: "Neste", brand: "Neste")
        let fills = [
            Self.fill(daysAgo: 30, price: "1.70", station: shell),
            Self.fill(daysAgo: 20, price: "1.72", station: shell),
            Self.fill(daysAgo: 10, price: "1.60", station: neste),               // one fill only
            Self.fill(daysAgo: 8, price: "1.50", station: nil),                  // no station
            Self.fill(daysAgo: 4, price: "9.99", station: shell, currency: .pln) // rate pending
        ]
        let series = BrandPrices.series(entries: fills, stations: [shell, neste], vehicleHome: .eur, asOf: Self.asOf)
        #expect(series.map(\.brand) == ["Shell"])
        #expect(series.first?.fillCount == 2)
        #expect(BrandPrices.gap(series) == nil)
    }

    @Test("fills older than the window are outside the comparison")
    func oldFillsAreOutsideTheWindow() {
        let shell = Self.station(name: "Shell", brand: "Shell")
        let fills = [
            Self.fill(daysAgo: 400, price: "1.70", station: shell),
            Self.fill(daysAgo: 380, price: "1.72", station: shell),
            Self.fill(daysAgo: 10, price: "1.60", station: shell)
        ]
        #expect(BrandPrices.series(entries: fills, stations: [shell], vehicleHome: .eur, asOf: Self.asOf).isEmpty)
    }

    @Test("TrendsStats hides a single brand and carries two")
    func trendsStatsCarriesTheComparison() throws {
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: Self.asOf - 400 * Self.day, updatedAt: Self.asOf - 400 * Self.day,
            deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 100_000)
        let shell = Self.station(name: "Shell", brand: "Shell")
        let neste = Self.station(name: "Neste", brand: "Neste")
        let shellOnly = [
            Self.fill(daysAgo: 30, price: "1.70", station: shell),
            Self.fill(daysAgo: 20, price: "1.72", station: shell)
        ]
        let one = TrendsStats(vehicle: vehicle, entries: shellOnly, asOf: Self.asOf, stations: [shell, neste])
        #expect(one.brandPrices.isEmpty)
        #expect(one.brandPriceGap == nil)

        let both = shellOnly + [
            Self.fill(daysAgo: 10, price: "1.60", station: neste),
            Self.fill(daysAgo: 5, price: "1.62", station: neste)
        ]
        let two = TrendsStats(vehicle: vehicle, entries: both, asOf: Self.asOf, stations: [shell, neste])
        #expect(two.brandPrices.map(\.brand) == ["Neste", "Shell"])
        #expect(try #require(two.brandPriceGap).percent == 6)
    }
}

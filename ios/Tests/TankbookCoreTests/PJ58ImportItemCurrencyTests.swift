import Foundation
import Testing
@testable import TankbookCore

// PJ.58 - a service record's line-item costs must be homed in the CAR's home
// currency, not a hardcoded EUR. The record's own money already consulted
// `vehicle.homeCurrency`; the line items did not, so a KZT car imported today
// had items homed in euros. The fixture car here is KZT on purpose: with an EUR
// car the hardcode and the fix are indistinguishable (the row's vacuous trap).
@Suite("Import service line items home in the car's currency (PJ.58)")
struct PJ58ImportItemCurrencyTests {

    /// A non-EUR car. The point of the suite: an EUR fixture would pass against
    /// the old hardcode, so every assertion is on a currency the hardcode could
    /// not have produced.
    private static let kztVehicle = Vehicle(
        id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
        name: "KZT car", make: nil, model: nil, year: nil, plate: nil,
        powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: nil,
        batteryCapacityKWh: nil, homeCurrency: .kzt,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                             energy: .kWhPer100),
        photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: nil)

    private static func serviceCandidate(costCurrency: String = "KZT") -> ImportCandidate {
        let money = ImportMoney(amount: "125.50", currency: costCurrency)
        return ImportCandidate(
            entityType: "serviceRecord",
            date: Date(timeIntervalSinceReferenceDate: 0),
            odometer: 100_500, volumeL: nil, unitPrice: nil, money: money,
            fuelKind: nil, isFull: nil, tankLevelAfterPct: nil, note: "Oil change",
            vehicleName: "KZT car",
            provenance: ImportProvenance(tag: "import", source: "drivvo"),
            sourceRow: 1,
            items: [ImportServiceItem(title: "Oil change",
                                      category: ImportCategoryTag(tag: "oil"), cost: money)])
    }

    /// L1, FAILS TODAY: a service imported into a KZT car homes every line item
    /// in KZT. Restore the `.eur` literal in `makeItem` and this goes red.
    @Test func aServiceImportedIntoAKZTCarHomesItsLineItemsInKZT() throws {
        let service = try #require(ImportConverter.makeService(from: Self.serviceCandidate(),
                                                               vehicle: Self.kztVehicle,
                                                               source: "drivvo"))
        let item = try #require(service.items.first)
        let cost = try #require(item.cost)
        #expect(cost.homeCurrency == .kzt,
                "the line item must home in the car's currency, not the old hardcoded EUR")
    }

    /// L1: the record's own money and every item agree on home currency, so a
    /// car whose record says KZT can never carry an item priced against EUR.
    @Test func theRecordMoneyAndItsItemsAgreeOnHomeCurrency() throws {
        let service = try #require(ImportConverter.makeService(
            from: Self.serviceCandidate(), vehicle: Self.kztVehicle, source: "drivvo"))
        let recordMoney = try #require(service.money)
        let item = try #require(service.items.first)
        let cost = try #require(item.cost)
        #expect(recordMoney.homeCurrency == .kzt)
        #expect(cost.homeCurrency == recordMoney.homeCurrency,
                "the record and its items must agree on home currency")
    }

    /// A foreign-cost item still homes in the CAR's currency: the original
    /// stays USD, the home is KZT, and no rate exists yet so `homeAmount` is
    /// nil (rate-pending, hard rule 3) rather than a silently wrong EUR home.
    @Test func aForeignCostItemHomesInTheCarCurrencyAndStaysRatePending() throws {
        let service = try #require(ImportConverter.makeService(
            from: Self.serviceCandidate(costCurrency: "USD"),
            vehicle: Self.kztVehicle, source: "drivvo"))
        let item = try #require(service.items.first)
        let cost = try #require(item.cost)
        #expect(cost.currency == .usd)
        #expect(cost.homeCurrency == .kzt,
                "the home side is the car's currency even when the original differs")
        #expect(cost.homeAmount == nil,
                "no rate is known at conversion, so the pair is rate-pending, never a guessed home")
    }
}

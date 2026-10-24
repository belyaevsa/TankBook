import TankbookCore
import XCTest
@testable import Tankbook

/// RV.339 - a shared receipt photo carries what its entries say: the fill's
/// fuel, volume, price and amount, each shop line bought beside it, the
/// expenses' sum and the receipt total, all in the receipt's own currency.
@MainActor
final class RV339ReceiptShareCaptionTests: XCTestCase {

    private let vehicle = TargetCar.newCar(named: "Test car", homeCurrency: .eur).vehicleValue
    private let day = Date(timeIntervalSince1970: 1_790_000_000)
    private let group = UUID.v7()

    private var units: Vehicle.Units {
        Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100)
    }

    private func money(_ amount: String, _ currency: CurrencyCode = .rub) -> Money {
        Money(amount: Decimal(string: amount)!, currency: currency, homeCurrency: .eur)
    }

    private func fill(stationId: UUID? = nil, group: UUID? = nil) -> FillUp {
        FillUp(id: UUID.v7(), createdAt: day, updatedAt: day, vehicleId: vehicle.id, date: day,
               odometer: 123_456, money: money("2491.47"), provenance: .receiptScan,
               purchaseGroupId: group, volumeL: 42.3, unitPrice: Decimal(string: "58.9")!,
               fuelKind: .petrol95, isFull: true, stationId: stationId, crossCheck: .verified)
    }

    private func expense(_ title: String, _ amount: String,
                         _ currency: CurrencyCode = .rub) -> Expense {
        Expense(id: UUID.v7(), createdAt: day.addingTimeInterval(1), updatedAt: day,
                deletedAt: nil, vehicleId: vehicle.id, date: day, odometer: nil,
                money: money(amount, currency), note: nil, attachments: [],
                provenance: .receiptScan, conflict: .none, purchaseGroupId: group,
                category: .other(""), title: title)
    }

    private func amount(_ value: String, _ currency: CurrencyCode = .rub) -> String {
        HomeFormat.entryAmount(Decimal(string: value)!,
                               symbol: AddVehicleSupport.moneySymbol(for: currency))
    }

    /// A mixed receipt: the fill's lines first, then each shop line, then the
    /// expenses' sum and the receipt total - and the station and odometer.
    func testAMixedReceiptListsEveryEntryAndBothSums() {
        let station = Station(id: UUID.v7(), createdAt: day, updatedAt: day, name: "Shell",
                              favorite: false, defaults: .init(fuelKind: nil, fuelGrade: nil))
        let entries: [any Entry] = [expense("Coffee", "240"), fill(stationId: station.id, group: group),
                                    expense("Wipers", "400")]
        let lines = ReceiptShareCaption.text(entries: entries, stations: [station], units: units)
            .components(separatedBy: "\n")

        XCTAssertTrue(lines[0].hasPrefix("Date: "), "the first line is the receipt's date")
        XCTAssertEqual(Array(lines.dropFirst()), [
            "Station: Shell",
            "Fuel: 95",
            "Volume: \(VolumeDisplay.text(42.3, unit: .l))",
            "Price / L: \(HomeFormat.unitPrice(Decimal(string: "58.9")!, symbol: "₽", volumeUnit: .l))",
            "Amount: \(amount("2491.47"))",
            "Coffee: \(amount("240"))",
            "Wipers: \(amount("400"))",
            "Expenses: \(amount("640"))",
            "Total: \(amount("3131.47"))",
            "Odometer: \(OdometerFormat.grouped(123_456)) km"
        ])
    }

    /// A fill on its own carries no sums - its amount is already the total.
    func testASingleFillHasNoTotalLine() {
        let text = ReceiptShareCaption.text(entries: [fill()], stations: [], units: units)
        XCTAssertTrue(text.contains("Amount: \(amount("2491.47"))"))
        XCTAssertFalse(text.contains("Total:"))
        XCTAssertFalse(text.contains("Expenses:"))
        XCTAssertFalse(text.contains("Station:"), "no station line without a station")
    }

    /// Two currencies are never summed into one number (hard rule 3): the total
    /// lists each currency's sum.
    func testMixedCurrenciesAreSummedPerCurrency() {
        let entries: [any Entry] = [expense("Toll", "10", .eur), expense("Coffee", "240"),
                                    expense("Snack", "100")]
        let text = ReceiptShareCaption.text(entries: entries, stations: [], units: units)
        XCTAssertTrue(text.contains("Total: \(amount("10", .eur)) · \(amount("340"))"), text)
    }

    /// A lone expense states its amount under the plain label, not its title
    /// twice.
    func testALoneExpenseStatesItsAmount() {
        let text = ReceiptShareCaption.text(entries: [expense("Car wash", "500")],
                                            stations: [], units: units)
        XCTAssertTrue(text.hasSuffix("Amount: \(amount("500"))"), text)
    }
}

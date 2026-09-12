import TankbookCore
import XCTest
@testable import Tankbook

/// PJ.58 - the second hardcoded `.eur`, on a service record's line items. The
/// car factory (RV.185) and the item converter are two sites of one decision:
/// an imported car's money is denominated in the currency the user declared.
/// Asserted TOGETHER here, because each site can be individually correct while
/// the pair disagrees - a KZT car whose items still home in EUR is exactly that.
@MainActor
final class PJ58ImportCarItemCurrencyTests: XCTestCase {

    private func serviceCandidate(currency: String) -> ImportCandidate {
        let money = ImportMoney(amount: "15000", currency: currency)
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

    /// The pair: the synthesized KZT car, its service record and every line item
    /// carry the SAME home currency. The old item hardcode fails this on the
    /// item; the old car hardcode fails it on the car.
    func testTheSynthesizedCarAndItsServiceItemsAgreeOnHomeCurrency() throws {
        let car = TargetCar.newCar(named: "KZT car", homeCurrency: .kzt).vehicleValue
        XCTAssertEqual(car.homeCurrency, .kzt, "RV.185: the car carries the declared currency")

        let service = try XCTUnwrap(ImportConverter.makeService(
            from: serviceCandidate(currency: "KZT"), vehicle: car, source: "drivvo"))

        XCTAssertEqual(service.money?.homeCurrency, .kzt,
                       "the record's money homes in the car's currency")
        XCTAssertEqual(service.items.first?.cost?.homeCurrency, .kzt,
                       "PJ.58: the line item homes in the car's currency, not a hardcoded EUR")
        XCTAssertEqual(service.money?.homeCurrency, service.items.first?.cost?.homeCurrency,
                       "the record and its items must not disagree about the home currency")
    }
}

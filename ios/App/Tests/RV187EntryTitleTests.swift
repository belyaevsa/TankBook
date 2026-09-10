import TankbookCore
import XCTest
@testable import Tankbook

/// RV.187 - a service or expense row carries its own title the way a fill-up
/// carries its station: the title when there is one, the category when there is
/// not, and never the bare type name while better text exists. One title
/// function (`EntryTitle`) serves every surface, so the Log row and the
/// Excluded-entries list cannot disagree.
@MainActor
final class RV187EntryTitleTests: XCTestCase {

    private let vehicle = TargetCar.newCar(named: "Test car", homeCurrency: .eur).vehicleValue

    private func service(_ titles: [String], category: ServiceCategory = .oil,
                         vendor: String? = nil) -> ServiceRecord {
        let items = titles.map { title in
            ServiceItem(title: title, category: category, cost: nil,
                        partNumber: nil, lifetime: nil)
        }
        return ServiceRecord(
            id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            vehicleId: vehicle.id, date: Date(), odometer: nil, money: nil,
            note: nil, attachments: [], provenance: .import(source: "drivvo"),
            conflict: .none, purchaseGroupId: nil, vendor: vendor, items: items,
            usedParts: [], tireSetId: nil, proposedReminderId: nil)
    }

    private func expense(_ title: String, category: ExpenseCategory) -> Expense {
        Expense(
            id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            vehicleId: vehicle.id, date: Date(), odometer: nil, money: nil,
            note: nil, attachments: [], provenance: .import(source: "drivvo"),
            conflict: .none, purchaseGroupId: nil, category: category, title: title)
    }

    /// A service with a named item renders that item's title, never "Service".
    func testServiceWithAnItemTitleShowsTheItemTitle() {
        let entry = service(["Замена масла"])
        XCTAssertEqual(EntryTitle.text(entry, stations: []), "Замена масла")
        XCTAssertNotEqual(EntryTitle.text(entry, stations: []), L10n.localize("Service"))
    }

    /// The multi-item decision: the first named item plus a count of the rest.
    func testMultiItemServiceShowsTheFirstItemAndACount() {
        let entry = service(["Замена масла", "Масляный фильтр", "Стоимость работы"])
        XCTAssertEqual(EntryTitle.text(entry, stations: []), "Замена масла and 2 more")
    }

    /// With no item named, the first item's category is the title; only when
    /// there is neither does the bare type name appear.
    func testServiceWithNoTitleFallsBackToCategoryThenTypeName() {
        let withCategory = service([""], category: .oil)
        XCTAssertEqual(EntryTitle.text(withCategory, stations: []), "Oil")
        let withNothing = service([])
        XCTAssertEqual(EntryTitle.text(withNothing, stations: []), L10n.localize("Service"))
    }

    /// An expense with an empty title falls back to its category. `Expense`
    /// always carries a category, so the bare type name is never reached while
    /// better text exists.
    func testExpenseWithNoTitleFallsBackToItsCategory() {
        XCTAssertEqual(EntryTitle.text(expense("", category: .insurance), stations: []),
                       "Insurance")
        XCTAssertEqual(EntryTitle.text(expense("", category: .other("")), stations: []),
                       "Other")
    }

    /// The Log row and the Excluded-entries list resolve the SAME title for the
    /// same entry: both go through `EntryTitle`, so the two entry points (the
    /// `LogStream.LogEntry` the Log renders and the `any Entry` the excluded
    /// list renders) agree.
    func testLogRowAndExcludedListAgreeOnTheSameTitle() {
        let entry = service(["Замена масла"])
        let stream = LogStream(vehicle: vehicle, entries: [entry])
        let logEntry = stream.sections
            .flatMap(\.rows)
            .compactMap { row -> LogStream.LogEntry? in
                if case .entry(let value) = row { return value }
                return nil
            }
            .first
        guard let logEntry else { return XCTFail("the service entry must reach the Log stream") }
        XCTAssertEqual(EntryTitle.text(logEntry, stations: []),
                       EntryTitle.text(entry, stations: []),
                       "the Log row and the excluded list must show the same title")
        XCTAssertEqual(EntryTitle.text(logEntry, stations: []), "Замена масла")
    }
}

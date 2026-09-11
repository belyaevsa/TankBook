import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.134: the Confirm sheet stated a miles/gallons car's own units in two rows
/// and contradicted itself in two others (`Price / L`, `÷ liters`), hardcoded
/// `km` in the live delta caption for every car, and two more entry kinds
/// hardcoded the km odometer quote. The fix is one full localised sentence per
/// unit (`ManualFillUpUnitCopy`, `OdometerConflict.quote`), never a unit token
/// spliced into a shared stem - RU declines the units differently, so the
/// sentence is the translation unit.
///
/// These are the L1 selectors: they FAIL when the imperial path is reverted to
/// the litre/km key (the named mutation). The catalogue half - the exact EN and
/// RU phrases each key renders - lives beside the RV.126 catalogue suite
/// (`LocalizationGateRV134Tests`).
final class RV134UnitCopyTests: XCTestCase {

    private let day: TimeInterval = 86_400
    private var epoch: Date { Date(timeIntervalSince1970: 1_700_000_000) }

    private func makeVehicle(distance: DistanceUnit) -> Vehicle {
        Vehicle(id: UUID.v7(), createdAt: epoch, updatedAt: epoch, deletedAt: nil,
                name: "Test Volvo", make: "Volvo", model: "V60", year: 2015, plate: nil,
                powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: 71,
                batteryCapacityKWh: nil, homeCurrency: .eur,
                units: Vehicle.Units(distance: distance, volume: .l,
                                     consumption: .lPer100, energy: .kWhPer100),
                photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 0)
    }

    private func makeFill(date: Date, odometer: Int) -> FillUp {
        FillUp(id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
               vehicleId: UUID.v7(), date: date, odometer: odometer,
               money: nil, note: nil, attachments: [], provenance: .manual,
               conflict: .none, purchaseGroupId: nil, volumeL: 40,
               unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil, isFull: true,
               tankLevelAfterPct: 100, stationId: nil,
               crossCheck: .notApplicable, extraction: nil)
    }

    /// The RU bundle of the app under test, so an L1 can read the phrase the
    /// user actually sees without switching the test process's language.
    private var russianBundle: Bundle? {
        Bundle.main.path(forResource: "ru", ofType: "lproj").flatMap(Bundle.init(path:))
    }

    // MARK: The volume pair

    /// EN is the app's source language, so each EN phrase is also its catalogue
    /// key - the key the RU bundle lookup below uses.
    func testPriceLabelIsPerVolumeUnit() {
        XCTAssertEqual(ManualFillUpUnitCopy.priceLabel(for: .l), "Price / L")
        XCTAssertEqual(ManualFillUpUnitCopy.priceLabel(for: .galUS), "Price / gal")
        XCTAssertEqual(ManualFillUpUnitCopy.priceLabel(for: .galUK), "Price / gal",
                       "both gallons share the compact label the volume row already uses")
    }

    func testFillsFromTotalIsPerVolumeUnit() {
        XCTAssertEqual(ManualFillUpUnitCopy.fillsFromTotal(for: .l),
                       "fills in from total ÷ liters")
        XCTAssertEqual(ManualFillUpUnitCopy.fillsFromTotal(for: .galUS),
                       "fills in from total ÷ gallons")
        XCTAssertEqual(ManualFillUpUnitCopy.fillsFromTotal(for: .galUK),
                       "fills in from total ÷ gallons")
    }

    /// The RU imperial price label is "Цена / гал", never "Цена / л". This is
    /// the named mutation's red: reverting the `.galUS` path to the litre key
    /// makes the key "Price / L" and this read "Цена / л".
    func testImperialPriceLabelRendersRussianGallons() throws {
        let bundle = try XCTUnwrap(russianBundle, "the app must bundle ru.lproj")
        let key = ManualFillUpUnitCopy.priceLabel(for: .galUS)
        XCTAssertEqual(key, "Price / gal", "the EN value is the catalogue key")
        let ru = bundle.localizedString(forKey: key, value: nil, table: nil)
        XCTAssertEqual(ru, "Цена / гал")
    }

    func testImperialFillsFromTotalRendersRussianGallons() throws {
        let bundle = try XCTUnwrap(russianBundle, "the app must bundle ru.lproj")
        let key = ManualFillUpUnitCopy.fillsFromTotal(for: .galUS)
        XCTAssertEqual(key, "fills in from total ÷ gallons", "the EN value is the catalogue key")
        let ru = bundle.localizedString(forKey: key, value: nil, table: nil)
        XCTAssertEqual(ru, "считается из суммы ÷ галлонов")
    }

    // MARK: The distance delta

    /// The rendered caption names the vehicle's own unit: a miles car is told
    /// about miles and never kilometres.
    func testDeltaSinceLastRendersTheVehiclesUnit() {
        XCTAssertTrue(ManualFillUpUnitCopy.deltaSinceLast(.km, km: 120).contains("km"))
        let miles = ManualFillUpUnitCopy.deltaSinceLast(.mi, km: 120)
        XCTAssertTrue(miles.contains("mi"), "a miles car must be told miles, was '\(miles)'")
        XCTAssertFalse(miles.contains("km"), "a miles car must never be told kilometres, was '\(miles)'")
    }

    // MARK: The service entry's odometer quote (the km hardcode)

    /// A service odometer below its date-neighbour renders the same per-unit
    /// quote the Confirm sheet uses. A miles service is told miles, never km.
    func testServiceOdometerConflictQuoteNamesTheVehiclesUnit() throws {
        var form = ServiceEntryFormState()
        form.odometer = "10020"
        form.date = epoch.addingTimeInterval(10 * day)

        let conflict = try XCTUnwrap(
            form.odometerConflict(vehicle: makeVehicle(distance: .mi),
                                  existingEntries: [makeFill(date: epoch, odometer: 10_000),
                                                    makeFill(date: epoch.addingTimeInterval(5 * day),
                                                             odometer: 10_050)],
                                  distanceUnit: .mi),
            "the out-of-order service must flag")
        let quote = try XCTUnwrap(conflict.quote)
        XCTAssertTrue(quote.contains("mi"), "the quote must name miles, was '\(quote)'")
        XCTAssertFalse(quote.contains("km"), "the quote must not name kilometres, was '\(quote)'")
    }
}

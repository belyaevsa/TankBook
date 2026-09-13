import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.271: two unit residues RV.234's audit found outside its list. Both are the
/// same shape - a label made per-unit while the value beside it stayed in the
/// stored unit. These L1 selectors fail on the litre/km value.
final class RV271UnitResidueTests: XCTestCase {

    /// The RU bundle of the app under test, so an L1 can read the phrase the
    /// user actually sees without switching the test process's language.
    private var russianBundle: Bundle {
        get throws {
            try XCTUnwrap(Bundle.main.path(forResource: "ru", ofType: "lproj")
                .flatMap(Bundle.init(path:)), "the app must bundle ru.lproj")
        }
    }

    private func ru(_ key: String) throws -> String {
        try russianBundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private func units(distance: DistanceUnit, volume: VolumeUnit) -> Vehicle.Units {
        Vehicle.Units(distance: distance, volume: volume,
                      consumption: distance == .mi ? .mpgUS : .lPer100,
                      energy: distance == .mi ? .miPerKWh : .kWhPer100)
    }

    private func vehicle(distance: DistanceUnit, volume: VolumeUnit,
                         paceLimitKmPerDay: Double = 1500) -> Vehicle {
        let now = Date()
        return Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "RV271", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: units(distance: distance, volume: volume),
            photo: nil, archived: false, paceLimitKmPerDay: paceLimitKmPerDay,
            initialOdometer: 118_000)
    }

    // MARK: - Residue 1: the pace limit reads and edits in the car's unit

    /// The field label exists once per distance unit, EN and RU (hard rule 10 -
    /// the phrase is the translation unit).
    func testPaceLimitUnitIsPerDistanceUnitInEnglishAndRussian() throws {
        XCTAssertEqual(ManualFillUpUnitCopy.paceLimitUnit(for: .km), "km/day")
        XCTAssertEqual(ManualFillUpUnitCopy.paceLimitUnit(for: .mi), "mi/day")
        XCTAssertNotEqual(ManualFillUpUnitCopy.paceLimitUnit(for: .km),
                          ManualFillUpUnitCopy.paceLimitUnit(for: .mi))
        XCTAssertEqual(try ru("km/day"), "км/день")
        XCTAssertEqual(try ru("mi/day"), "миль/день")
    }

    /// The field loads and saves in the car's own distance unit. A metric car is
    /// unchanged; a miles car reads the converted figure, and an untouched save
    /// keeps the car's own kilometre value (rule 13 - the field is a display of
    /// the stored bound, not a new fact).
    func testPaceLimitLoadsAndSavesInTheCarsDistanceUnit() {
        let metric = vehicle(distance: .km, volume: .l)
        var metricForm = VehicleDetailFormState()
        metricForm.load(from: metric, photoData: nil)
        XCTAssertEqual(metricForm.paceLimit, "1500")
        XCTAssertEqual(metricForm.applying(to: metric).paceLimitKmPerDay, 1500)

        let imperial = vehicle(distance: .mi, volume: .galUS)
        var imperialForm = VehicleDetailFormState()
        imperialForm.load(from: imperial, photoData: nil)
        XCTAssertEqual(imperialForm.paceLimit, "932.1",
                       "1500 km/day must read as miles per day on a miles car")
        XCTAssertEqual(imperialForm.applying(to: imperial).paceLimitKmPerDay, 1500,
                       accuracy: 1,
                       "an untouched save must keep the car's kilometre bound")
    }

    /// A figure the user types is in the display unit and converts to kilometres
    /// at the save boundary.
    func testATypedImperialPaceLimitConvertsToKilometres() {
        let imperial = vehicle(distance: .mi, volume: .galUS)
        var form = VehicleDetailFormState()
        form.load(from: imperial, photoData: nil)
        form.paceLimit = "1000"
        XCTAssertEqual(form.applying(to: imperial).paceLimitKmPerDay, 1609.344,
                       accuracy: 0.001,
                       "1000 mi/day is 1609.344 km/day")
    }

    /// Switching the distance unit re-expresses the same physical pace in the
    /// new unit, the way the capacity field re-expresses the tank (RV.69).
    func testSwitchingDistanceReexpressesThePaceLimit() {
        var form = VehicleDetailFormState()
        form.load(from: vehicle(distance: .km, volume: .l), photoData: nil)
        form.paceLimit = "1000"
        form.reconvertPaceLimitDistance(from: .km, to: .mi)
        XCTAssertEqual(form.paceLimit, "621.4",
                       "1000 km/day is 621.4 mi/day")
        form.reconvertPaceLimitDistance(from: .mi, to: .km)
        XCTAssertEqual(form.paceLimit, "1000",
                       "and back, within the one-decimal display")
    }

    // MARK: - Residue 2: the inbox volume values read in the car's unit

    /// Both columns of the volume comparison render the car's unit. The saved
    /// figure is stored litres; the receipt's reading is normalized to litres by
    /// the extractor, so the two are converted with the one litre<->display
    /// converter the fill forms use.
    func testInboxVolumeValuesAreConvertedToTheCarsVolumeUnit() {
        let now = Date()
        let vehicle = vehicle(distance: .mi, volume: .galUS)
        let fill = FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 120_000,
            money: Money(amount: Decimal(string: "100.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.30, unitPrice: nil,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .notApplicable, extraction: nil)
        let entry = InboxEntry.fillUp(fill)

        // Metric: the litre figure is the stored one.
        XCTAssertEqual(InboxValueFormat.yours(.volume, entry: entry, volumeUnit: .l), "42.30 L")

        // Imperial: the same stored litres read gallons.
        XCTAssertEqual(InboxValueFormat.yours(.volume, entry: entry, volumeUnit: .galUS), "11.17 gal",
                       "the saved 42.30 L must read 11.17 gal on a gallons car")

        let extraction = GatewayExtraction(
            volume: .init(value: 40.00, confidence: 0.90), pipeline: "seed")
        let recognition = InboxRecognition.fuel(extraction)

        XCTAssertEqual(
            InboxValueFormat.receipt(.volume, entry: entry, recognition: recognition, volumeUnit: .l),
            "40.00 L")
        XCTAssertEqual(
            InboxValueFormat.receipt(.volume, entry: entry, recognition: recognition, volumeUnit: .galUS),
            "10.57 gal",
            "the receipt's 40.00 L reading must read 10.57 gal on a gallons car")
    }
}

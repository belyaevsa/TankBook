import TankbookCore
import XCTest
@testable import Tankbook

/// RV.137 L1 - a catalogue pick on the Vehicle edit screen stores make, model
/// and year as text the user owns and records NO catalogue identifier or
/// reference. The permanence decision (VehicleDetailView's header: "nothing
/// here stores a catalog id for a later pack to rewrite") is not this test's to
/// make; it is the mechanism this test pins. Lives in the app-target test
/// bundle because the form state is app code; the SwiftPM core tests run on
/// macOS and cannot reach it.
final class VehicleEditSuggestionTests: XCTestCase {

    /// A pick fills the three model fields and nothing else. The assertion is
    /// equality against a copy of the original changed ONLY in make/model/year
    /// and `updatedAt`: a future change that makes the pick "stick" by binding
    /// the car to a catalogue row, or that copies the suggestion's powertrain,
    /// fuel kinds, capacity or units over the user's own values, fails here.
    func testSuggestionPickStoresOnlyMakeModelYearAndNoCatalogIdentifier() throws {
        let id = UUID()
        let createdAt = Date(timeIntervalSinceReferenceDate: 1000)
        let original = Vehicle(id: id, createdAt: createdAt, updatedAt: createdAt,
                               deletedAt: nil, name: "Volvo V60",
                               make: "Volvo", model: "V60", year: 2015, plate: "A1",
                               powertrain: .ice, fuelKinds: [.petrol95, .lpg],
                               tankCapacityL: 71, batteryCapacityKWh: nil,
                               homeCurrency: .eur,
                               units: Vehicle.Units(distance: .km, volume: .l,
                                                    consumption: .lPer100,
                                                    energy: .kWhPer100),
                               archived: false, paceLimitKmPerDay: 1500,
                               initialOdometer: nil)
        var form = VehicleDetailFormState()
        form.load(from: original, photoData: nil)

        // The edit-screen pick that mirrors typing "Lada" and tapping the
        // first row: the bundled Granta, whose open-ended model-year range
        // lands the year on the current one, exactly as Add car pre-fills.
        let entries = try VehicleCatalogStore.bundledEntries()
        let granta = try XCTUnwrap(entries.first { $0.make == "Lada" && $0.model == "Granta" })
        form.applyMakeModelSuggestion(granta.prefill(currentYear: 2026))

        XCTAssertEqual(form.makeModel, "Lada · Granta · 2026",
                       "the pick writes the canonical make · model · year text")
        let now = Date(timeIntervalSinceReferenceDate: 2000)
        let updated = form.applying(to: original, now: now)

        XCTAssertEqual(updated.make, "Lada", "the pick must set the stored make")
        XCTAssertEqual(updated.model, "Granta", "the pick must set the stored model")
        XCTAssertEqual(updated.year, 2026, "the pick must set the stored year")

        var expected = original
        expected.updatedAt = now
        expected.make = "Lada"
        expected.model = "Granta"
        expected.year = 2026
        XCTAssertEqual(updated, expected,
                       "the pick must change ONLY make/model/year (and updatedAt) - "
                       + "no catalogue identifier, no rewrite of name, powertrain, fuel "
                       + "kinds, capacity, currency or units")
    }

    /// The permanence half: a user's own model text that matches no catalogue
    /// row is saved exactly as typed, with make/model/year parsed from it, and
    /// no suggestion has touched the record - the edit path is complete without
    /// the picker (hard rule 13: the value is editable as text even when the
    /// convenience is not offered).
    func testTypedModelTextStillRoundTripsWithoutAnySuggestion() {
        let createdAt = Date(timeIntervalSinceReferenceDate: 1000)
        let original = Vehicle(id: UUID(), createdAt: createdAt, updatedAt: createdAt,
                               deletedAt: nil, name: "Volvo V60",
                               make: "Volvo", model: "V60", year: 2015, plate: nil,
                               powertrain: .ice, fuelKinds: [.petrol95],
                               tankCapacityL: 71, batteryCapacityKWh: nil,
                               homeCurrency: .eur,
                               units: Vehicle.Units(distance: .km, volume: .l,
                                                    consumption: .lPer100,
                                                    energy: .kWhPer100),
                               archived: false, paceLimitKmPerDay: 1500,
                               initialOdometer: nil)
        var form = VehicleDetailFormState()
        form.load(from: original, photoData: nil)
        // Free typing, exactly as the Make·model field's own onChange parses it
        // (MakeModelParser) with no pick ever applied.
        let text = "Saab 900 Turbo 1998"
        form.makeModel = text
        let parsed = MakeModelParser.parse(text)
        form.make = parsed.make
        form.model = parsed.model
        form.year = parsed.year

        let updated = form.applying(to: original, now: Date(timeIntervalSinceReferenceDate: 2000))
        XCTAssertEqual(updated.make, "Saab")
        XCTAssertEqual(updated.model, "900 Turbo")
        XCTAssertEqual(updated.year, 1998)
        XCTAssertEqual(updated.name, "Volvo V60")
    }
}

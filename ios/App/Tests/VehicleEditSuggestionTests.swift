import TankbookCore
import XCTest
@testable import Tankbook

/// RV.137 / RV.182 L1 - a catalogue pick on the Vehicle edit screen stores
/// make, model and year as text the user owns and records NO catalogue
/// identifier or reference.
///
/// RV.182 narrowed what a pick promises. The suggestion row renders a tank or
/// battery volume (`Shared/VehicleCatalogSuggestionsArea.swift`), so a pick
/// must fill that volume when the capacity field is BLANK - an empty field is
/// not a user value - while a capacity the user has already set stays
/// byte-identical (hard rule 13: a value the user set is theirs permanently).
/// The permanence decision (VehicleDetailView's header: "nothing here stores a
/// catalog id for a later pack to rewrite") is not these tests' to make; it is
/// the mechanism they pin. Lives in the app-target test bundle because the form
/// state is app code; the SwiftPM core tests run on macOS and cannot reach it.
final class VehicleEditSuggestionTests: XCTestCase {

    private let createdAt = Date(timeIntervalSinceReferenceDate: 1000)
    private let now = Date(timeIntervalSinceReferenceDate: 2000)

    private func vehicle(name: String = "Volvo V60",
                         make: String? = "Volvo", model: String? = "V60", year: Int? = 2015,
                         powertrain: Powertrain = .ice,
                         fuelKinds: [FuelKind] = [.petrol95, .lpg],
                         tankCapacityL: Double? = 71, batteryCapacityKWh: Double? = nil,
                         volume: VolumeUnit = .l) -> Vehicle {
        Vehicle(id: UUID(), createdAt: createdAt, updatedAt: createdAt,
                deletedAt: nil, name: name, make: make, model: model, year: year, plate: "A1",
                powertrain: powertrain, fuelKinds: fuelKinds,
                tankCapacityL: tankCapacityL, batteryCapacityKWh: batteryCapacityKWh,
                homeCurrency: .eur,
                units: Vehicle.Units(distance: .km, volume: volume,
                                     consumption: .lPer100, energy: .kWhPer100),
                archived: false, paceLimitKmPerDay: 1500, initialOdometer: nil)
    }

    private func granta() throws -> VehicleCatalogEntry {
        let entries = try VehicleCatalogStore.bundledEntries()
        return try XCTUnwrap(entries.first { $0.make == "Lada" && $0.model == "Granta" })
    }

    /// RV.182 narrowed this from "the pick changes ONLY make/model/year". The
    /// pick now also fills a BLANK capacity, so the claim that still holds - and
    /// the one that matters - is that a capacity the user already set is never
    /// overwritten and no catalogue identifier is stored. The fixture's tank
    /// (71 L) is non-empty, so a blank-fields-only pick must leave it exactly as
    /// it was; the pick writes make/model/year and nothing else.
    func testSuggestionPickStoresNoCatalogIdentifierAndNeverOverwritesANonEmptyCapacity() throws {
        let original = vehicle()
        var form = VehicleDetailFormState()
        form.load(from: original, photoData: nil)

        // The edit-screen pick that mirrors typing "Lada" and tapping the
        // first row: the bundled Granta, whose open-ended model-year range
        // lands the year on the current one, exactly as Add car pre-fills.
        form.applyMakeModelSuggestion(try granta().prefill(currentYear: 2026))

        XCTAssertEqual(form.makeModel, "Lada · Granta · 2026",
                       "the pick writes the canonical make · model · year text")
        XCTAssertEqual(form.capacity, "71",
                       "the user's own tank must stay byte-identical - the pick only fills a BLANK capacity")
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
                       "the pick must change ONLY make/model/year (and updatedAt) when the capacity "
                       + "is non-empty - no catalogue identifier, no rewrite of name, powertrain, "
                       + "fuel kinds, capacity, currency or units")
    }

    /// RV.182 L1, the half that fails today: a pick on a car whose capacity the
    /// user has NOT set fills it with the figure the suggestion row displays.
    /// The oracle is the row's own displayed volume - the catalogue tank
    /// converted into the form's unit the same way the row renders it - never
    /// "the field is non-empty".
    func testSuggestionPickFillsABlankCapacityWithTheRowsDisplayedVolume() throws {
        let entry = try granta()
        let tank = try XCTUnwrap(entry.tankCapacityL)
        let original = vehicle(tankCapacityL: nil)
        var form = VehicleDetailFormState()
        form.load(from: original, photoData: nil)
        XCTAssertEqual(form.capacity, "", "precondition: the field starts blank")

        form.applyMakeModelSuggestion(entry.prefill(currentYear: 2026))

        XCTAssertEqual(form.capacity,
                       AddVehicleSupport.tankCapacityText(litres: tank, unit: .l),
                       "a blank capacity must take the volume the suggestion row displays")
        XCTAssertEqual(form.capacity, "50", "the Granta row advertises 50 L")

        let updated = form.applying(to: original, now: now)
        XCTAssertEqual(updated.tankCapacityL, tank,
                       "the filled figure must reach the stored vehicle as the same physical volume")
    }

    /// RV.182 L1, the gallons half: the row renders the catalogue's litres in
    /// the vehicle's own volume unit (RV.69), so the filled field must be the
    /// gallons figure the row shows, and the stored tank must still be ~50 L
    /// physical. A litres-only test cannot see a half-conversion.
    func testSuggestionPickFillsABlankCapacityInGallons() throws {
        let entry = try granta()
        let tank = try XCTUnwrap(entry.tankCapacityL)
        let original = vehicle(tankCapacityL: nil, volume: .galUS)
        var form = VehicleDetailFormState()
        form.load(from: original, photoData: nil)

        form.applyMakeModelSuggestion(entry.prefill(currentYear: 2026))

        XCTAssertEqual(form.capacity,
                       AddVehicleSupport.tankCapacityText(litres: tank, unit: .galUS),
                       "the blank field must take the row's gallons figure")
        XCTAssertEqual(form.capacity, "13.2", "the Granta row advertises ~13.2 gal in a US unit car")

        let updated = form.applying(to: original, now: now)
        XCTAssertEqual(updated.tankCapacityL ?? 0, tank, accuracy: 0.1,
                       "the stored tank must stay ~50 L physical, not the gallons number stored as litres")
    }

    /// RV.182 L1, the battery half of "every value the row shows": an EV row
    /// displays kWh, so a pick on an EV with a blank capacity fills it with the
    /// catalogue's battery size.
    func testSuggestionPickFillsABlankBatteryCapacity() throws {
        let entries = try VehicleCatalogStore.bundledEntries()
        let entry = try XCTUnwrap(entries.first { $0.make == "VW" && $0.model == "ID.4" })
        let battery = try XCTUnwrap(entry.batteryCapacityKWh)
        let original = vehicle(name: "ID.4", make: "Volkswagen", model: "ID.4", year: 2022,
                               powertrain: .ev, fuelKinds: [.electricity],
                               tankCapacityL: nil, batteryCapacityKWh: nil)
        var form = VehicleDetailFormState()
        form.load(from: original, photoData: nil)

        form.applyMakeModelSuggestion(entry.prefill(currentYear: 2026))

        XCTAssertEqual(form.capacity, AddVehicleSupport.capacityText(battery),
                       "a blank battery field must take the kWh the row displays")
        XCTAssertEqual(form.capacity, "77")
    }

    /// RV.182 L1, the more important half: a capacity the user typed stays
    /// byte-identical across a pick whose row advertises a different figure.
    func testSuggestionPickLeavesATypedCapacityByteIdentical() throws {
        let original = vehicle()
        var form = VehicleDetailFormState()
        form.load(from: original, photoData: nil)
        form.capacity = "60"

        form.applyMakeModelSuggestion(try granta().prefill(currentYear: 2026))

        XCTAssertEqual(form.capacity, "60",
                       "the pick must never overwrite a capacity the user typed (hard rule 13)")
    }

    /// RV.182 L1, the wrong-fact guard: the capacity field's kind is fixed by
    /// the car's powertrain (tank for a combustion car, battery for an EV), so a
    /// pick whose row advertises the OTHER kind is not fillable - a tank's
    /// litres in a kWh field (or the reverse) would be a silently plausible
    /// wrong fact (RV.69). The field stays blank, exactly as for an entry with
    /// no capacity of that kind.
    func testSuggestionPickDoesNotFillACapacityOfTheWrongKind() throws {
        // An EV car with a blank battery, picking the ICE Granta (50 L).
        let evOriginal = vehicle(name: "ID.4", make: "Volkswagen", model: "ID.4", year: 2022,
                                 powertrain: .ev, fuelKinds: [.electricity],
                                 tankCapacityL: nil, batteryCapacityKWh: nil)
        var evForm = VehicleDetailFormState()
        evForm.load(from: evOriginal, photoData: nil)
        evForm.applyMakeModelSuggestion(try granta().prefill(currentYear: 2026))
        XCTAssertEqual(evForm.capacity, "",
                       "a tank's litres must not land in an EV's kWh field (RV.69)")

        // A combustion car with a blank tank, picking the EV ID.4 (77 kWh).
        let entries = try VehicleCatalogStore.bundledEntries()
        let id4 = try XCTUnwrap(entries.first { $0.make == "VW" && $0.model == "ID.4" })
        let iceOriginal = vehicle(tankCapacityL: nil)
        var iceForm = VehicleDetailFormState()
        iceForm.load(from: iceOriginal, photoData: nil)
        iceForm.applyMakeModelSuggestion(id4.prefill(currentYear: 2026))
        XCTAssertEqual(iceForm.capacity, "",
                       "an EV's kWh must not land in a combustion car's litre field (RV.69)")
    }

    /// The permanence half: a user's own model text that matches no catalogue
    /// row is saved exactly as typed, with make/model/year parsed from it, and
    /// no suggestion has touched the record - the edit path is complete without
    /// the picker (hard rule 13: the value is editable as text even when the
    /// convenience is not offered).
    func testTypedModelTextStillRoundTripsWithoutAnySuggestion() {
        let original = vehicle()
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

        let updated = form.applying(to: original, now: now)
        XCTAssertEqual(updated.make, "Saab")
        XCTAssertEqual(updated.model, "900 Turbo")
        XCTAssertEqual(updated.year, 1998)
        XCTAssertEqual(updated.name, "Volvo V60")
    }
}

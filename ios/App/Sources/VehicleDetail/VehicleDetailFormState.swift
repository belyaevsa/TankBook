import Foundation
import TankbookCore

/// Form state for the Vehicle detail screen (P1.12) - every value Add car can
/// pre-fill from the catalog or the locale, editable again (hard rule 13: the
/// app suggests, the user decides - and once the user decides, it is theirs).
///
/// Loaded from an existing `Vehicle`; `applying(to:)` produces the updated
/// copy that upserts back. Shares the Add-car parsing/formatting helpers
/// (`MakeModelParser`, `OdometerFormat`, `AddVehicleSupport`,
/// `OdometerPlausibility`) so the two screens can never disagree on what a
/// value means.
struct VehicleDetailFormState {
    var name = ""
    var makeModel = ""
    var make: String?
    var model: String?
    var year: Int?
    var plate = ""
    var powertrain: Powertrain = .ice
    var selectedFuelKinds: Set<FuelKind> = [.petrol95]
    var odometer = ""
    var homeCurrency: CurrencyCode = LocaleCurrency.defaultCurrency(for: .current)
    var capacity = ""
    var units = Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100)
    var photo: Data?
    /// The vehicle's current attachment id + photo bytes, so saving can tell an
    /// unchanged photo (keep the id) from a replaced or removed one.
    var originalPhotoID: AttachmentID?
    var originalPhotoData: Data?
    var saveAttempted = false

    mutating func load(from vehicle: Vehicle, photoData: Data?) {
        name = vehicle.name
        makeModel = Self.makeModelText(make: vehicle.make, model: vehicle.model, year: vehicle.year)
        make = vehicle.make
        model = vehicle.model
        year = vehicle.year
        plate = vehicle.plate ?? ""
        powertrain = vehicle.powertrain
        selectedFuelKinds = Set(vehicle.fuelKinds)
        odometer = vehicle.initialOdometer.map(OdometerFormat.grouped) ?? ""
        homeCurrency = vehicle.homeCurrency
        // The field reads in the user's display unit. `tankCapacityL` stores
        // litres, so a tank's stored figure converts OUT at load; battery kWh
        // is unit-invariant and never converts (RV.69).
        let isElectric = vehicle.powertrain == .ev
        let capacityValue = isElectric ? vehicle.batteryCapacityKWh : vehicle.tankCapacityL
        if let capacityValue {
            capacity = isElectric
                ? AddVehicleSupport.capacityText(capacityValue)
                : AddVehicleSupport.tankCapacityText(litres: capacityValue, unit: vehicle.units.volume)
        } else {
            capacity = ""
        }
        units = vehicle.units
        photo = photoData
        originalPhotoID = vehicle.photo
        originalPhotoData = photoData
        saveAttempted = false
    }

    static func makeModelText(make: String?, model: String?, year: Int?) -> String {
        [make, model, year.map(String.init)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var odometerValue: Int? {
        let trimmed = odometer.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Int(OdometerFormat.ungrouped(trimmed))
    }

    var isElectric: Bool { powertrain == .ev }

    /// The Add-car empty-name warn, adapted: saving an edited car with no name
    /// is blocked and the warn clears live as soon as a name is typed
    /// (docs/ERRORS.md -> Add car, row 1).
    var showNameWarning: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && saveAttempted
    }

    var orderedFuelKinds: [FuelKind] {
        selectedFuelKinds.sorted { lhs, rhs in
            (FuelKind.allCases.firstIndex(of: lhs) ?? 0) < (FuelKind.allCases.firstIndex(of: rhs) ?? 0)
        }
    }

    /// The edited vehicle: every form field applied onto `original`. The
    /// envelope (`id`, `createdAt`) and the archive state (`archived` /
    /// `archivedAt`) are untouched - archiving is its own action. `updatedAt`
    /// bumps so sync LWW and the dirty queue see the edit.
    func applying(to original: Vehicle, now: Date = Date()) -> Vehicle {
        var vehicle = original
        let parsed = MakeModelParser.parse(makeModel)
        vehicle.updatedAt = now
        vehicle.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        vehicle.make = make ?? parsed.make
        vehicle.model = model ?? parsed.model
        vehicle.year = year ?? parsed.year
        vehicle.plate = trimmedOrNil(plate)
        vehicle.powertrain = powertrain
        vehicle.fuelKinds = orderedFuelKinds
        // The field held the display unit; storage is litres, so a tank figure
        // converts IN here and kWh does not (RV.69). `units.volume` (the form's
        // unit - the one the field was shown in) is the source of truth.
        let capacityValue = capacity.isEmpty ? nil : Double(capacity)
        if let capacityValue {
            if isElectric {
                vehicle.batteryCapacityKWh = capacityValue
                vehicle.tankCapacityL = nil
            } else {
                vehicle.tankCapacityL = AddVehicleSupport.tankCapacityLitres(display: capacityValue, unit: units.volume)
                vehicle.batteryCapacityKWh = nil
            }
        } else {
            vehicle.tankCapacityL = nil
            vehicle.batteryCapacityKWh = nil
        }
        vehicle.homeCurrency = homeCurrency
        vehicle.units = units
        vehicle.initialOdometer = odometerValue
        return vehicle
    }

    /// The capacity field always holds the volume unit the row currently
    /// labels. When the units editor changes that axis, the SAME physical
    /// volume must be re-expressed ("13.2" gal -> "50" for a 50 L tank), or a
    /// gallons user who switches to litres would save their "13.2" as 13.2 L
    /// and quietly halve the tank (hard rule 13 - the app must never turn a
    /// figure into a wrong fact). kWh is unit-invariant, so an EV's battery
    /// field is untouched.
    mutating func reconvertCapacityVolume(from oldUnit: VolumeUnit, to newUnit: VolumeUnit) {
        guard oldUnit != newUnit, !isElectric else { return }
        guard let value = Double(capacity) else { return }
        let litres = AddVehicleSupport.tankCapacityLitres(display: value, unit: oldUnit)
        capacity = AddVehicleSupport.tankCapacityText(litres: litres, unit: newUnit)
    }

    private func trimmedOrNil(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

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
        let capacityValue = vehicle.powertrain == .ev ? vehicle.batteryCapacityKWh : vehicle.tankCapacityL
        capacity = capacityValue.map(AddVehicleSupport.capacityText) ?? ""
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
        let capacityValue = capacity.isEmpty ? nil : Double(capacity)
        vehicle.updatedAt = now
        vehicle.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        vehicle.make = make ?? parsed.make
        vehicle.model = model ?? parsed.model
        vehicle.year = year ?? parsed.year
        vehicle.plate = trimmedOrNil(plate)
        vehicle.powertrain = powertrain
        vehicle.fuelKinds = orderedFuelKinds
        vehicle.tankCapacityL = isElectric ? nil : capacityValue
        vehicle.batteryCapacityKWh = isElectric ? capacityValue : nil
        vehicle.homeCurrency = homeCurrency
        vehicle.units = units
        vehicle.initialOdometer = odometerValue
        return vehicle
    }

    private func trimmedOrNil(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

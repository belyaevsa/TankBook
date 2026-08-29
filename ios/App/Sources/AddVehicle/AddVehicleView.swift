import PhotosUI
import SwiftUI
import TankbookCore
import UIKit

/// The Add car screen (P1.2), replacing the P1.1 placeholder. Reached from
/// Garage, Welcome and the Car switcher (docs/SCREENMAP.md); Save writes a
/// `Vehicle` through the repository and exits to the opener; back returns to
/// the opener. Matches design/screens/AddVehicle.dc.html and implements the
/// three ERRORS.md states (empty name, implausible odometer, catalog offline).
struct AddVehicleView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var form = AddVehicleFormState()
    @FocusState private var focus: AddVehicleFocus?
    @State private var catalogEntries: [VehicleCatalogEntry] = []
    @State private var catalogUnavailable = false
    @State private var photoItem: PhotosPickerItem?

    private let units = AddVehicleFormState.units()

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                VehiclePhotoTile(photo: $form.photo, photoItem: $photoItem)
                VehicleIdentityCard(name: $form.name, makeModel: $form.makeModel,
                                    plate: $form.plate, make: $form.make,
                                    model: $form.model, year: $form.year,
                                    focus: $focus, showNameWarning: form.showNameWarning,
                                    idPrefix: "addVehicle")
                AddVehicleCatalogArea(form: $form, focus: $focus,
                                      entries: catalogEntries,
                                      unavailable: catalogUnavailable,
                                      units: units,
                                      onApply: apply)
                section("Powertrain") {
                    VehiclePowertrainPicker(powertrain: $form.powertrain,
                                            selectedFuelKinds: $form.selectedFuelKinds)
                }
                section("Fuel") {
                    VehicleFuelPills(powertrain: $form.powertrain,
                                     selectedFuelKinds: $form.selectedFuelKinds)
                }
                AddVehicleOdometerCard(form: $form, focus: $focus, units: units)
                improvesAccuracySection
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.Palette.midnight)
        .safeAreaInset(edge: .bottom) { saveBar }
        .task { await loadCatalog() }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionEyebrow(title)
            content()
        }
    }

    private var improvesAccuracySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionEyebrow("Improves accuracy") {
                Text("· optional")
                    .font(.caption)
                    .textCase(.none)
                    .tracking(0)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            AddVehicleAccuracyCard(form: $form, focus: $focus, units: units)
        }
    }

    /// Selecting a suggestion copies catalog values into the form; every one
    /// stays user-overridable (docs/SCHEMA.md -> Vehicle catalog).
    func apply(_ prefill: CatalogPrefill) {
        form.makeModel = "\(prefill.make) · \(prefill.model) · \(prefill.year)"
        form.make = prefill.make
        form.model = prefill.model
        form.year = prefill.year
        if form.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            form.name = "\(prefill.make) \(prefill.model)"
        }
        form.powertrain = prefill.powertrain
        // The catalog's fuelKinds is an OFFER SET - what the model line is sold
        // with - not what this car takes (docs/SCHEMA.md -> Vehicle catalog).
        // "Volvo V60 -> [petrol95, diesel]" means petrol OR diesel; copying both
        // onto the Vehicle creates a car that accepts two fuels, which no car
        // does, and then prints "95" on every log row forever. Select ONE by
        // default; the chip row already offers every other kind the powertrain
        // allows, so the alternatives stay one tap away - the app suggests, the
        // user decides (hard rule 13).
        form.selectedFuelKinds = Set(prefill.fuelKinds.prefix(1))
        if let tank = prefill.tankCapacityL {
            form.capacity = AddVehicleSupport.capacityText(tank)
        } else if let battery = prefill.batteryCapacityKWh {
            form.capacity = AddVehicleSupport.capacityText(battery)
        }
        focus = nil
    }

    // MARK: - Save

    private var saveBar: some View {
        Button(action: save) {
            Text(saveTitle)
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.Palette.midnight)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.Palette.taillight)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .shadow(color: Theme.Palette.taillight.opacity(0.3), radius: 18, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("addVehicleSaveButton")
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Theme.Palette.midnight)
    }

    private var saveTitle: LocalizedStringKey {
        form.name.isEmpty ? "Add car" : "Add \(form.name)"
    }

    func save() {
        guard !form.name.isEmpty else {
            form.saveAttempted = true
            return
        }
        form.saveAttempted = true
        do {
            let result = try buildVehicle()
            let repository = try AppStore.repository()
            if let attachment = result.attachment {
                try repository.upsertAttachment(attachment)
            }
            try repository.upsertVehicle(result.vehicle)
            dismiss()
        } catch {
            AppLog.error(operation: "addVehicle.save", category: .ui, error: error)
        }
    }

    func buildVehicle() throws -> (vehicle: Vehicle, attachment: Attachment?) {
        let now = Date()
        var attachment: Attachment?
        var photoID: AttachmentID?
        if let photo = form.photo {
            let id = UUID.v7()
            let ref = try VehiclePhotoStore.save(photo, id: id)
            attachment = Attachment(id: id, createdAt: now, updatedAt: now, deletedAt: nil,
                                    kind: .photo,
                                    file: LocalFileRef(sha256: ref.sha256, relativePath: ref.relativePath),
                                    extractedTimestamp: nil, ocrText: nil)
            photoID = id
        }
        let parsed = MakeModelParser.parse(form.makeModel)
        let capacityValue = form.capacity.isEmpty ? nil : Double(form.capacity)
        let isElectric = form.powertrain == .ev
        let vehicle = Vehicle(
            id: UUID.v7(),
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            name: form.name.trimmingCharacters(in: .whitespacesAndNewlines),
            make: form.make ?? parsed.make,
            model: form.model ?? parsed.model,
            year: form.year ?? parsed.year,
            plate: trimmedOrNil(form.plate),
            powertrain: form.powertrain,
            fuelKinds: orderedFuelKinds,
            tankCapacityL: isElectric ? nil : capacityValue,
            batteryCapacityKWh: isElectric ? capacityValue : nil,
            homeCurrency: form.homeCurrency,
            units: units,
            photo: photoID,
            archived: false,
            paceLimitKmPerDay: 1500,
            initialOdometer: form.odometerValue)
        return (vehicle, attachment)
    }

    private var orderedFuelKinds: [FuelKind] {
        form.selectedFuelKinds.sorted { lhs, rhs in
            (FuelKind.allCases.firstIndex(of: lhs) ?? 0) < (FuelKind.allCases.firstIndex(of: rhs) ?? 0)
        }
    }

    private func trimmedOrNil(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func loadCatalog() async {
        if ProcessInfo.processInfo.arguments.contains("-forceCatalogUnavailable") {
            catalogUnavailable = true
            return
        }
        if let entries = try? VehicleCatalogStore.bundledEntries() {
            catalogEntries = entries
        } else {
            catalogUnavailable = true
        }
    }
}

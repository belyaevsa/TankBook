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
    @Environment(AppToastCenter.self) private var toastCenter

    @State private var form = AddVehicleFormState()
    @FocusState private var focus: AddVehicleFocus?
    @State private var catalogEntries: [VehicleCatalogEntry] = []
    @State private var catalogUnavailable = false
    @State private var photoItem: PhotosPickerItem?
    /// The exact text the last applied suggestion wrote into `form.makeModel`
    /// (nil when none has). RV.67: the suggestion list's visibility is decided
    /// from the field text + this applied state (`ModelSuggestionGate`), never
    /// from focus - see AddVehicleSections.swift.
    @State private var acceptedModelText: String?

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
                AddVehicleCatalogArea(form: $form,
                                      showsSuggestions: showsModelSuggestions,
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
        #if DEBUG
        .task { await presentModelSuggestionsIfRequested() }
        #endif
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

    /// Whether the live catalog suggestion list is mounted. RV.67: decided
    /// from the field text and the applied state - "the user is choosing a
    /// model" - NOT from `focus == .makeModel`, so the scroll gesture that
    /// dismisses the keyboard can no longer unmount the very list it was
    /// reaching for.
    private var showsModelSuggestions: Bool {
        ModelSuggestionGate.shouldShow(query: form.makeModel, accepted: acceptedModelText)
    }

    /// Selecting a suggestion copies catalog values into the form; every one
    /// stays user-overridable (docs/SCHEMA.md -> Vehicle catalog).
    func apply(_ prefill: CatalogPrefill) {
        let canonical = "\(prefill.make) · \(prefill.model) · \(prefill.year)"
        // Record the applied text BEFORE the field holds it: the suggestion
        // list unmounts the moment query == accepted (ModelSuggestionGate),
        // so the user can see what they just chose instead of a re-filtered
        // list of near-matches.
        acceptedModelText = canonical
        form.makeModel = canonical
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
            // The catalog stores litres; the form field reads in the user's
            // volume unit (RV.69). Un-converted, a gallons user saw "50" beside
            // a "gal" label and got a 50 L tank for a ~190 L figure they could
            // not question - a wrong fact, inverting hard rule 13.
            form.capacity = AddVehicleSupport.tankCapacityText(litres: tank, unit: units.volume)
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
            // RV.25: a saved car must reach every listener (Garage especially) -
            // the tab roots stay mounted, so only this revision bump tells them
            // a car was added; without it a new car never appears in Garage
            // until a relaunch (reads as data loss).
            toastCenter.noteEntryChanged()
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
            // The field holds the user's display unit; `tankCapacityL` stores
            // litres, so the figure converts back at the boundary (RV.69).
            tankCapacityL: isElectric ? nil
                : capacityValue.map { AddVehicleSupport.tankCapacityLitres(display: $0, unit: units.volume) },
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

    #if DEBUG
    /// RV.67 screenshot hook `-addVehicleModelSuggestions`: focuses the
    /// Make · model field and puts a five-row query ("Lada") in it, so a
    /// capture shows the suggestion list WITH the keyboard raised - the exact
    /// state the RV.67 bug lives in (the lower rows sit under the keyboard).
    /// simctl cannot tap or type, so the state a screenshot needs is driven
    /// here, like the other DEBUG hooks. The text is set first and the focus
    /// lands a beat later, once the screen is on screen, so the keyboard
    /// actually raises.
    private func presentModelSuggestionsIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("-addVehicleModelSuggestions") else { return }
        try? await Task.sleep(nanoseconds: 700_000_000)
        form.makeModel = "Lada"
        focus = .makeModel
    }
    #endif
}

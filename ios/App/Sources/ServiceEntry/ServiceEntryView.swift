import os
import SwiftUI
import TankbookCore

/// The ServiceEntry sheet (P3.1a): the typed path for a service visit
/// (docs/JOURNEYS.md J7). The scanned invoice path (P3.1b) drops in later as a
/// pre-fill of these same fields - the same screen, never a second one
/// (hard rule 15 - manual and scan are peer paths).
///
/// Matches design/screens/ServiceEntry.dc.html: the mode row, the vendor + total
/// header, the Date / Odometer card (odometer pre-filled from the last known
/// value and editable - hard rule 13), line items with category and cost, "Add
/// line item", and "Save service". A record with one uncategorized item carrying
/// the whole total saves exactly like a multi-item one - nothing pushes the user
/// to itemize (J7).
struct ServiceEntryView: View {
    @Binding var hasUnsavedChanges: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCarSelection.self) private var carSelection

    @State private var form = ServiceEntryFormState()
    @FocusState private var focus: ServiceEntryFocus?
    @State private var vehicle: Vehicle?
    @State private var showDatePicker = false
    @State private var didLoad = false
    @State private var lastKnownOdometer: Int?

    private static let log = Logger(subsystem: "app.tankbook", category: "serviceEntry")

    private var distanceUnit: DistanceUnit { vehicle?.units.distance ?? .km }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                if vehicle == nil {
                    noVehicleCard
                } else {
                    ServiceEntryModeRow()
                    ServiceEntryHeader(vendor: $form.vendor, totalText: totalText)
                    ServiceEntryDateOdometerCard(
                        form: $form,
                        focus: $focus,
                        distanceUnit: distanceUnit,
                        showDatePicker: $showDatePicker,
                        odometerRequired: form.requiresOdometer,
                        onFillOdometer: fillOdometer)
                    if showDatePicker {
                        DatePicker("", selection: $form.date, in: ...Date(),
                                   displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .accessibilityIdentifier("serviceEntryDatePicker")
                            .padding(.horizontal, Theme.Spacing.cardPadding)
                    }
                    ForEach($form.items) { $item in
                        ServiceEntryItemCard(item: $item) {
                            form.items.removeAll { $0.id == item.id }
                        }
                    }
                    ServiceEntryAddItemButton(action: addItem)
                    ServiceEntryNoteRow(note: $form.note)
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.Palette.midnight)
        .safeAreaInset(edge: .bottom) { saveBar }
        .task { await load() }
        .onChange(of: form, initial: true) { _, _ in
            hasUnsavedChanges = form.hasEdits()
        }
    }

    // MARK: - Derived

    private var totalText: String {
        let symbol = AddVehicleSupport.currencySymbol(for: vehicle?.homeCurrency ?? .eur)
        return HomeFormat.entryAmount(form.totalDecimal, symbol: symbol)
    }

    private var odometerMissing: Bool {
        form.requiresOdometer && form.odometerValue == nil
    }

    private var saveEnabled: Bool {
        guard vehicle != nil else { return false }
        guard form.hasTitledItem else { return false }
        return !odometerMissing
    }

    // MARK: - Actions

    private func addItem() {
        form.items.append(ServiceEntryItemDraft())
    }

    private func fillOdometer() {
        form.odometer = lastKnownOdometer.map(OdometerFormat.grouped) ?? ""
    }

    // MARK: - Loading

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        ServiceEntryTestSeed.seedIfRequested()
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            guard let vehicle = carSelection.selectedVehicle(vehicles) else { return }
            self.vehicle = vehicle
            let existingEntries = try repository.liveEntries(forVehicle: vehicle.id)
            let lastKnown = existingEntries.compactMap(\.odometer).max() ?? vehicle.initialOdometer
            lastKnownOdometer = lastKnown
            form.odometer = lastKnown.map(OdometerFormat.grouped) ?? ""
            if let prefill = ServiceEntryPrefillSeed.from(arguments: ProcessInfo.processInfo.arguments) {
                apply(prefill)
            }
            // Snapshots are taken AFTER the convenience pre-fills (odometer,
            // date, seed) - none of them count as an edit.
            form.initialVendor = form.vendor
            form.initialItems = form.items
            form.initialOdometer = form.odometer
            form.initialDate = form.date
            form.initialNote = form.note
        } catch {
            Self.log.error("Service entry load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The scanned-path seam (P3.1b): the extraction becomes default input the
    /// user edits. Whatever it produces stays editable at the moment it is
    /// offered and afterwards (hard rule 13).
    private func apply(_ prefill: ServiceEntryPrefill) {
        form.vendor = prefill.vendor
        form.items = prefill.items
        if !prefill.odometer.isEmpty {
            form.odometer = prefill.odometer
        }
        form.date = prefill.date
    }

    // MARK: - Save

    private func save() {
        guard let vehicle, saveEnabled else { return }
        do {
            let repository = try AppStore.repository()
            let draft = form.draft(vehicle: vehicle)
            try repository.upsertServiceRecord(
                draft.build(vehicleId: vehicle.id, homeCurrency: vehicle.homeCurrency))
            hasUnsavedChanges = false
            dismiss()
        } catch {
            Self.log.error("Service entry save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Save bar

    private var saveBar: some View {
        VStack(spacing: 8) {
            Button(action: save) {
                Text("Save service")
                    .font(.body.weight(.bold))
                    .foregroundStyle(saveEnabled ? Color.white : Theme.Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(saveEnabled ? Theme.Palette.taillight : Theme.Palette.dash)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .shadow(color: saveEnabled ? Theme.Palette.taillight.opacity(0.3) : .clear,
                            radius: 18, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(!saveEnabled)
            .accessibilityIdentifier("serviceEntrySaveButton")

            if !saveEnabled && !form.hasTitledItem {
                Text("Add a line item to save")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("serviceEntrySaveHint")
            }
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Theme.Palette.midnight)
    }
}

// MARK: - Focus

/// Which ServiceEntry field holds focus (drives the cyan underline).
enum ServiceEntryFocus: Hashable {
    case odometer
}

// MARK: - No-vehicle hint

extension ServiceEntryView {
    private var noVehicleCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "car")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("No car yet – add one from Garage to start logging services.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .accessibilityIdentifier("serviceEntryNoVehicleHint")
    }
}

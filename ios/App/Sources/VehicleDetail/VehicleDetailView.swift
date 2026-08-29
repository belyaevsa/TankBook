import os
import PhotosUI
import SwiftUI
import TankbookCore
import UIKit

/// The Vehicle detail screen (P1.12) - per-car settings, editable. Reached from
/// the Garage tab, the Car switcher's archived row, the limit sheet's "Archive
/// a car" and `-presentScreen vehicleDetail` (docs/SCREENMAP.md).
///
/// This is the screen that makes hard rule 13 ("the app suggests, the user
/// decides") real: every value Add car pre-filled from the catalog or the
/// locale - name, make/model/year, plate, powertrain, fuel kinds, tank/battery
/// capacity, home currency, units, `initialOdometer`, photo - is editable here,
/// again and for good. Per-car settings live on the car, never in Settings
/// (docs/DESIGN.md). A user's edit is theirs permanently: nothing here stores a
/// catalog id for a later pack to rewrite, and the sync layer's field-level
/// merge (SYNC.md S9) is the guarantee that a stale device cannot revert it.
///
/// Archiving (J13) keeps history and drops the car from active stats; delete is
/// the one place red lives - a system confirmation that tombstones the car and
/// every entry, so Recently deleted can restore them (hard rule 8, nothing lost
/// silently). Editing `tankCapacityL` changes real maths (partial-fill
/// adjustment, P1.9) and the save triggers a full-vehicle recompute - the
/// headline before and after come from the engine and the delta toast shows
/// only when a figure actually changed (hard rule 2, docs/SCHEMA.md,
/// Recalculation on edit).
struct VehicleDetailView: View {
    /// The vehicle being edited; nil falls back to the selected car
    /// (placeholder links, `-presentScreen vehicleDetail`, the limit sheet's
    /// "Archive a car").
    let vehicleID: UUID?

    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(AppCarSelection.self) private var carSelection
    @Environment(ReminderNotificationCoordinator.self) private var notificationCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var form = VehicleDetailFormState()
    @State private var vehicle: Vehicle?
    @State private var photoItem: PhotosPickerItem?
    @State private var showDeleteConfirm = false
    @State private var didLoad = false
    @State private var loadFailed = false
    @FocusState private var focus: AddVehicleFocus?

    private static let log = Logger(subsystem: "app.tankbook", category: "vehicleDetail")

    var body: some View {
        Group {
            if loadFailed {
                notFound
            } else if let vehicle {
                formView(vehicle)
            } else {
                Color.clear
            }
        }
        .background(Theme.Palette.midnight)
        .task { await load() }
        .alert("Delete this car?",
               isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It moves to Recently deleted for 30 days, and so does every entry.")
        }
    }

    // MARK: - Content

    private func formView(_ vehicle: Vehicle) -> some View {
        ScrollView {
            VStack(spacing: 9) {
                VehicleDetailHeader(vehicle: vehicle,
                                    onArchive: toggleArchive,
                                    onDelete: { showDeleteConfirm = true })
                if vehicle.archived {
                    VehicleDetailArchivedBanner(vehicle: vehicle)
                }
                VehiclePhotoTile(photo: $form.photo, photoItem: $photoItem)
                VehicleIdentityCard(name: $form.name, makeModel: $form.makeModel,
                                    plate: $form.plate, make: $form.make,
                                    model: $form.model, year: $form.year,
                                    focus: $focus, showNameWarning: form.showNameWarning,
                                    idPrefix: "vehicleDetail")
                section("Powertrain") {
                    VehiclePowertrainPicker(powertrain: $form.powertrain,
                                            selectedFuelKinds: $form.selectedFuelKinds,
                                            idPrefix: "vehicleDetail")
                }
                section("Fuel") {
                    VehicleFuelPills(powertrain: $form.powertrain,
                                     selectedFuelKinds: $form.selectedFuelKinds,
                                     idPrefix: "vehicleDetail")
                }
                VehicleDetailOdometerCard(form: $form, focus: $focus, units: form.units)
                section("Tire sets") {
                    NavigationLink(value: Route.tireSets) {
                        HStack {
                            Text("Tire sets")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Palette.ink)
                            Spacer(minLength: 8)
                            Text("Manage sets and swap history")
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.inkSoft)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(Theme.Palette.inkSoft)
                        }
                        .padding(.horizontal, Theme.Spacing.cardPadding)
                        .padding(.vertical, 12)
                        .formCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("vehicleDetailTireSetsLink")
                }
                section("Your data") {
                    VehicleExportRow(vehicle: vehicle)
                }
                section("Improves accuracy") {
                    VehicleDetailAccuracyCard(form: $form, focus: $focus)
                }
                hint
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .bottom) { saveBar }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionEyebrow(title)
            content()
        }
    }

    /// The honest consequence, stated once (docs/SCHEMA.md, Recalculation on
    /// edit): capacity and units feed the maths, so editing them recomputes.
    private var hint: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .padding(.top, 1)
            Text("Edits recalculate consumption for this and the next fill-up.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityIdentifier("vehicleDetailRecomputeHint")
    }

    private var notFound: some View {
        VStack(spacing: 8) {
            Image(systemName: "car.side")
                .font(.title3)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("Car not found")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("It may have been deleted on another device.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .formCard()
        .padding(.horizontal, Theme.Spacing.screenMargin)
    }

    // MARK: - Save

    private var saveBar: some View {
        Button(action: save) {
            Text("Save changes")
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.Palette.midnight)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.Palette.taillight)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .shadow(color: Theme.Palette.taillight.opacity(0.3), radius: 18, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vehicleDetailSaveButton")
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Theme.Palette.midnight)
    }

    func save() {
        guard let vehicle,
              !form.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            form.saveAttempted = true
            return
        }
        form.saveAttempted = true
        do {
            let repository = try AppStore.repository()
            let before = headline(repository: repository, vehicle: vehicle)
            var updated = form.applying(to: vehicle)
            if let photo = form.photo {
                if photo == form.originalPhotoData, let originalID = form.originalPhotoID {
                    updated.photo = originalID
                } else {
                    let id = UUID.v7()
                    let now = Date()
                    let ref = try VehiclePhotoStore.save(photo, id: id)
                    let attachment = Attachment(id: id, createdAt: now, updatedAt: now,
                                                deletedAt: nil, kind: .photo,
                                                file: LocalFileRef(sha256: ref.sha256,
                                                                   relativePath: ref.relativePath),
                                                extractedTimestamp: nil, ocrText: nil)
                    try repository.upsertAttachment(attachment)
                    updated.photo = id
                }
            } else {
                updated.photo = nil
            }
            try repository.upsertVehicle(updated)
            let after = headline(repository: repository, vehicle: updated)
            notify(before: before, after: after, vehicle: updated)
            dismiss()
        } catch {
            Self.log.error("Vehicle detail save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The recompute, both halves from the engine (docs/SCHEMA.md,
    /// Recalculation on edit): a full-vehicle recompute follows any vehicle
    /// edit, and the delta toast reports only a figure that actually moved.
    private func headline(repository: TankbookRepository, vehicle: Vehicle) -> Headline? {
        guard let fills = try? repository.liveFillUps(forVehicle: vehicle.id) else { return nil }
        let pairs = DuplicateDetector.pairs(
            in: fills,
            resolved: (try? repository.resolvedDuplicateKeys()) ?? [])
        let excluded = Set(pairs.map(\.excludedID))
        let counting = fills.filter { !excluded.contains($0.id) }
        let segments = ConsumptionEngine.recompute(fills: counting, tankCapacityL: vehicle.tankCapacityL)
        return ConsumptionEngine.headline(segments: segments, asOf: Date())
    }

    private func notify(before: Headline?, after: Headline?, vehicle: Vehicle) {
        if let message = EditConsumptionDelta.message(before: before, after: after,
                                                      unit: vehicle.units.consumption) {
            toastCenter.show(message)
        } else {
            toastCenter.noteEntryChanged()
        }
    }

    // MARK: - Archive / unarchive (J13)

    /// Archiving is reversible (Unarchive restores the car to active stats), so
    /// it acts immediately - no confirmation, exactly the asymmetry a
    /// reversible action deserves. Delete is the one place red lives.
    private func toggleArchive() {
        guard let vehicle else { return }
        do {
            let repository = try AppStore.repository()
            if vehicle.archived {
                try repository.unarchiveVehicle(id: vehicle.id)
            } else {
                try repository.archiveVehicle(id: vehicle.id)
                // An archived car's monthly summary has no reason to exist
                // (docs/NOTIFICATIONS.md -> Multi-device cleanup).
                Task { await notificationCoordinator.cancelMonthlySummary(forVehicle: vehicle.id) }
            }
            toastCenter.noteEntryChanged()
            reload()
        } catch {
            Self.log.error("Vehicle archive toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Delete (the destructive path)

    private func performDelete() {
        guard let vehicle else { return }
        do {
            let repository = try AppStore.repository()
            try repository.softDeleteVehicle(id: vehicle.id)
            // A deleted car's pending monthly summary must not fire on the 1st
            // (the plan only sees live vehicles, so the delete site cancels).
            Task { await notificationCoordinator.cancelMonthlySummary(forVehicle: vehicle.id) }
            toastCenter.noteEntryChanged()
            dismiss()
        } catch {
            Self.log.error("Vehicle delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Loading

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        VehicleDetailTestSeed.seedIfRequested()
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            let selected = carSelection.selectedVehicle(vehicles)
            let target = vehicleID.flatMap { id in vehicles.first { $0.id == id } } ?? selected
            guard let target else {
                loadFailed = true
                return
            }
            self.vehicle = target
            form.load(from: target, photoData: try loadPhoto(repository: repository, vehicle: target))
        } catch {
            Self.log.error("Vehicle detail load failed: \(error.localizedDescription, privacy: .public)")
            loadFailed = true
        }
    }

    private func reload() {
        do {
            let repository = try AppStore.repository()
            guard let vehicle else { return }
            guard let refreshed = try repository.vehicle(id: vehicle.id) else {
                loadFailed = true
                return
            }
            self.vehicle = refreshed
            form.load(from: refreshed, photoData: try loadPhoto(repository: repository, vehicle: refreshed))
        } catch {
            Self.log.error("Vehicle detail reload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadPhoto(repository: TankbookRepository, vehicle: Vehicle) throws -> Data? {
        guard let photoID = vehicle.photo else { return nil }
        let attachments = try repository.liveAttachments()
        guard let attachment = attachments.first(where: { $0.id == photoID }) else { return nil }
        let url = try VehiclePhotoStore.attachmentsDirectory()
            .appendingPathComponent(attachment.file.relativePath)
        return try? Data(contentsOf: url)
    }
}

// MARK: - Accuracy card (capacity + units)

/// The "Improves accuracy · optional" card on the detail screen: the
/// tank/battery capacity row (shared with Add car) and the units editor - the
/// per-car settings DESIGN.md says live here, not in Settings.
struct VehicleDetailAccuracyCard: View {
    @Binding var form: VehicleDetailFormState
    @FocusState.Binding var focus: AddVehicleFocus?

    var body: some View {
        VStack(spacing: 0) {
            VehicleCapacityField(capacity: $form.capacity,
                                 isElectric: form.isElectric,
                                 volumeUnit: form.units.volume,
                                 focus: $focus, idPrefix: "vehicleDetail")
            CardDivider()
            VehicleUnitsEditor(units: $form.units)
        }
        .formCard()
    }
}

// MARK: - UI-test seeding

/// UI-test DB seeding for the Vehicle detail screen. Reuses the Car switcher
/// seed (`-seedHomeCarSwitcher`) for a populated detail state: the Volvo has
/// every catalog-derived field (capacity, fuel kinds, units, initial odometer),
/// the ID.4 the EV variant, and the BMW an archived car with history - so the
/// archived-at flow is exercised against a real row. The reset and the
/// idempotence guard live in HomeTestSeed, exactly like the switcher.
enum VehicleDetailTestSeed {
    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(where: { $0.hasPrefix("-seedHome") })
            || arguments.contains("-homeResetDatabase") else { return }
        HomeTestSeed.seedIfRequested()
    }
}

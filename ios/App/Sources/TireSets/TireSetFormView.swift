import SwiftUI
import TankbookCore

/// The tire-set form (P3.3) - create and rename (docs/SCREENMAP.md: Tire sets
/// -> New tire set -> Tire set form -> Save -> Tire sets). No artboard exists;
/// it derives from the DESIGN.md tokens and the ServiceEntry/Reminder forms it
/// sits beside - same card metrics, same eyebrow, same underline.
///
/// The one invariant the screen exists for: a tire set with no name is not a
/// set. Save refuses a blank name and names the next step (hard rule 7).
struct TireSetFormView: View {
    /// nil = create a new set; otherwise the set being renamed.
    var tireSetID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppCarSelection.self) private var carSelection

    @State private var form = TireSetFormState()
    @State private var vehicle: Vehicle?
    @State private var didLoad = false
    @State private var existing: TireSet?
    @FocusState private var nameFocused: Bool

    private var isEditing: Bool { tireSetID != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                if vehicle == nil {
                    noVehicleCard
                } else {
                    TireSetNameCard(name: $form.name, focused: $nameFocused)
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.Palette.midnight)
        .safeAreaInset(edge: .bottom) { saveBar }
        .navigationTitle(isEditing ? "Edit tire set" : "New tire set")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - Save

    private var saveEnabled: Bool {
        form.readiness == .ready
    }

    private var saveBar: some View {
        VStack(spacing: 8) {
            Button(action: save) {
                Text("Save tire set")
                    .font(.body.weight(.bold))
                    .foregroundStyle(saveEnabled ? Theme.Palette.midnight : Theme.Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(saveEnabled ? Theme.Palette.taillight : Theme.Palette.dash)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .shadow(color: saveEnabled ? Theme.Palette.taillight.opacity(0.3) : .clear,
                            radius: 18, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(!saveEnabled)
            .accessibilityIdentifier("tireSetSaveButton")

            if !saveEnabled {
                Text("Add a name to save")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("tireSetSaveHint")
            }
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Theme.Palette.midnight)
    }

    private func save() {
        guard let vehicle, saveEnabled else { return }
        do {
            let repository = try AppStore.repository()
            if let existing {
                try repository.upsertTireSet(form.draft.applied(to: existing))
            } else {
                try repository.upsertTireSet(form.draft.build(vehicleId: vehicle.id))
            }
            dismiss()
        } catch {
            AppLog.error(operation: "tireSetForm.save", category: .ui, error: error)
        }
    }

    // MARK: - Loading

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        #if DEBUG
        TireSetTestSeed.seedIfRequested()
        #endif
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            guard let vehicle = carSelection.selectedVehicle(vehicles) else { return }
            self.vehicle = vehicle
            if let tireSetID {
                existing = try repository.liveTireSets(forVehicle: vehicle.id)
                    .first { $0.id == tireSetID }
                if let existing {
                    form = TireSetFormState.from(tireSet: existing)
                }
            }
        } catch {
            AppLog.error(operation: "tireSetForm.load", category: .ui, error: error)
        }
    }

    private var noVehicleCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "car")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("No car yet – add one from Garage to start tire sets.")
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
        .accessibilityIdentifier("tireSetFormNoVehicleHint")
    }
}

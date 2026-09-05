import SwiftUI
import TankbookCore

/// The Reminder form (P3.4) - create and edit/reschedule (docs/SCREENMAP.md:
/// Reminders -->|New reminder| ReminderForm, ReminderForm -->|Save| Reminders,
/// and since RV.75 the merged list's "New reminder", design/screens/
/// ReminderForm.dc.html). It derives from docs/DESIGN.md tokens and the
/// ServiceEntry form it must sit beside - same card metrics, same eyebrow
/// labels, same field underlines - so it does not look like a different app.
///
/// **The car is the first field, and it is a default input, never a fact**
/// (hard rule 13, docs/SCREENMAP.md -> "the car as its first field"): the
/// merged list opens it with NO car chosen and Save inert until one is picked;
/// a car's own list opens it with that car chosen, still changeable. The
/// reminder itself can never be saved without a car.
///
/// The other invariant the screen exists for (docs/SCHEMA.md -> Reminder):
/// neither due field is mandatory on its own, but a reminder with neither is
/// not a reminder - Save refuses and names the next step (hard rule 7).
struct ReminderFormView: View {
    /// nil = create a new reminder; otherwise the reminder being edited.
    var reminderID: UUID?
    /// The car the OPENER named for a create (the per-car list's "New
    /// reminder"). `nil` when no car was named - the merged list's create opens
    /// the car field empty and required. Ignored for an edit, whose car comes
    /// from the reminder itself.
    var initialVehicleID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(ReminderNotificationCoordinator.self) private var notificationCoordinator

    @State private var form = ReminderFormState()
    @State private var vehicles: [Vehicle] = []
    @State private var selectedVehicleID: UUID?
    @State private var showDatePicker = false
    @State private var didLoad = false
    @State private var existing: Reminder?
    @FocusState private var focus: ReminderFormFocus?

    private var selectedVehicle: Vehicle? {
        guard let selectedVehicleID else { return nil }
        return vehicles.first { $0.id == selectedVehicleID }
    }

    private var distanceUnit: DistanceUnit { selectedVehicle?.units.distance ?? .km }
    private var isEditing: Bool { reminderID != nil }

    var body: some View {
        // The shared shell for any form with a confirmation button
        // (`ConfirmableFormScreen`): it pins the primary action and hides the
        // tab bar while the form is on screen, so the capture circle can no
        // longer sit on top of Save.
        ConfirmableFormScreen(
            confirmTitle: "Save reminder",
            isEnabled: saveEnabled,
            hint: saveEnabled ? nil : saveHint,
            identifier: "reminderFormSaveButton",
            action: save
        ) {
        ScrollView {
            VStack(spacing: 9) {
                if vehicles.isEmpty {
                    noVehicleCard
                } else {
                    ReminderFormCarCard(vehicles: carChoices,
                                        selectedVehicleID: selectedVehicleID,
                                        onSelect: { selectedVehicleID = $0 },
                                        showsCaption: !isEditing)
                    ReminderFormTitleCard(form: $form, focus: $focus)
                    ReminderFormCategoryCard(form: $form)
                    ReminderFormDueCard(form: $form, focus: $focus,
                                        distanceUnit: distanceUnit,
                                        showDatePicker: $showDatePicker)
                    if showDatePicker && form.hasDueDate {
                        DatePicker("", selection: $form.dueDate, in: Date()...,
                                   displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .accessibilityIdentifier("reminderFormDatePicker")
                            .padding(.horizontal, Theme.Spacing.cardPadding)
                    }
                    ReminderFormRecurrenceCard(form: $form)
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        }
        .navigationTitle(isEditing ? "Edit reminder" : "New reminder")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - The cars the field offers

    /// The chips the Car field draws: the ACTIVE garage. An archived car is a
    /// sold car (J13) - a new reminder on one would land on no merged list - so
    /// archived cars are offered only when EVERY car is archived (the one case
    /// where the per-car screen is showing an archived car and creating one for
    /// it is the honest thing to do).
    private var carChoices: [Vehicle] {
        let active = vehicles.filter { !$0.archived }
        return active.isEmpty ? vehicles : active
    }

    // MARK: - Save

    private var saveEnabled: Bool {
        // A reminder is about A car: nothing to save until one is picked, and
        // the draft's own readiness (title, a due field) still gates.
        selectedVehicleID != nil && form.readiness == .ready
    }

    private var saveHint: String {
        if selectedVehicleID == nil {
            return L10n.localize("Pick a car to save")
        }
        switch form.readiness {
        case .ready: return ""
        case .titleMissing: return L10n.localize("Add a title to save")
        case .noDueField: return L10n.localize("Add a due date or due odometer to save")
        }
    }

    private func save() {
        guard let vehicle = selectedVehicle, saveEnabled else { return }
        do {
            let repository = try AppStore.repository()
            if let existing {
                var updated = form.draft.applied(to: existing)
                // The car field is editable even in an edit: a reminder moved
                // to another car is saved for THAT car (hard rule 13 - never
                // silently keep the old one).
                if selectedVehicleID != existing.vehicleId {
                    updated.vehicleId = selectedVehicleID!
                }
                try repository.upsertReminder(updated)
            } else {
                try repository.upsertReminder(form.draft.build(vehicleId: vehicle.id))
            }
            // Arming: a create schedules its date notification and asks for
            // permission at this first moment it is needed (never at launch);
            // an edit/reschedule cancels the superseded notification and
            // schedules the new one (docs/NOTIFICATIONS.md). Runs against the
            // car the reminder now belongs to.
            let vehicleId = vehicle.id
            Task {
                if isEditing {
                    await notificationCoordinator.reconcile(vehicleId: vehicleId)
                } else {
                    await notificationCoordinator.requestPermissionIfFirstReminder(vehicleId: vehicleId)
                    await notificationCoordinator.reconcile(vehicleId: vehicleId)
                }
            }
            dismiss()
        } catch {
            AppLog.error(operation: "reminderForm.save", category: .notifications, error: error)
        }
    }

    // MARK: - Loading

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        #if DEBUG
        ReminderTestSeed.seedIfRequested()
        #endif
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            self.vehicles = vehicles
            if let reminderID {
                // The reminder being edited names its OWN car - never the
                // selected one (RV.75: an edit from the merged list can be any
                // car's row). The selected-car resolver is deliberately not
                // used here.
                existing = Self.resolveReminder(reminderID, vehicles: vehicles, repository: repository)
                if let existing {
                    selectedVehicleID = existing.vehicleId
                    form = ReminderFormState.from(reminder: existing)
                } else {
                    // A reminder that no longer exists (deleted on another
                    // device since the list was drawn) is a landing, not a dead
                    // end (hard rule 7): the form falls back to a create for
                    // whatever the opener named, or an empty car when nothing
                    // was named.
                    selectedVehicleID = initialVehicleID
                }
            } else {
                // Create: the opener's named car arrives chosen (still
                // changeable, hard rule 13); the merged list names none.
                selectedVehicleID = initialVehicleID
                #if DEBUG
                if let prefill = ReminderFormPrefillSeed.from(arguments: ProcessInfo.processInfo.arguments) {
                    apply(prefill)
                }
                #endif
            }
        } catch {
            AppLog.error(operation: "reminderForm.load", category: .notifications, error: error)
        }
    }

    /// Finds the reminder being edited across every live vehicle. There is no
    /// by-id repository query yet (RV.74 owns it); a per-vehicle search reuses
    /// only existing API and keeps the form correct for a reminder on any car,
    /// including when it is the SELECTED car's peer.
    private static func resolveReminder(_ reminderID: UUID,
                                        vehicles: [Vehicle],
                                        repository: TankbookRepository) -> Reminder? {
        for vehicle in vehicles {
            if let match = (try? repository.liveReminders(forVehicle: vehicle.id))?
                .first(where: { $0.id == reminderID }) {
                return match
            }
        }
        return nil
    }

    /// The screenshot seed: pre-fills a CREATE form so a simctl-driven capture
    /// shows a populated reminder without driving taps. The pre-fill is default
    /// input the user edits (hard rule 13) - and it is snapshotted, so opening
    /// and closing the form with just the pre-fill is not an edit. It never
    /// picks a car: the form the seed renders is the merged list's (car empty,
    /// Save inert) unless the opener named one.
    private func apply(_ prefill: ReminderFormPrefill) {
        form.title = prefill.title
        form.category = prefill.category
        form.hasDueDate = prefill.hasDueDate
        form.dueDate = prefill.dueDate
        form.dueOdometer = prefill.dueOdometer
        form.recurrenceEveryMonths = prefill.recurrenceEveryMonths
        form.recurrenceEveryKm = prefill.recurrenceEveryKm
        form.snapshotInitials()
    }

    private var noVehicleCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "car")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("No car yet – add one from Garage to start reminders.")
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
        .accessibilityIdentifier("reminderFormNoVehicleHint")
    }
}

// MARK: - Focus

enum ReminderFormFocus: Hashable {
    case title
    case odometer
}

// MARK: - Category labels

extension ReminderCategory {
    /// The fixed categories the form offers, in a stable order. `.other(String)`
    /// is the invoice-line free text, not a reminder category (docs/SCHEMA.md:
    /// reminder category is ServiceCategory | .insurance | .inspection | .custom).
    static let formCases: [ReminderCategory] = [
        .oil, .brakes, .tires, .battery, .filters, .inspection,
        .repair, .parts, .wash, .insurance, .custom
    ]

    /// A stable identifier token per category, used by accessibility
    /// identifiers (never user-visible copy).
    var rawLabel: String {
        switch self {
        case .oil: "oil"
        case .brakes: "brakes"
        case .tires: "tires"
        case .battery: "battery"
        case .filters: "filters"
        case .inspection: "inspection"
        case .repair: "repair"
        case .parts: "parts"
        case .wash: "wash"
        case .insurance: "insurance"
        case .custom: "custom"
        case .other: "other"
        }
    }

    /// The fixed-category display label, or nil for `.other` free text.
    var fixedLabelKey: LocalizedStringKey? {
        switch self {
        case .oil: "Oil"
        case .brakes: "Brakes"
        case .tires: "Tires"
        case .battery: "Battery"
        case .filters: "Filters"
        case .inspection: "Inspection"
        case .repair: "Repair"
        case .parts: "Parts"
        case .wash: "Wash"
        case .insurance: "Insurance"
        case .custom: "Custom"
        case .other: nil
        }
    }
}

/// Renders a reminder category's label through the catalogue (the `.other`
/// free text would be runtime data - this form never offers `.other`, so the
/// fixed key is always present).
struct ReminderCategoryLabel: View {
    let category: ReminderCategory

    var body: some View {
        if let key = category.fixedLabelKey {
            Text(key)
        } else {
            Text(category.rawLabel)
        }
    }
}

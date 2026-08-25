import os
import SwiftUI
import TankbookCore

/// The Reminder form (P3.4) - create and edit/reschedule (docs/SCREENMAP.md:
/// Reminders -->|New reminder| ReminderForm, ReminderForm -->|Save| Reminders).
/// No artboard exists; it derives from docs/DESIGN.md tokens and the
/// ServiceEntry form it must sit beside - same card metrics, same eyebrow
/// labels, same field underlines - so it does not look like a different app.
///
/// The one invariant the screen exists for (docs/SCHEMA.md -> Reminder):
/// neither due field is mandatory on its own, but a reminder with neither is
/// not a reminder - Save refuses and names the next step (hard rule 7).
struct ReminderFormView: View {
    /// nil = create a new reminder; otherwise the reminder being edited.
    var reminderID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppCarSelection.self) private var carSelection

    @State private var form = ReminderFormState()
    @State private var vehicle: Vehicle?
    @State private var showDatePicker = false
    @State private var didLoad = false
    @State private var existing: Reminder?
    @FocusState private var focus: ReminderFormFocus?

    private static let log = Logger(subsystem: "app.tankbook", category: "reminderForm")

    private var distanceUnit: DistanceUnit { vehicle?.units.distance ?? .km }
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
                if vehicle == nil {
                    noVehicleCard
                } else {
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

    // MARK: - Save

    private var saveEnabled: Bool {
        form.readiness == .ready
    }


    private var saveHint: String {
        switch form.readiness {
        case .ready: ""
        case .titleMissing: L10n.localize("Add a title to save")
        case .noDueField: L10n.localize("Add a due date or due odometer to save")
        }
    }

    private func save() {
        guard let vehicle, saveEnabled else { return }
        do {
            let repository = try AppStore.repository()
            if let existing {
                try repository.upsertReminder(form.draft.applied(to: existing))
            } else {
                try repository.upsertReminder(form.draft.build(vehicleId: vehicle.id))
            }
            dismiss()
        } catch {
            Self.log.error("Reminder save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Loading

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        ReminderTestSeed.seedIfRequested()
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            guard let vehicle = carSelection.selectedVehicle(vehicles) else { return }
            self.vehicle = vehicle
            if let reminderID {
                existing = try repository.liveReminders(forVehicle: vehicle.id)
                    .first { $0.id == reminderID }
                if let existing {
                    form = ReminderFormState.from(reminder: existing)
                }
            } else if let prefill = ReminderFormPrefillSeed.from(arguments: ProcessInfo.processInfo.arguments) {
                apply(prefill)
            }
        } catch {
            Self.log.error("Reminder form load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The screenshot seed: pre-fills a CREATE form so a simctl-driven capture
    /// shows a populated reminder without driving taps. The pre-fill is default
    /// input the user edits (hard rule 13) - and it is snapshotted, so opening
    /// and closing the form with just the pre-fill is not an edit.
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

import os
import SwiftUI
import TankbookCore

// MARK: - Expense category cases

extension ExpenseCategory {
    /// The categories the Expense entry offers in the chooser, in a stable
    /// order. `.parts` is an ordinary category here - buying a part is just an
    /// expense, never a separate flow (docs/JOURNEYS.md J7b).
    static let entryCases: [ExpenseCategory] = [
        .insurance, .tax, .parking, .toll, .fine, .accessory, .parts, .other("")
    ]
}

// MARK: - Form state

/// Everything the Expense entry collects, plus the derived save gate. The typed
/// amount is the user's own digits, parsed to an exact `Decimal` on save (never
/// `Double`, docs/SCHEMA.md -> Money).
struct ExpenseEntryFormState: Equatable {
    var category: ExpenseCategory = .accessory
    var title = ""
    var amount = ""
    var date = Date()

    // Snapshots for the discard guard (SCREENMAP rule 1): the form is dirty only
    // for real edits, not the category pre-selection or the date default.
    var initialCategory: ExpenseCategory = .accessory
    var initialTitle = ""
    var initialAmount = ""
    var initialDate = Date()

    var amountDecimal: Decimal? {
        let trimmed = amount.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Decimal(string: trimmed)
    }

    var hasTitle: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Save gate: a title and a non-blank amount. Category always has a value.
    var canSave: Bool { hasTitle && amountDecimal != nil }

    func hasEdits() -> Bool {
        if category != initialCategory { return true }
        if title != initialTitle || amount != initialAmount { return true }
        if !Calendar.current.isDate(date, inSameDayAs: initialDate) { return true }
        return false
    }
}

// MARK: - Expense entry sheet

/// The Expense entry (P3.2): category, title, money and date - reachable as a
/// peer of the service path from the "Service & expenses" surface (hard rule
/// 15). `.parts` is an ordinary category, so buying a part and buying insurance
/// are the same form.
struct ExpenseEntryView: View {
    @Binding var hasUnsavedChanges: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCarSelection.self) private var carSelection
    @Environment(ExpenseEntrySession.self) private var expenseSession
    @Environment(ReminderCompletionSession.self) private var completionSession
    @Environment(ReminderNotificationCoordinator.self) private var notificationCoordinator

    @State private var form = ExpenseEntryFormState()
    @State private var vehicle: Vehicle?
    @State private var showDatePicker = false
    @State private var didLoad = false
    /// A reminder completion handed off by the ReminderComplete sheet (P3.5):
    /// pre-fills this form and, on save, completes the reminder with the
    /// entry's real id. Consumed at load; held locally for the save.
    @State private var pendingCompletion: ReminderCompletionSession.Pending?

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                if vehicle == nil {
                    noVehicleCard
                } else {
                    categoryCard
                    titleCard
                    amountCard
                    ManualFillUpDateRow(date: $form.date, showDatePicker: $showDatePicker)
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

    // MARK: - Cards

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow("Category")
            Menu {
                ForEach(ExpenseCategory.entryCases, id: \.self) { category in
                    Button {
                        form.category = category
                    } label: {
                        Text(L10n.expenseCategoryLabel(category))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(L10n.expenseCategoryLabel(form.category))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }
            .accessibilityIdentifier("expenseEntryCategory")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 12)
        .formCard()
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow("Title")
            TextField("e.g. Oil filter", text: $form.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityIdentifier("expenseEntryTitleField")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 12)
        .formCard()
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow("Amount")
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField("0.00", text: $form.amount)
                    .keyboardType(.decimalPad)
                    .font(.custom(AppFonts.dinAlternateBold, size: 24))
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityIdentifier("expenseEntryAmountField")
                Text(AddVehicleSupport.currencySymbol(for: vehicle?.homeCurrency ?? .eur))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 12)
        .formCard()
    }

    // MARK: - Save

    private var saveEnabled: Bool {
        vehicle != nil && form.canSave
    }

    private func save() {
        guard let vehicle, saveEnabled, let amount = form.amountDecimal else { return }
        do {
            let repository = try AppStore.repository()
            let now = Date()
            let expense = Expense(
                id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
                vehicleId: vehicle.id, date: form.date, odometer: nil,
                money: Money(amount: amount, currency: vehicle.homeCurrency,
                             homeCurrency: vehicle.homeCurrency),
                note: nil, attachments: [], provenance: .manual, conflict: .none,
                purchaseGroupId: nil, category: form.category, title: form.title,
                recurrence: nil, installedInServiceId: nil)
            try repository.upsertExpense(expense)
            // The other half of the P3.5 chain: a reminder completion handed
            // off by the ReminderComplete sheet completes with THIS entry's id.
            if let pending = pendingCompletion {
                ReminderCompletionSession.persistCompletion(
                    reminder: pending.reminder, entryId: expense.id,
                    completionDate: pending.completionDate,
                    completionOdometer: pending.completionOdometer,
                    coordinator: notificationCoordinator)
                pendingCompletion = nil
            }
            hasUnsavedChanges = false
            dismiss()
        } catch {
            Self.log.error("Expense entry save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static let log = os.Logger(subsystem: "app.tankbook", category: "expenseEntry")

    private var saveBar: some View {
        VStack(spacing: 8) {
            Button(action: save) {
                Text("Save expense")
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
            .accessibilityIdentifier("expenseEntrySaveButton")
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Theme.Palette.midnight)
    }

    // MARK: - Loading

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        PartsShelfTestSeed.seedIfRequested()
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            guard let vehicle = carSelection.selectedVehicle(vehicles) else { return }
            self.vehicle = vehicle
            // The category pre-selection from the mode row ("Parts" -> .parts)
            // is a default input the user edits (hard rule 13), never a lock.
            if let preset = expenseSession.pendingPreset {
                form.category = preset
                expenseSession.pendingPreset = nil
            }
            // The ReminderComplete sheet's "Type amount" hand-off (P3.5): an
            // insurance reminder pre-fills the category and title - default
            // input the user edits. Consumed here; save completes the reminder.
            if let pending = completionSession.pending,
               case .expense(let category) = ReminderCompletion.entryKind(for: pending.reminder.category) {
                pendingCompletion = pending
                completionSession.pending = nil
                form.category = category
                form.title = pending.reminder.title
                form.date = pending.completionDate
            }
            // Snapshots taken AFTER the pre-selection - it does not count as an edit.
            form.initialCategory = form.category
            form.initialTitle = form.title
            form.initialAmount = form.amount
            form.initialDate = form.date
        } catch {
            Self.log.error("Expense entry load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var noVehicleCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "car")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("No car yet – add one from Garage to start logging expenses.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 0)
        }
        .padding(14)
        .formCard()
        .accessibilityIdentifier("expenseEntryNoVehicleHint")
    }
}

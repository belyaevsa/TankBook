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

    /// Save gate: a non-blank amount. The category always has a value, and the
    /// Log row names the expense from it when the title is empty (RV.187), so a
    /// title is never required to save. Even the bare `.other("")` renders the
    /// localized "Other" - a real category label the user can edit afterwards
    /// (RV.195), never an unnamed row.
    var canSave: Bool { amountDecimal != nil }

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
    /// RV.12: the presenter's after-a-successful-save hook. Capture passes a
    /// closure that closes its own modal so the "Type it" door does not
    /// uncover the camera on Save; every other presenter leaves it empty and
    /// nothing changes. Never called for a cancel or a save that threw.
    var onSaved: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(AppCarSelection.self) private var carSelection
    @Environment(ExpenseEntrySession.self) private var expenseSession
    @Environment(ReminderCompletionSession.self) private var completionSession
    @Environment(ReminderNotificationCoordinator.self) private var notificationCoordinator
    @Environment(ReminderOfferSession.self) private var offerSession

    @State private var form = ExpenseEntryFormState()
    @State private var vehicle: Vehicle?
    @State private var showDatePicker = false
    @State private var didLoad = false
    /// RV.267: set the moment a save lands, so the one dismissal path can tell
    /// a save (the capture is consumed by its record) from a cancel (take the
    /// staged scan with it).
    @State private var didSave = false
    /// PJ.28: the receipt photo an Expense-mode scan produced, consumed from the
    /// session on load and held here until Save persists it. `nil` is the typed
    /// path (hard rule 15): no photo, and nothing about this save changes.
    @State private var scan: ExpenseScanCapture?
    /// A reminder completion handed off by the ReminderComplete sheet (P3.5):
    /// pre-fills this form and, on save, completes the reminder with the
    /// entry's real id. Consumed at load; held locally for the save.
    @State private var pendingCompletion: ReminderCompletionSession.Pending?
    /// RV.200: the category a scan suggested, held so the save can report
    /// whether the user kept it (`expense.category.suggest`, shape only). Nil
    /// when nothing suggested a kind - the typed path and an unrecognised scan
    /// alike - so "no suggestion" is distinguishable from "suggestion kept".
    @State private var suggestedCategory: ExpenseCategory?

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
        // RV.267: the sheet's one dismissal path. The X, a swipe-down and any
        // discard prompt end here; a save sets `didSave` first and keeps the
        // capture its record consumed. A scan staged a photo and a pre-fill with
        // no owning record, so a close without a save must clear them before the
        // next open reads them (hard rule 8).
        .onDisappear {
            guard !didSave else { return }
            Self.discardStagedScan(expenseSession)
        }
        .onChange(of: form, initial: true) { _, _ in
            hasUnsavedChanges = form.hasEdits()
        }
        // RV.215: a deferred read that finishes before the save fills the open
        // form. It never overwrites a value the user already changed (hard rule
        // 13); a read that finishes after the save routes to the inbox instead
        // (`markSaved`), never here.
        .onChange(of: expenseSession.scanRevision) { _, _ in
            // RV.243: the photograph the read carries is the SAME one staged at
            // scan start, so it is always consumed - a user edit suppresses the
            // read's VALUES, never its photo (hard rule 8).
            if let capture = expenseSession.consumePendingCapture() {
                scan = capture
            }
            guard !form.hasEdits() else { return }
            if let prefill = expenseSession.pendingPrefill {
                apply(prefill)
                expenseSession.pendingPrefill = nil
            }
            if let preset = expenseSession.pendingPreset {
                form.category = preset
                suggestedCategory = preset
                expenseSession.pendingPreset = nil
            }
            form.initialCategory = form.category
            form.initialTitle = form.title
            form.initialAmount = form.amount
            form.initialDate = form.date
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
                    .numericInput($form.amount, kind: .decimal)
                Text(AddVehicleSupport.moneySymbol(for: vehicle?.homeCurrency ?? .eur))
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

    /// The stored row `save()` writes, as a value. Extracted so the save gate
    /// and the persisted shape are reachable from L1 without driving the view's
    /// private `save()` (the RV.202 seam). The title is written exactly as
    /// typed - empty when the user left it blank, because the category names
    /// the row (RV.187) and the gate no longer demands one (RV.206).
    static func storedExpense(form: ExpenseEntryFormState, vehicle: Vehicle,
                              amount: Decimal, attachments: [AttachmentID],
                              provenance: Provenance, id: UUID = UUID.v7(),
                              now: Date = Date()) -> Expense {
        Expense(
            id: id, createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: form.date, odometer: nil,
            money: Money(amount: amount, currency: vehicle.homeCurrency,
                         homeCurrency: vehicle.homeCurrency),
            note: nil, attachments: attachments, provenance: provenance,
            conflict: .none, purchaseGroupId: nil, category: form.category,
            title: form.title, recurrence: nil, installedInServiceId: nil)
    }

    private func save() {
        guard let vehicle, saveEnabled, let amount = form.amountDecimal else { return }
        do {
            let repository = try AppStore.repository()
            // RV.243: the receipt half is the shared save seam
            // (`writeExpense`), which writes the photo from the capture staged
            // at scan start regardless of whether the read has finished. The
            // write is attempted first and its failure degrades to no photo -
            // the expense below still saves, and the user is told
            // (docs/ERRORS.md -> Service & expenses) - never a silent drop
            // (hard rule 8) and never a blocked save (hard rule 15: the photo
            // is a head start, never a requirement).
            let (expense, photoWriteFailed) = try Self.writeExpense(
                form: form, vehicle: vehicle, amount: amount, scan: scan,
                repository: repository)
            // RV.200: only a scanned expense has a suggestion to report - the
            // typed path proposed no category and emits nothing. Shape only:
            // the category code and whether the user kept it (hard rule 12).
            if scan != nil {
                AppLog.shared.emit(ExpenseCategorySuggestion(suggested: suggestedCategory,
                                                             saved: form.category))
            }
            // The other half of the P3.5 chain: a reminder completion handed
            // off by the ReminderComplete sheet completes with THIS entry's id.
            if let pending = pendingCompletion {
                ReminderCompletionSession.persistCompletion(
                    reminder: pending.reminder, entryId: expense.id,
                    completionDate: pending.completionDate,
                    completionOdometer: pending.completionOdometer,
                    coordinator: notificationCoordinator)
                pendingCompletion = nil
            } else {
                // RV.77: a plain expense save proposes the next reminder only
                // after the record is on disk - an offer, never an auto-create.
                offerSession.stage(afterExpense: expense, repository: repository)
            }
            hasUnsavedChanges = false
            // RV.267: the capture this save consumed now belongs to the record,
            // so the dismissal that follows must not discard it - nor cancel a
            // read still bound for the inbox.
            didSave = true
            // Tell Home to reload (a `.sheet` never re-triggers the presenter's
            // `.task` on iOS 26) - the new expense must render, not wait for a
            // manual refresh (the Manual fill-up / Edit entry convention).
            toastCenter.noteEntryChanged()
            if photoWriteFailed {
                // The receipt could not be kept: the entry saved without it and
                // the failure names its next step (hard rule 7) - the photo is
                // gone from this save, but the entry it documented is not.
                toastCenter.show(L10n.receiptNotSavedMessage)
            }
            // RV.215: a saved expense is corrected by its owner alone - a read
            // still in flight becomes an inbox suggestion keyed to this entry,
            // never a silent rewrite (hard rule 13).
            expenseSession.markSaved(entryID: expense.id)
            dismiss()
            onSaved()
        } catch {
            AppLog.error(operation: "expenseEntry.save", category: .ui, error: error)
        }
    }

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

    /// RV.247: the car this entry writes to. A reminder completion hand-off
    /// names its own car explicitly; the selected car is UI state and is the
    /// fallback only when no hand-off matches this entry kind.
    static func entryVehicle(vehicles: [Vehicle],
                             completion: ReminderCompletionSession.Pending?,
                             selected: Vehicle?) -> Vehicle? {
        let matching = completion.flatMap { pending -> ReminderCompletionSession.Pending? in
            guard case .expense = ReminderCompletion.entryKind(for: pending.reminder.category) else {
                return nil
            }
            return pending
        }
        return ReminderCompletionSession.entryVehicle(vehicles: vehicles,
                                                      pending: matching,
                                                      selected: selected)
    }

    /// RV.62: the scan's pre-fill becomes default input, field by field. A nil
    /// value stays blank and focusable - never `0` and never an error (hard
    /// rules 13, 7). The total is offered only when the receipt's own currency
    /// is not in conflict with the home-currency form: the expense form has no
    /// foreign-currency affordance, so a total priced in another currency must
    /// not be offered as if it were home money - the field stays blank for the
    /// user to type. A nil currency is treated as "no evidence to the
    /// contrary", exactly as the fill-up form treats an unresolved currency.
    private func apply(_ prefill: ExpensePrefill) {
        if let total = prefill.total {
            let currencyFitsForm = prefill.currency == nil
                || prefill.currency == vehicle?.homeCurrency
            if currencyFitsForm {
                form.amount = ConfirmFormat.string(decimal: total, fractionDigits: 2)
            }
        }
        if let date = prefill.date {
            form.date = date
        }
    }

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        #if DEBUG
        PartsShelfTestSeed.seedIfRequested()
        ExpenseEntryTestSeed.seedIfRequested()
        #endif
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            guard let vehicle = Self.entryVehicle(
                vehicles: vehicles,
                completion: completionSession.pending,
                selected: carSelection.selectedVehicle(vehicles)) else { return }
            self.vehicle = vehicle
            // The category pre-selection is a default input the user edits
            // (hard rule 13), never a lock. Two writers share it: the mode row
            // ("Parts" -> .parts) and, since RV.200, an Expense-mode scan's own
            // inference. Held locally so the save can report whether the user
            // kept a suggestion (shape only - never the receipt's text).
            if let preset = expenseSession.pendingPreset {
                form.category = preset
                suggestedCategory = preset
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
            } else if let prefill = expenseSession.pendingPrefill {
                // RV.62: an Expense-mode capture hands its recognised
                // total/currency/date through the shared session (mirroring
                // `ServiceInvoiceSession`). Applied AFTER the category preset -
                // a scan never overwrites a preset - and every value is default
                // input the user edits (hard rule 13). Consumed here, so a
                // second open of the form never re-applies a stale scan.
                apply(prefill)
                expenseSession.pendingPrefill = nil
            } else {
                #if DEBUG
                if let prefill = ExpenseEntryPrefillSeed.from(
                    arguments: ProcessInfo.processInfo.arguments) {
                    apply(prefill)
                }
                #endif
            }
            // RV.243: the scan's photograph is consumed whether or not the read
            // produced a pre-fill. A deferred read leaves `pendingPrefill` nil
            // at load, so consuming it inside that branch would drop the photo;
            // it is held for THIS save and no later one (PJ.28's one-shot
            // discipline).
            if let capture = expenseSession.consumePendingCapture() {
                scan = capture
            }
            // Snapshots taken AFTER the category pre-selection and the scan
            // pre-fill - neither counts as an edit.
            form.initialCategory = form.category
            form.initialTitle = form.title
            form.initialAmount = form.amount
            form.initialDate = form.date
        } catch {
            AppLog.error(operation: "expenseEntry.load", category: .ui, error: error)
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

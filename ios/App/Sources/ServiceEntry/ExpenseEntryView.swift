import SwiftUI
import TankbookCore

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
    @Environment(ExpenseEntrySession.self) var expenseSession
    @Environment(ReminderCompletionSession.self) private var completionSession
    @Environment(ReminderNotificationCoordinator.self) private var notificationCoordinator
    @Environment(ReminderOfferSession.self) private var offerSession
    /// PJ.29: the cloud-extract surface. `allowsServerBacked` withholds the
    /// `/extract` request under `.required` (docs/CONFIG.md), exactly as the
    /// fill-up Confirm sheet does - the on-device result still stands.
    @Environment(AppConfigService.self) private var config

    @State var form = ExpenseEntryFormState()
    /// RV.279: the shared odometer card's focus, so its format-on-blur works on
    /// the capture door exactly as it does on Edit entry.
    @FocusState var focus: EditEntryNonFillFocus?
    @State var vehicle: Vehicle?
    /// PJ.29: the entry id, generated once for this sheet and reused as the
    /// gateway's `captureId`. The same id the save writes, so a late answer and
    /// the entry it is about share one value.
    @State private var entryId = UUID.v7()
    /// RV.279: the car's live entries, so the currency offer's history tier
    /// reflects what this car has actually paid in (docs/SCHEMA.md -> Currency
    /// offer). Loaded once with the vehicle.
    @State var existingEntries: [any Entry] = []
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

    /// PJ.29: the cloud reading of a scanned expense (docs/API.md -> "The
    /// device's side of /extract"). Started by the capture path
    /// (`CaptureExpenseScan.startExpenseGatewayIfAvailable`) as soon as the local
    /// result lands, and owned by `ExpenseEntrySession` so it survives the gap
    /// before this sheet exists. The sheet renders its phase and applies its
    /// answer; the fill-up Confirm sheet's exact shape.
    ///
    /// The fields the ON-DEVICE read resolved (the pre-fill already on screen).
    /// The on-device result has first claim (F4); a cloud answer never refills
    /// one of these.
    @State var gatewayOnDeviceResolved: Set<FieldRef> = []
    /// Arming guard for the amount/currency/date/category touch hooks: the
    /// load-time pre-fill must not count as a user touch.
    @State private var gatewayTouchTrackingArmed = false
    /// RV.57: the proceed note was dismissed (the ×). Per-sheet, never
    /// persisted - a new capture is a new sheet and a new note.
    @State private var proceedNoteDismissed = false
    /// RV.65: the "sign in to use cloud reading" notice was dismissed (the ×).
    /// Per-sheet, never persisted; the session stays dead until the user signs
    /// in, and a dead session on the NEXT capture surfaces the notice again
    /// (hard rule 7).
    @State private var authExpiredNoticeDismissed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                if vehicle == nil {
                    noVehicleCard
                } else {
                    // PJ.29: the cloud reading's surfaces, in the same order and
                    // with the same copy as the fill-up Confirm sheet - the
                    // update notice when the server no longer supports this
                    // build, then the in-flight proceed note, then the dead
                    // session's next step. All are non-blocking; the on-device
                    // result already stands (hard rules 1, 7, 15).
                    if scan != nil, !config.allowsServerBacked {
                        UpdateRequiredNotice()
                    }
                    if GatewayProceedNote.shouldShow(phase: expenseSession.gateway.phase),
                       !proceedNoteDismissed {
                        GatewayProceedNoteView(dismiss: { proceedNoteDismissed = true })
                    }
                    if expenseSession.gateway.phase == .authExpired, !authExpiredNoticeDismissed {
                        GatewayAuthExpiredNoticeView(dismiss: { authExpiredNoticeDismissed = true })
                    }
                    categoryCard
                    titleCard
                    amountCard
                    ManualFillUpDateRow(date: $form.date, showDatePicker: $showDatePicker)
                    odometerCard
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
        // PJ.29: user engagement with a field is permanent (hard rule 13), so a
        // cloud answer that lands later never overwrites it. Armed only after
        // the load-time pre-fill, exactly as `ManualFillUpView` does.
        .onChange(of: form.amount) { _, _ in
            if gatewayTouchTrackingArmed { expenseSession.gateway.markTouched(.total) }
        }
        .onChange(of: form.currency) { _, _ in
            if gatewayTouchTrackingArmed { expenseSession.gateway.markTouched(.currency) }
        }
        .onChange(of: form.date) { _, _ in
            if gatewayTouchTrackingArmed { expenseSession.gateway.markTouched(.date) }
        }
        .onChange(of: form.category) { _, _ in
            if gatewayTouchTrackingArmed { expenseSession.gateway.markTouched(.category) }
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
            let prefill = expenseSession.pendingPrefill
            let preset = expenseSession.pendingPreset
            gatewayOnDeviceResolved = Self.onDeviceResolvedFields(prefill: prefill, preset: preset)
            if !form.hasEdits() {
                if let prefill {
                    apply(prefill)
                    expenseSession.pendingPrefill = nil
                }
                if let preset {
                    form.category = preset
                    suggestedCategory = preset
                    expenseSession.pendingPreset = nil
                }
                form.initialCategory = form.category
                form.initialTitle = form.title
                form.initialAmount = form.amount
                form.initialCurrency = form.currency
                form.initialOdometer = form.odometer
                form.initialDate = form.date
            }
            // PJ.29: the on-device result is on screen (F4). Touch tracking is
            // armed now, after the pre-fill, so it never counts as a user touch;
            // the cloud reading itself was started by the capture path.
            gatewayTouchTrackingArmed = true
        }
        // PJ.29: a cloud answer that landed within the budget. It fills blank AND
        // untouched fields only, and never arrives after the save (that route is
        // the inbox's, via the session's `markSaved`).
        .onChange(of: expenseSession.gatewayRevision) { _, _ in
            applyPendingGatewayAnswer()
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
            vehicleId: vehicle.id, date: form.date, odometer: form.odometerValue,
            money: Money(amount: amount, currency: form.currency,
                         homeCurrency: vehicle.homeCurrency),
            note: nil, attachments: attachments, provenance: provenance,
            conflict: .none, purchaseGroupId: nil, category: form.category,
            title: form.title, installedInServiceId: nil)
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

    /// RV.62/RV.279: the scan's pre-fill becomes default input, field by field.
    /// The form's own `apply` owns the rule so the L1 test drives the exact
    /// conversion the load does.
    private func apply(_ prefill: ExpensePrefill) {
        form.apply(prefill)
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
            // The car's own currency is the default (hard rule 13); the chip
            // row lets the user change it, and a foreign scan pre-fills its own.
            form.currency = vehicle.homeCurrency
            existingEntries = (try? repository.liveEntries(forVehicle: vehicle.id)) ?? []
            // PJ.29: the local read may already have landed before the sheet's
            // `.task` runs (the seeded and fast-scan paths). Capture what it
            // resolved BEFORE consuming it, so the cloud reading knows which
            // fields the on-device result owns (F4) and never fights it.
            let localPrefill = expenseSession.pendingPrefill
            let localPreset = expenseSession.pendingPreset
            gatewayOnDeviceResolved = Self.onDeviceResolvedFields(prefill: localPrefill,
                                                                  preset: localPreset)
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
            form.initialCurrency = form.currency
            form.initialOdometer = form.odometer
            form.initialDate = form.date
            // PJ.29: touch tracking is armed only here, after every load-time
            // pre-fill has been written, so none of them counts as a user touch.
            // An answer that arrived before this sheet existed is applied now.
            gatewayTouchTrackingArmed = true
            applyPendingGatewayAnswer()
        } catch {
            AppLog.error(operation: "expenseEntry.load", category: .ui, error: error)
        }
    }

    /// PJ.29: the fields the on-device read resolved - the cloud answer must
    /// never fight the parser for one of them (F4). The category counts when the
    /// scan inferred one, the same suggestion that rides `pendingPreset`.
    static func onDeviceResolvedFields(prefill: ExpensePrefill?,
                                       preset: ExpenseCategory?) -> Set<FieldRef> {
        var out = Set<FieldRef>()
        if prefill?.total != nil { out.insert(.total) }
        if prefill?.currency != nil { out.insert(.currency) }
        if prefill?.date != nil { out.insert(.date) }
        if preset != nil { out.insert(.category) }
        return out
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

// MARK: - Save

// In a same-file extension so the struct body stays under the linter's ceiling;
// `private` is file-scoped, so the members above are still reachable.
extension ExpenseEntryView {
    func save() {
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
                repository: repository, id: entryId)
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
            // RV.215 + PJ.29: a saved expense is corrected by its owner alone - a
            // read still in flight (local OR cloud) becomes an inbox suggestion
            // keyed to this entry, never a silent rewrite (hard rule 13).
            // `markSaved` seals both boundaries; one call, not two.
            expenseSession.markSaved(entryID: expense.id)
            dismiss()
            onSaved()
        } catch {
            AppLog.error(operation: "expenseEntry.save", category: .ui, error: error)
        }
    }

    var saveBar: some View {
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
}

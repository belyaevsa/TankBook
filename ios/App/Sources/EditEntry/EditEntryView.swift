import SwiftUI
import UIKit
import TankbookCore

/// The Edit entry screen (P1.6) - design/screens/EditEntry.dc.html. A pushed
/// route reached from a Home log row, the conflict badge, the account-wide
/// flagged list, Recently deleted and `-presentScreen editEntry`
/// (docs/SCREENMAP.md).
///
/// RV.66: an EXPLICIT entry id (the flagged list, the inbox's "use a different
/// receipt") opens the entry wherever it lives - the screen resolves the id
/// across every vehicle, never against the selected car's rows alone - so a
/// conflict on car B is decidable without first switching to car B.
///
/// The fill-up is the 80% case and it reuses the ConfirmManual components
/// wholesale - the same currency chips, three-number card with live derivation
/// and cross-check, fuel/full-tank card, odometer card with the F9a conflict,
/// station row and date picker (lifted to a shared `Date` binding). Nothing is
/// forked. The other three entry types render their own compact editable rows.
///
/// Saving is a full-vehicle recompute (docs/SCHEMA.md, Recalculation on edit):
/// the headline before and after both come from the engine, and the delta toast
/// shows only when a figure actually changed (docs/ERRORS.md -> Edit entry).
/// Delete is a tombstone write via the repository - the one place red lives -
/// with the 30-day Recently deleted window built by P1.7.
struct EditEntryView: View {
    /// The entry being edited; `nil` falls back to the most recent entry of the
    /// default vehicle (placeholder links, `-presentScreen editEntry`).
    let entryID: UUID?

    @Environment(AppToastCenter.self) var toastCenter
    // RV.66: `carSelection` (and the form/support state below) is internal, not
    // private, so the entry-resolution extension in
    // `EditEntryView+EntryResolution.swift` - split out to keep this file under
    // the linter's length limits, the EditEntryView+Discard precedent - can
    // read and write it.
    @Environment(AppCarSelection.self) var carSelection
    // PJ.22: the post-save reminder offer. The edit screen stages a proposal
    // when a service's line-item lifetime changed; the tab root presents it
    // once this pushed screen has popped (see `stagedOfferForPromotion`).
    @Environment(ReminderOfferSession.self) private var offerSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    // FillUp form (reuses the ConfirmManual components).
    @State var fillForm = ManualFillUpFormState()
    @FocusState private var fillFocus: ManualFillUpFocus?
    // RV.230: the non-fill form's focus. Held here (like `fillFocus`) so the
    // shared `F9aWarningRow`'s Fix can focus the odometer through a binding.
    @FocusState private var nonFillFocus: EditEntryNonFillFocus?
    // The other three entry types. Internal (not private) so the RV.31 discard
    // extension in EditEntryView+Discard.swift can read it for the dirty check.
    @State var nonFillForm = EditEntryNonFillForm()

    @State var vehicle: Vehicle?
    @State var fillUp: FillUp?
    @State var charge: ChargeSession?
    @State var service: ServiceRecord?
    @State var expense: Expense?
    /// The tire set a `.parts` expense bought, when the link exists. Loaded with
    /// the entry; written by `makeTireSet`.
    @State var linkedTireSet: TireSet?
    @State var otherEntries: [any Entry] = []
    @State var stations: [Station] = []
    @State var attachments: [Attachment] = []
    @State var selectedStation: Station?
    // The fill-up's note (the non-fill note lives inside `nonFillForm`). Internal
    // (not private) so the RV.31 discard extension can read it for the dirty check.
    @State var note = ""
    @State private var showDatePicker = false
    @State private var showDeleteConfirm = false
    @State private var showTankLevel = false
    @State var syncOverwrite: SyncOverwrite?
    @State private var didLoad = false
    @State var loadFailed = false
    @State var pendingBlobIDs: Set<UUID> = []
    /// RV.208: the entry's attachment ids that resolve to no live `Attachment`
    /// row. Left in place (never swept - the states are not locally
    /// distinguishable, docs/SYNC.md -> Attachments); the receipt strip surfaces
    /// them with a re-attach next step.
    @State var missingAttachmentIDs: [AttachmentID] = []
    /// PJ.22: a lifetime edit staged an offer that must be promoted only after
    /// this pushed screen has fully popped - the same "never mid-save, never
    /// over the screen that saved" rule the create door's sheet dismissal
    /// enforces.
    @State private var stagedOfferForPromotion = false

    // PJ.48: the "Add receipt" attach flow. The photo, its OCR lines and the
    // extraction are held until Save writes them; a failed write flips
    // `attachFailed` and leaves the entry completely unchanged (ERRORS.md ->
    // Edit entry, the PJ.48 warn row). `attachImage` is internal (not private)
    // for the RV.31 discard extension - a held photo is unsaved work too.
    @State var showAttachSource = false
    @State var attachImage: UIImage?
    @State private var attachOcrLines: [OCRLine] = []
    @State private var attachExtraction: FuelExtraction?
    @State private var attachFailed = false
    @State var attachProcessing = false

    var currentEntry: (any Entry)? { fillUp ?? charge ?? service ?? expense }
    private var volumeUnit: VolumeUnit { vehicle?.units.volume ?? .l }
    var distanceUnit: DistanceUnit { vehicle?.units.distance ?? .km }

    var body: some View {
        Group {
            if loadFailed {
                EditEntryRows.entryNotFound
            } else if let currentEntry, let vehicle {
                VStack(spacing: 0) {
                    // RV.104: the acceptance stays VISIBLE and reversible here
                    // (hard rule 8 - never a silent hole in the data). The
                    // banner shows while the opened entry carries an active
                    // acceptance; Undo clears it and the timeline validator
                    // re-derives the flag from the entries alone.
                    if let acceptance = currentEntry.flagAcceptance {
                        acceptedBanner(acceptance)
                    }
                    if let fillUp {
                        fillUpContent(fillUp, vehicle: vehicle)
                    } else {
                        nonFillContent(currentEntry, vehicle: vehicle)
                    }
                }
            } else {
                Color.clear
            }
        }
        .background(Theme.Palette.midnight)
        .task {
            await load()
            await fetchPendingBlobs()
            #if DEBUG
            openDatePickerIfRequested()
            #endif
        }
        .sheet(isPresented: $showTankLevel) {
            DiscardAwareSheet(policy: .discardSilently, hasUnsavedChanges: .constant(false)) {
                TankLevelSheet(tankLevelAfterPct: $fillForm.tankLevelAfterPct,
                               isFull: $fillForm.isFull,
                               capacityL: vehicle?.tankCapacityL)
                    .navigationTitle("Tank level")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .alert("Delete this entry?",
               isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It moves to Recently deleted for 30 days.")
        }
        // RV.31: report whether this pushed Edit entry holds unsaved work up to
        // the tab host (`AppRootView`), which consults it when the ACTIVE tab is
        // re-tapped: a dirty entry makes the pop-to-root ask first (hard rule
        // 8), a clean one pops immediately. See `PushedFormDirtyPreference`.
        .preference(key: PushedFormDirtyPreference.self, value: entryHasUnsavedChanges)
        // PJ.22: promote a staged lifetime-edit offer only once this screen has
        // popped, so the sheet never lands over the form that saved it.
        .onDisappear {
            guard stagedOfferForPromotion else { return }
            stagedOfferForPromotion = false
            offerSession.promote()
        }
    }

    private var currencySymbol: String {
        AddVehicleSupport.moneySymbol(for: fillForm.currency)
    }

    /// The foreign-currency decision for the edited fill, resolved honestly
    /// from the rate store exactly as the Confirm sheet does (P5.2). A manual
    /// rate set on this entry - or loaded from its stored money - overrides the
    /// feed (hard rule 13: the user's number wins and stays editable), so the
    /// same card renders here as on Confirm, including the F9 next step.
    private var editConversionState: ForeignCurrencyState {
        fillForm.conversionState(vehicle: vehicle, lowConfidence: false)
    }

    private var editConvertedAmount: Decimal? {
        fillForm.convertedAmount(vehicle: vehicle, volumeUnit: volumeUnit, lowConfidence: false)
    }

    /// Same placement rule as the Confirm sheet (docs/DESIGN.md - entry form
    /// order): a currency needing attention renders above the numbers, the
    /// folded home-currency case below them.
    private func editCurrencyNeedsAttention(_ vehicle: Vehicle) -> Bool {
        ManualFillUpCurrencySection.needsAttention(
            currency: fillForm.currency, homeCurrency: vehicle.homeCurrency,
            lowConfidence: false, state: editConversionState)
    }

    @ViewBuilder
    private func editCurrencySection(_ vehicle: Vehicle) -> some View {
        ManualFillUpCurrencySection(form: $fillForm,
                                    homeCurrency: vehicle.homeCurrency,
                                    lowConfidence: false, state: editConversionState,
                                    offer: currencyOffer(vehicle: vehicle))
    }

    /// The complete, ordered currency offer for the edited entry's car
    /// (docs/SCHEMA.md -> Currency offer). The entry being edited counts as
    /// history - it is the most recent currency use there is, so editing a PLN
    /// fill offers PLN first. Pure local derivation - no network (hard rule 1).
    private func currencyOffer(vehicle: Vehicle) -> [CurrencyCode] {
        let entries = otherEntries + (currentEntry.map { [$0] } ?? [])
        return CurrencyOfferBuilder.offer(
            homeCurrency: vehicle.homeCurrency,
            history: CurrencyHistory.recentCurrencies(in: entries),
            region: Locale.current.region?.identifier)
    }

    private var odometerConflict: OdometerConflict? {
        guard let vehicle else { return nil }
        return fillForm.odometerConflict(vehicle: vehicle,
                                         existingEntries: otherEntries,
                                         attachments: attachments,
                                         distanceUnit: distanceUnit)
    }

    // MARK: - Other entry types

    private func nonFillContent(_ entry: any Entry, vehicle: Vehicle) -> some View {
        EditEntryNonFillView(form: $nonFillForm, entry: entry,
                             vehicle: vehicle,
                             focus: $nonFillFocus,
                             // RV.230: the F9a warn and its neighbourhood are
                             // derived from the form the same way the save
                             // stamps the flag, so a conflict is visible here
                             // instead of silently carried (hard rules 7 and 8).
                             odometerConflict: nonFillConflict,
                             neighbourhood: nonFillNeighbourhood,
                             offer: currencyOffer(vehicle: vehicle),
                             attachments: attachments,
                             showDatePicker: $showDatePicker,
                             syncOverwrite: syncOverwrite,
                             onRestore: restoreSyncOverwrite,
                             pendingBlobIDs: pendingBlobIDs,
                             missingAttachmentIDs: missingAttachmentIDs,
                             onAttachmentChanged: handleAttachmentChanged,
                             attachImage: attachImage,
                             attachProcessing: attachProcessing,
                             showAttachSource: $showAttachSource,
                             onAddReceipt: { showAttachSource = true },
                             onAttachImage: { image in attachReceipt(image) },
                             linkedTireSet: linkedTireSet,
                             onMakeTireSet: makeTireSet)
            .safeAreaInset(edge: .bottom) { saveBar }
    }

    /// "Make this a tire set" from a `.parts` expense (docs/JOURNEYS.md J7b).
    /// The link is written once: an expense that already has a live set opens it
    /// instead of minting a second. The set's default name is the expense's own
    /// title, editable on the set form afterwards (hard rule 13).
    private func makeTireSet() {
        guard let expense, let vehicle else { return }
        do {
            let repository = try AppStore.repository()
            let sets = try repository.liveTireSets(forVehicle: vehicle.id)
            if let existing = TireSetPurchase.linkedSet(forExpense: expense.id, in: sets) {
                linkedTireSet = existing
                return
            }
            guard let set = TireSetPurchase.makeSet(for: expense, existing: sets) else { return }
            try repository.upsertTireSet(set)
            linkedTireSet = set
            toastCenter.noteEntryChanged()
        } catch {
            AppLog.error(operation: "editEntry.makeTireSet", category: .ui, error: error)
        }
    }

    // MARK: - Loading

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        #if DEBUG
        EditEntryTestSeed.seedIfRequested()
        PhotoSyncingTestSeed.seedIfRequested()
        #endif
        await reloadData()
    }

    /// RV.10 screenshot hook `-openDatePicker`: expands the date row's picker so
    /// a capture shows the flipped chevron and the collapse affordance. simctl
    /// cannot tap, so the state a screenshot needs is driven here, exactly like
    /// `-presentReminderComplete` and the other DEBUG hooks.
    #if DEBUG
    private func openDatePickerIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-openDatePicker") else { return }
        showDatePicker = true
    }
    #endif

    // MARK: - Save

    private var saveEnabled: Bool {
        guard let vehicle else { return false }
        if fillUp != nil { return fillForm.canSave(volumeUnit: vehicle.units.volume) }
        return true
    }

    private func save() {
        guard let vehicle else { return }
        if let fill = fillUp {
            saveFill(fill, vehicle: vehicle)
        } else if let entry = currentEntry {
            saveNonFill(entry, vehicle: vehicle)
        }
    }

    private func saveFill(_ fill: FillUp, vehicle: Vehicle) {
        guard let derived = fillForm.derived(volumeUnit: vehicle.units.volume) else { return }
        do {
            let repository = try AppStore.repository()
            // PJ.48: write the freshly-attached receipt FIRST. A failed write
            // leaves the entry completely unchanged - the warn row names the
            // next step and nothing is upserted (docs/ERRORS.md -> Edit entry).
            var attachPlan: ScannedSavePlan?
            if let attachImage {
                // The photo is kept either way (docs/ERRORS.md -> Edit entry):
                // if the OCR has not settled yet, the attach still writes the
                // photo with an empty extraction rather than dropping it.
                let extraction = attachExtraction ?? FuelExtraction()
                let plan = ScannedSavePlanner.plan(
                    extraction: extraction,
                    cropRects: [:],
                    qrAnchor: nil,
                    declaredProvenance: .manual,
                    hasPhoto: true,
                    saved: ScannedSaveValues(total: derived.total, volumeL: derived.volumeL,
                                             unitPrice: derived.unitPrice, currency: fillForm.currency,
                                             fuelKind: fillForm.fuelKind, date: fillForm.date))
                do {
                    guard let id = plan.attachmentID else { return }
                    let attachment = try ReceiptAttachmentWriter.write(id: id, image: attachImage,
                                                                        ocrLines: attachOcrLines,
                                                                        extraction: extraction)
                    try repository.upsertAttachment(attachment)
                    attachPlan = plan
                } catch {
                    attachFailed = true
                    return
                }
            }
            let before = headline(repository: repository, vehicle: vehicle)
            var updated = fillForm.buildUpdatedFill(from: fill, vehicle: vehicle,
                                                    derived: derived,
                                                    otherEntries: otherEntries,
                                                    stationID: selectedStation?.id)
            updated.note = note.isEmpty ? nil : note
            // Re-apply the conversion on save: `Money.edited` (inside
            // `buildUpdatedFill`) already re-pended a money-fact edit and
            // re-homed it to the vehicle's current home currency; the money
            // must also come back with a rate - a manual rate if the user set
            // one, the store's for the entry's date otherwise, rate-pending
            // only when neither exists (F9). Without this an edited foreign
            // fill-up silently lost its conversion and saved rate-pending.
            if let money = updated.money {
                updated.money = fillForm.convertForSave(money, vehicle: vehicle, lowConfidence: false)
            }
            // PJ.48: link the receipt the attach just wrote. `buildUpdatedFill`
            // carries `provenance` over untouched, so a typed entry stays
            // `.manual`; the extraction record is the attach's own OCR.
            if let plan = attachPlan, let id = plan.attachmentID {
                updated.attachments = [id]
                updated.extraction = plan.extraction
            }
            try loggedWrite(AppLog.shared, op: .update, entityType: FillUp.entityType,
                            entityId: updated.id, source: .manual) { try repository.upsertFillUp(updated) }
            let after = headline(repository: repository, vehicle: vehicle)
            notify(before: before, after: after, vehicle: vehicle)
            dismiss()
        } catch {
            AppLog.error(operation: "editEntry.saveFillUp", category: .ui, error: error)
        }
    }

    private func saveNonFill(_ entry: any Entry, vehicle: Vehicle) {
        do {
            let repository = try AppStore.repository()
            // RV.202: a receipt attached to a non-fill entry is written FIRST,
            // through the same shared photo-write seam the fill-up and Confirm
            // saves use. A failed write degrades to no photo rather than
            // blocking the entry (hard rule 1), and the report fires only after
            // the entry is on disk, so a failed save never claims success (hard
            // rule 8, docs/ERRORS.md -> Confirm, RV.149).
            let held = attachImage.map {
                HeldReceiptPhoto(image: $0, ocrLines: attachOcrLines,
                                 extraction: attachExtraction)
            }
            let receiptWrite = try Self.writeNonFillWithHeldReceipt(
                entry, vehicle: vehicle, form: nonFillForm,
                otherEntries: otherEntries, heldPhoto: held, repository: repository)
            // A non-fill edit never moves consumption segments; there is no
            // delta to toast about - Home just reloads.
            toastCenter.noteEntryChanged()
            reportLostReceiptPhoto(receiptWrite, toastCenter: toastCenter)
            // PJ.22: a service whose line-item lifetime was set or changed
            // proposes the next reminder, through the SAME `ReminderOffer` seam
            // the create door uses. Nothing is created here - the offer is
            // staged and presented after this screen pops.
            stageServiceReminderOfferIfLifetimeChanged(entry, vehicle: vehicle,
                                                       repository: repository)
            dismiss()
        } catch {
            AppLog.error(operation: "editEntry.save", category: .ui, error: error)
        }
    }

    /// Stages the post-save service-reminder offer when this save set or changed
    /// a line item's lifetime (PJ.22). The stored record is read back after the
    /// write so the proposal sees the values that actually landed; the offer is
    /// then promoted on `onDisappear`, once this pushed screen is gone.
    private func stageServiceReminderOfferIfLifetimeChanged(
        _ entry: any Entry, vehicle: Vehicle, repository: TankbookRepository) {
        guard entry is ServiceRecord, nonFillForm.serviceLifetimeChanged,
              let stored = (try? repository.liveServiceRecords(forVehicle: vehicle.id))?
                  .first(where: { $0.id == entry.id }) else { return }
        offerSession.stage(afterService: stored, repository: repository)
        stagedOfferForPromotion = offerSession.pending != nil
    }

    /// The recompute, both halves from the engine (docs/SCHEMA.md,
    /// Recalculation on edit): the headline is a pure function of the vehicle's
    /// fill history, so before and after differ only by what the edit changed.
    /// The S2 single-count invariant applies here too - an unresolved duplicate
    /// pair contributes once, so the delta toast never reports a number that
    /// would double (docs/SYNC.md S2).
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

    // MARK: - Save bar

    private var saveBar: some View {
        VStack(spacing: 8) {
            Button(action: save) {
                Text("Save changes")
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
            .accessibilityIdentifier("editEntrySaveButton")

            if !saveEnabled {
                Text("Enter total and liters to save")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }

            Button("Delete entry") {
                showDeleteConfirm = true
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.Palette.inkSoft)
            .padding(.vertical, 6)
            .accessibilityIdentifier("editEntryDeleteButton")
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Theme.Palette.midnight)
    }

    // MARK: - Restore (the "Changed by sync" action)

    /// "Restore my version" (docs/SYNC.md S1/S4, hard rule 13): writes the
    /// losing version back as a fresh local edit, so the next sync pushes it
    /// instead of overwriting it again. The overwrite log row is cleared by the
    /// restore, and the form reloads to show the restored values.
    private func restoreSyncOverwrite() {
        guard let overwrite = syncOverwrite else { return }
        do {
            let repository = try AppStore.repository()
            if try repository.restoreSyncOverwrite(recordId: overwrite.recordId) {
                syncOverwrite = nil
                toastCenter.noteEntryChanged()
                Task { await reloadData() }
            }
        } catch {
            AppLog.error(operation: "editEntry.restoreSyncOverwrite", category: .ui, error: error)
        }
    }

    // MARK: - Delete

    private func performDelete() {
        do {
            let repository = try AppStore.repository()
            // OB.2: the delete mutation pair - ids and the entity type only.
            if let fill = fillUp {
                try loggedWrite(AppLog.shared, op: .delete, entityType: FillUp.entityType,
                                entityId: fill.id, source: .manual) { try repository.softDeleteFillUp(id: fill.id) }
            } else if let charge = charge {
                try loggedWrite(AppLog.shared, op: .delete, entityType: ChargeSession.entityType,
                                entityId: charge.id, source: .manual) { try repository.softDeleteChargeSession(id: charge.id) }
            } else if let service = service {
                try loggedWrite(AppLog.shared, op: .delete, entityType: ServiceRecord.entityType,
                                entityId: service.id, source: .manual) { try repository.softDeleteServiceRecord(id: service.id) }
            } else if let expense = expense {
                try loggedWrite(AppLog.shared, op: .delete, entityType: Expense.entityType,
                                entityId: expense.id, source: .manual) { try repository.softDeleteExpense(id: expense.id) }
            }
            toastCenter.noteEntryChanged()
            dismiss()
        } catch {
            AppLog.error(operation: "editEntry.delete", category: .ui, error: error)
        }
    }
}

// MARK: - FillUp content

private extension EditEntryView {
    func fillUpContent(_ fill: FillUp, vehicle: Vehicle) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 9) {
                    fillUpReceiptCard(fill)
                    if attachFailed {
                        attachFailedWarn
                    }
                    ManualFillUpDateRow(date: $fillForm.date, showDatePicker: $showDatePicker)
                    ManualFillUpOdometerCard(form: $fillForm, focus: $fillFocus,
                                             distanceUnit: distanceUnit,
                                             conflict: odometerConflict,
                                             onFixDate: { showDatePicker = true })
                    neighbourhoodCard
                        .id(Self.neighbourhoodScrollTarget)
                    ManualFillUpStationRow(stations: $stations, selection: $selectedStation)
                    ManualFillUpFuelFullCard(form: $fillForm, fuelKinds: vehicle.fuelKinds)
                    if editCurrencyNeedsAttention(vehicle) { editCurrencySection(vehicle) }
                    ManualFillUpNumbersCard(form: $fillForm, focus: $fillFocus,
                                            volumeUnit: volumeUnit, currencySymbol: currencySymbol,
                                            reduceMotion: accessibilityReduceMotion)
                    if !editCurrencyNeedsAttention(vehicle) { editCurrencySection(vehicle) }
                    if editConversionState.showsConversionCard {
                        ForeignCurrencyCard(
                            currency: fillForm.currency,
                            homeCurrency: vehicle.homeCurrency,
                            state: editConversionState,
                            convertedAmount: editConvertedAmount,
                            manualRate: $fillForm.manualRate,
                            isManualRateEditorOpen: $fillForm.isManualRateEditorOpen)
                    }
                    TankLevelRow(isFull: fillForm.isFull,
                                 tankLevelAfterPct: fillForm.tankLevelAfterPct,
                                 action: { showTankLevel = true })
                        .formCard()
                    EditEntryRows.noteRow(text: $note, identifier: "editEntryNoteField")
                    if let syncOverwrite {
                        EditEntryRows.changedBySyncRow(deviceName: syncOverwrite.deviceName,
                                                       replacedAt: syncOverwrite.replacedAt,
                                                       onRestore: restoreSyncOverwrite)
                    }
                    EditEntryRows.footer
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .safeAreaInset(edge: .bottom) { saveBar }
            #if DEBUG
            .onAppear {
                scrollToNeighbourhoodIfRequested(proxy)
            }
            #endif
        }
    }
}

// MARK: - PJ.48 attach a receipt to a typed entry
//
// Internal (not private) extension: the RV.66 entry-resolution extension
// (`EditEntryView+EntryResolution.swift`, split out for the linter's length
// limits) invokes `seedAttachSuggestionIfRequested` after binding a resolved
// entry, so the attach hook must be reachable across files.

extension EditEntryView {
    /// The screenshot/test hook `-seedAttachSuggestion`: applies a synthetic
    /// OCR reading through the REAL merge + apply path (blank fields only,
    /// dimmed until confirmed), so a screenshot can show the post-attach state
    /// without driving the out-of-process Photos picker.
    #if DEBUG
    func seedAttachSuggestionIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seedAttachSuggestion"),
              let fillUp else { return }
        // Only the unit price, so the merge suggests exactly the blank price
        // field and nothing else - the suggestion stays dimmed (.notApplicable
        // cross-check, no triple to verify).
        let extraction = FuelExtraction(unitPrice: Decimal(string: "1.679")!)
        let suggestions = ReceiptAttachMerge.suggestions(entry: fillUp, extraction: extraction)
        fillForm.applyAttachedSuggestions(suggestions, extraction: extraction)
    }
    #endif

    /// One image in, one set of blank-fields-only suggestions out. The OCR runs
    /// through the same `CapturePipeline` the scan door uses; the merge then
    /// decides which fields are blank on the TYPED entry, and only those are
    /// offered as dimmed pre-fills (hard rule 13). A typed value is never
    /// overwritten and raises no amber (docs/ERRORS.md -> Edit entry).
    ///
    /// RV.202: shared by the fill-up and the three non-fill kinds. The
    /// blank-fields-only merge is a FILL-UP concern - a service invoice or an
    /// expense receipt has no fuel fields to pre-fill - so a non-fill attach
    /// holds the photo without any value merge; widening recognition over entry
    /// kind is RV.201's, not this path's. The photo itself is written on Save
    /// (`saveNonFill`), reusing the shared `attemptReceiptPhotoWrite` seam.
    func attachReceipt(_ image: UIImage) {
        guard let vehicle else { return }
        attachFailed = false
        attachImage = image
        attachProcessing = true
        Task {
            let prefill = await CapturePipeline.process(
                image, source: .receipt,
                bandProvider: AppFuelPriceBand.provider(vehicleId: vehicle.id))
            attachOcrLines = prefill.ocrLines
            let extraction = prefill.extraction ?? FuelExtraction()
            attachExtraction = extraction
            if let fillUp {
                let suggestions = ReceiptAttachMerge.suggestions(entry: fillUp, extraction: extraction)
                fillForm.applyAttachedSuggestions(suggestions, extraction: extraction)
            }
            attachProcessing = false
        }
    }

    /// The failed-write warn row (docs/ERRORS.md -> Edit entry, the PJ.48 row):
    /// the entry is unchanged and the next step is named - retry, or free up
    /// space in Settings. Amber is attention (hard rule 5), never a block.
    var attachFailedWarn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't save the photo – the entry is unchanged.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.warn)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                Button("Try again") { save() }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
                Button("Free up space") { openSettings() }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
            }
        }
        .padding(12)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editAttachFailedWarn")
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

import SwiftUI
import UIKit
import TankbookCore

/// The Edit entry screen (P1.6) - design/screens/EditEntry.dc.html. A pushed
/// route reached from a Home log row, the conflict badge, Recently deleted and
/// `-presentScreen editEntry` (docs/SCREENMAP.md).
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

    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(AppCarSelection.self) private var carSelection
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    // FillUp form (reuses the ConfirmManual components).
    @State private var fillForm = ManualFillUpFormState()
    @FocusState private var fillFocus: ManualFillUpFocus?
    // The other three entry types.
    @State private var nonFillForm = EditEntryNonFillForm()

    @State private var vehicle: Vehicle?
    @State private var fillUp: FillUp?
    @State private var charge: ChargeSession?
    @State private var service: ServiceRecord?
    @State private var expense: Expense?
    @State private var otherEntries: [any Entry] = []
    @State private var stations: [Station] = []
    @State private var attachments: [Attachment] = []
    @State private var selectedStation: Station?
    @State private var note = ""
    @State private var showDatePicker = false
    @State private var showDeleteConfirm = false
    @State private var showTankLevel = false
    @State private var showChangedBySync = false
    @State private var didLoad = false
    @State private var loadFailed = false
    @State private var pendingBlobIDs: Set<UUID> = []

    // PJ.48: the "Add receipt" attach flow. The photo, its OCR lines and the
    // extraction are held until Save writes them; a failed write flips
    // `attachFailed` and leaves the entry completely unchanged (ERRORS.md ->
    // Edit entry, the PJ.48 warn row).
    @State private var showAttachSource = false
    @State private var attachImage: UIImage?
    @State private var attachOcrLines: [OCRLine] = []
    @State private var attachExtraction: FuelExtraction?
    @State private var attachFailed = false
    @State private var attachProcessing = false

    private var currentEntry: (any Entry)? { fillUp ?? charge ?? service ?? expense }
    private var volumeUnit: VolumeUnit { vehicle?.units.volume ?? .l }
    private var distanceUnit: DistanceUnit { vehicle?.units.distance ?? .km }

    var body: some View {
        Group {
            if loadFailed {
                EditEntryRows.entryNotFound
            } else if let currentEntry, let vehicle {
                if let fillUp {
                    fillUpContent(fillUp)
                } else {
                    nonFillContent(currentEntry, vehicle: vehicle)
                }
            } else {
                Color.clear
            }
        }
        .background(Theme.Palette.midnight)
        .task {
            await load()
            await fetchPendingBlobs()
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
        .receiptAttachSource(isPresented: $showAttachSource, title: "Add receipt") { image in
            attachReceipt(image)
        }
        .alert("Delete this entry?",
               isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It moves to Recently deleted for 30 days.")
        }
    }

    private var currencySymbol: String {
        AddVehicleSupport.currencySymbol(for: fillForm.currency)
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
    private var editCurrencyNeedsAttention: Bool {
        ManualFillUpCurrencySection.needsAttention(
            currency: fillForm.currency, homeCurrency: vehicle?.homeCurrency ?? .eur,
            lowConfidence: false, state: editConversionState)
    }

    @ViewBuilder
    private var editCurrencySection: some View {
        ManualFillUpCurrencySection(form: $fillForm,
                                    homeCurrency: vehicle?.homeCurrency ?? .eur,
                                    lowConfidence: false, state: editConversionState)
    }

    private var odometerConflict: OdometerConflict? {
        guard let vehicle else { return nil }
        return fillForm.odometerConflict(vehicle: vehicle,
                                         existingEntries: otherEntries,
                                         distanceUnit: distanceUnit)
    }

    // MARK: - Other entry types

    private func nonFillContent(_ entry: any Entry, vehicle: Vehicle) -> some View {
        EditEntryNonFillView(form: $nonFillForm, entry: entry,
                             vehicle: vehicle,
                             attachments: attachments,
                             showDatePicker: $showDatePicker,
                             showChangedBySync: showChangedBySync,
                             pendingBlobIDs: pendingBlobIDs)
            .safeAreaInset(edge: .bottom) { saveBar }
    }

    // MARK: - Loading

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        EditEntryTestSeed.seedIfRequested()
        PhotoSyncingTestSeed.seedIfRequested()
        showChangedBySync = ProcessInfo.processInfo.arguments.contains("-forceChangedBySync")
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            // Same selection as Home: an edit belongs to the car on screen.
            guard let vehicle = carSelection.selectedVehicle(vehicles) else {
                loadFailed = true
                return
            }
            self.vehicle = vehicle
            let all = try repository.liveEntries(forVehicle: vehicle.id)
            let targetID = entryID ?? Self.mostRecentID(all)
            guard let target = all.first(where: { $0.id == targetID }) else {
                loadFailed = true
                return
            }
            otherEntries = all.filter { $0.id != target.id }
            stations = try repository.liveStations()
            attachments = try repository.liveAttachments()
                .filter { target.attachments.contains($0.id) }
            pendingBlobIDs = Set(attachments
                .filter { !BlobService.isBlobAvailable($0) }
                .map(\.id))
            if let fill = target as? FillUp {
                fillUp = fill
                selectedStation = stations.first { $0.id == fill.stationId }
                fillForm.load(from: fill, vehicle: vehicle)
                note = fill.note ?? ""
                seedAttachSuggestionIfRequested()
            } else {
                loadNonFill(target)
            }
        } catch {
            AppLog.error(operation: "editEntry.load", category: .ui, error: error)
            loadFailed = true
        }
    }

    private func loadNonFill(_ entry: any Entry) {
        nonFillForm.amount = entry.money.map {
            ManualFillUpFormat.decimal($0.amount, fractionDigits: 2)
        } ?? ""
        nonFillForm.currency = entry.money?.currency ?? vehicle?.homeCurrency ?? .eur
        nonFillForm.date = entry.date
        nonFillForm.odometer = entry.odometer.map(OdometerFormat.grouped) ?? ""
        nonFillForm.note = entry.note ?? ""
        switch entry {
        case let charge as ChargeSession:
            self.charge = charge
            nonFillForm.energyKWh = charge.energyKWh == 0
                ? "" : ManualFillUpFormat.decimal(charge.energyKWh, fractionDigits: 1)
            nonFillForm.provider = charge.provider ?? ""
        case let service as ServiceRecord:
            self.service = service
            nonFillForm.vendor = service.vendor ?? ""
        case let expense as Expense:
            self.expense = expense
            nonFillForm.title = expense.title
        default:
            break
        }
    }

    /// P4.6 lazy download: opening the entry fetches the missing full rendition
    /// (docs/SYNC.md -> Delivery). Signed-out or offline, the fetch fails
    /// silently and the "photo syncing" shimmer stays - nothing blocks the
    /// entry (hard rule 1).
    private func fetchPendingBlobs() async {
        guard !pendingBlobIDs.isEmpty,
              let fetcher = SyncService.makeBlobFetcher(sessionStore: KeychainSessionStore()) else { return }
        for id in pendingBlobIDs {
            guard let attachment = attachments.first(where: { $0.id == id }) else { continue }
            if (try? await fetcher.fetch(sha256: attachment.file.sha256)) != nil {
                pendingBlobIDs.remove(id)
            }
        }
    }

    private static func mostRecentID(_ entries: [any Entry]) -> UUID? {
        entries.max { $0.date < $1.date }?.id
    }

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
            // Re-apply the conversion on save: editing amount/currency clears
            // the snapshot (hard rule 3), and the money must come back with a
            // rate - a manual rate if the user set one, the store's for the
            // entry's date otherwise, rate-pending only when neither exists
            // (F9). Without this an edited foreign fill-up silently lost its
            // conversion and saved rate-pending.
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
            try repository.upsertFillUp(updated)
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
            var updated = entry
            updated.updatedAt = Date()
            updated.date = nonFillForm.date
            updated.odometer = nonFillForm.odometerValue
            updated.money = nonFillForm.editedMoney(original: entry.money,
                                                    homeCurrency: vehicle.homeCurrency)
            updated.note = nonFillForm.note.isEmpty ? nil : nonFillForm.note

            // PJ.11: F9a is checked on every write, not just capture. An edit
            // that moves an odometer or a date can break the timeline exactly
            // as a new entry can, and the flag must land with the save - never
            // left to a later read. The stamp never blocks the write (hard rule
            // 13: the user decided; the amber badge surfaces it later).
            let validations = TimelineValidator.validate(entries: otherEntries + [updated],
                                                         vehicle: vehicle)
            updated.conflict = validations.first { $0.entryID == updated.id }?.conflict ?? .none

            switch updated {
            case var charge as ChargeSession:
                charge.provider = nonFillForm.provider.isEmpty ? nil : nonFillForm.provider
                if let kWh = Double(nonFillForm.energyKWh) { charge.energyKWh = kWh }
                charge.conflict = updated.conflict
                try repository.upsertChargeSession(charge)
            case var service as ServiceRecord:
                service.vendor = nonFillForm.vendor.isEmpty ? nil : nonFillForm.vendor
                service.conflict = updated.conflict
                try repository.upsertServiceRecord(service)
            case var expense as Expense:
                expense.title = nonFillForm.title
                expense.conflict = updated.conflict
                try repository.upsertExpense(expense)
            default:
                break
            }
            // A non-fill edit never moves consumption segments; there is no
            // delta to toast about - Home just reloads.
            toastCenter.noteEntryChanged()
            dismiss()
        } catch {
            AppLog.error(operation: "editEntry.save", category: .ui, error: error)
        }
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

    // MARK: - Delete

    private func performDelete() {
        do {
            let repository = try AppStore.repository()
            if let fill = fillUp {
                try repository.softDeleteFillUp(id: fill.id)
            } else if let charge = charge {
                try repository.softDeleteChargeSession(id: charge.id)
            } else if let service = service {
                try repository.softDeleteServiceRecord(id: service.id)
            } else if let expense = expense {
                try repository.softDeleteExpense(id: expense.id)
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
    func fillUpContent(_ fill: FillUp) -> some View {
        ScrollView {
            VStack(spacing: 9) {
                if !attachments.isEmpty {
                    EditEntryRows.receiptCard(attachments: attachments, entry: fill,
                                              pendingBlobIDs: pendingBlobIDs)
                } else if attachImage != nil {
                    pendingReceiptCard
                } else {
                    EditEntryRows.receiptCard(attachments: attachments, entry: fill,
                                              pendingBlobIDs: pendingBlobIDs,
                                              onAddReceipt: { showAttachSource = true })
                }
                if attachFailed {
                    attachFailedWarn
                }
                ManualFillUpDateRow(date: $fillForm.date, showDatePicker: $showDatePicker)
                ManualFillUpOdometerCard(form: $fillForm, focus: $fillFocus,
                                         distanceUnit: distanceUnit,
                                         conflict: odometerConflict,
                                         onFixDate: { showDatePicker = true })
                ManualFillUpStationRow(stations: stations, selection: $selectedStation)
                ManualFillUpFuelFullCard(form: $fillForm, fuelKinds: vehicle?.fuelKinds ?? [.petrol95])
                if editCurrencyNeedsAttention { editCurrencySection }
                ManualFillUpNumbersCard(form: $fillForm, focus: $fillFocus,
                                        volumeUnit: volumeUnit, currencySymbol: currencySymbol,
                                        reduceMotion: accessibilityReduceMotion)
                if !editCurrencyNeedsAttention { editCurrencySection }
                if editConversionState.showsConversionCard, let vehicle {
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
                if showChangedBySync {
                    EditEntryRows.changedBySyncRow
                }
                EditEntryRows.footer
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .bottom) { saveBar }
    }
}

// MARK: - PJ.48 attach a receipt to a typed entry

private extension EditEntryView {
    /// The screenshot/test hook `-seedAttachSuggestion`: applies a synthetic
    /// OCR reading through the REAL merge + apply path (blank fields only,
    /// dimmed until confirmed), so a screenshot can show the post-attach state
    /// without driving the out-of-process Photos picker.
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

    /// One image in, one set of blank-fields-only suggestions out. The OCR runs
    /// through the same `CapturePipeline` the scan door uses; the merge then
    /// decides which fields are blank on the TYPED entry, and only those are
    /// offered as dimmed pre-fills (hard rule 13). A typed value is never
    /// overwritten and raises no amber (docs/ERRORS.md -> Edit entry).
    func attachReceipt(_ image: UIImage) {
        guard let fillUp else { return }
        attachFailed = false
        attachImage = image
        attachProcessing = true
        Task {
            let prefill = await CapturePipeline.process(image, source: .receipt)
            attachOcrLines = prefill.ocrLines
            let extraction = prefill.extraction ?? FuelExtraction()
            attachExtraction = extraction
            let suggestions = ReceiptAttachMerge.suggestions(entry: fillUp, extraction: extraction)
            fillForm.applyAttachedSuggestions(suggestions, extraction: extraction)
            attachProcessing = false
        }
    }

    /// The post-pick, pre-save receipt card: the photo is held in memory and
    /// will be written when Save runs. A spinner marks the OCR still reading;
    /// the `editAttachReady` identifier flips on when the reading finishes, so
    /// a UI test can wait for the attach to settle before saving.
    private var pendingReceiptCard: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.Palette.dash)
                .frame(width: 44, height: 56)
                .overlay(
                    Image(systemName: "photo")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Receipt photo")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("Receipt attached")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            Spacer(minLength: 0)
            if attachProcessing {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Theme.Palette.inkSoft)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.taillight)
            }
        }
        .padding(12)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(attachProcessing ? "editAttachProcessing" : "editAttachReady")
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

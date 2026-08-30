import SwiftUI
import TankbookCore

/// The ConfirmManual sheet (P1.3): the manual fill-up form, and the fallback
/// the whole capture pipeline degrades to (docs/JOURNEYS.md F1 - the failure
/// state IS this form). Stands alone: no camera, no OCR, no network.
///
/// Matches design/screens/ConfirmManual.dc.html: the three-number card with
/// live derivation and the cross-check line, fuel kind, full-tank toggle, the
/// last-known odometer, station, date, and the taillight Save bar. The core
/// rule (docs/SCHEMA.md -> FillUp): type any two of total / litres / price, the
/// third derives on save and `crossCheck = .notApplicable`; type all three and
/// the cross-check applies. Money is always a pair (hard rule 3) - with no
/// rates service a foreign currency saves rate-pending ("≈ – · converts when
/// online") and backfills later, never silently converted.
///
/// P2.3: the scanned path lands in THIS SAME sheet (hard rule 15 - manual and
/// scan are peer paths). An optional `prefill` carries the extraction, its
/// per-field crops and the fiscal QR anchor; present fields pre-fill, nil
/// fields stay blank and focusable, resolved-but-unconfirmed fields dim to 60%
/// opacity and stay fully editable (hard rule 13), and the QR anchor outranks
/// the OCR total.
struct ManualFillUpView: View {
    @Binding var hasUnsavedChanges: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCarSelection.self) private var carSelection
    @Environment(ReminderNotificationCoordinator.self) private var notificationCoordinator
    @Environment(AppConfigService.self) private var config
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    /// The scanned-path input (P2.3). `nil` is the manual form with nothing
    /// pre-filled - never an error, never a "scan failed" state (hard rule 15).
    private let injectedPrefill: ConfirmPrefill?

    @State var form = ManualFillUpFormState()
    @FocusState private var focus: ManualFillUpFocus?
    @State var vehicle: Vehicle?
    @State private var existingEntries: [any Entry] = []
    /// PJ.14: the last-known odometer + entry date, driving the live delta caption.
    @State private var lastKnown: OdometerLastKnown?
    @State private var stations: [Station] = []
    @State private var selectedStation: Station?
    @State var currencyLowConfidence = false
    @State private var showDatePicker = false
    @State private var showTankLevel = false
    @State private var didLoad = false
    @State private var verifyCrop: VerifyCrop?
    @State private var detection: MixedReceiptDetection = .notMixed
    @State private var acceptedLineIDs: Set<UUID> = []
    /// P6.3: the cloud-reading session (docs/API.md -> "The device's side of
    /// /extract"). Idle for the typed path; started when a scan carries a photo
    /// and a gateway is available. Drives the 3 s budget banner and the
    /// fill-blanks-only late answer.
    @State private var gatewaySession = GatewayScanSession()
    /// The fields the ON-DEVICE extraction resolved (the pre-fill already on
    /// screen). A late gateway answer never refills one of these (F4).
    @State private var gatewayOnDeviceResolved: Set<FieldRef> = []
    /// Arming guard for the currency/fuelKind/date touch hooks: the form's own
    /// load-time assignment must not count as a user touch.
    @State private var gatewayTouchTrackingArmed = false

    init(prefill: ConfirmPrefill? = nil, hasUnsavedChanges: Binding<Bool>) {
        self.injectedPrefill = prefill
        self._hasUnsavedChanges = hasUnsavedChanges
    }

    var volumeUnit: VolumeUnit { vehicle?.units.volume ?? .l }
    private var distanceUnit: DistanceUnit { vehicle?.units.distance ?? .km }

    /// Reduce Motion (docs/DESIGN.md -> Motion): the cross-check lock's spring
    /// draw-in degrades to a plain state change - the tick still appears, just
    /// without the animation. The launch-argument override exists so a UI test
    /// can pin the setting it cannot reach through XCUITest.
    /// A currency needing attention renders ABOVE the numbers card; the folded
    /// home-currency case sits below it. Opening itself below the fold would not
    /// be opening at all.
    private var currencyNeedsAttention: Bool {
        guard let vehicle else { return false }
        return ManualFillUpCurrencySection.needsAttention(
            currency: form.currency, homeCurrency: vehicle.homeCurrency,
            lowConfidence: currencyLowConfidence, state: conversionState)
    }

    @ViewBuilder
    private var currencySection: some View {
        if let vehicle {
            ManualFillUpCurrencySection(
                form: $form,
                homeCurrency: vehicle.homeCurrency,
                lowConfidence: currencyLowConfidence,
                state: conversionState)
        }
    }

    private var reduceMotion: Bool {
        accessibilityReduceMotion || ProcessInfo.processInfo.arguments.contains("-forceReduceMotion")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                if vehicle == nil {
                    noVehicleCard
                } else {
                    // Field order matches Edit entry (docs/DESIGN.md - entry
                    // form order): Date, Odometer, Station, Fuel, the numbers,
                    // then currency. The artboards drew the numbers first
                    // because the scan's payload is what arrives first; in the
                    // hand it put the ODOMETER - the field consumption depends
                    // on, and the one a scan can never read - below the fold and
                    // behind the pinned Save bar. One order across both screens
                    // also means muscle memory transfers between them.
                    ManualFillUpDateRow(date: $form.date, showDatePicker: $showDatePicker)
                    if cloudExtractSurface && !config.allowsServerBacked {
                        UpdateRequiredNotice()
                    }
                    if gatewaySession.phase == .budgetExpired {
                        gatewayTimeoutBanner
                    }
                    ManualFillUpOdometerCard(form: $form, focus: $focus, distanceUnit: distanceUnit,
                                             conflict: odometerConflict,
                                             onFixDate: { showDatePicker = true },
                                             lastKnown: lastKnown,
                                             paceLimitKmPerDay: vehicle!.paceLimitKmPerDay)
                    ManualFillUpStationRow(stations: stations, selection: $selectedStation)
                    ManualFillUpFuelFullCard(form: $form, fuelKinds: vehicle!.fuelKinds)
                    if !form.isFull {
                        TankLevelRow(isFull: form.isFull,
                                     tankLevelAfterPct: form.tankLevelAfterPct,
                                     action: { showTankLevel = true })
                            .formCard()
                    }
                    if currencyNeedsAttention { currencySection }
                    ManualFillUpNumbersCard(
                        form: $form, focus: $focus,
                        volumeUnit: volumeUnit,
                        currencySymbol: currencySymbol,
                        crops: prefill?.crops ?? [:],
                        reduceMotion: reduceMotion,
                        onVerify: { field, crop in verifyCrop = VerifyCrop(field: field, evidence: crop) })
                    if !currencyNeedsAttention { currencySection }
                    if conversionState.showsConversionCard {
                        ForeignCurrencyCard(
                            currency: form.currency,
                            homeCurrency: vehicle!.homeCurrency,
                            state: conversionState,
                            convertedAmount: convertedAmount,
                            manualRate: $form.manualRate,
                            isManualRateEditorOpen: $form.isManualRateEditorOpen)
                    }
                    if case .mixed(let lines, let fuelLine, let grandTotal) = detection {
                        MixedReceiptSection(
                            lines: lines,
                            acceptedLineIDs: $acceptedLineIDs,
                            currencySymbol: currencySymbol,
                            receiptTotal: grandTotal,
                            fillUpAmount: fuelLine)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.Palette.midnight)
        .safeAreaInset(edge: .bottom) { saveBar }
        .task { await load() }
        .sheet(isPresented: $showTankLevel) {
            DiscardAwareSheet(policy: .discardSilently, hasUnsavedChanges: .constant(false)) {
                TankLevelSheet(tankLevelAfterPct: $form.tankLevelAfterPct,
                               isFull: $form.isFull,
                               capacityL: vehicle?.tankCapacityL)
                    .navigationTitle("Tank level")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(item: $verifyCrop) { crop in
            VerifyCropSheet(evidence: crop.evidence)
        }
        .onChange(of: focus) { _, newValue in
            // Tapping a pre-filled field confirms it (docs/DESIGN.md: dimmed
            // "until confirmed by tap or edit"). The odometer is not a pump
            // card figure, so it is not part of the confidence set.
            if let field = newValue?.mathField {
                form.userConfirmedFields.insert(field)
                // P6.3: engagement is permanent - a tapped field is the user's
                // own, and no late gateway answer may overwrite it (hard rule
                // 13).
                gatewaySession.markTouched(field.fieldRef)
            }
        }
        .onChange(of: form, initial: true) { _, newValue in
            if let vehicle {
                hasUnsavedChanges = newValue.hasEdits(vehicle: vehicle)
            }
        }
        // P6.3: touching the non-math fields is engagement too. Guarded so the
        // load-time pre-fills (currency = home, fuel kind default, date =
        // extraction/today) never count as touches.
        .onChange(of: form.currency) { _, _ in
            if gatewayTouchTrackingArmed { gatewaySession.markTouched(.currency) }
        }
        .onChange(of: form.fuelKind) { _, _ in
            if gatewayTouchTrackingArmed { gatewaySession.markTouched(.fuelKind) }
        }
        .onChange(of: form.date) { _, _ in
            if gatewayTouchTrackingArmed { gatewaySession.markTouched(.date) }
        }
    }

    private var prefill: ConfirmPrefill? {
        injectedPrefill ?? ConfirmPrefillSeed.from(arguments: ProcessInfo.processInfo.arguments)
    }

    /// Whether this sheet is a cloud-extract surface (P6.18b): a scan carried a
    /// photo the gateway would have read. Under `.required` the reading is
    /// withheld and the update notice renders in its place - the on-device
    /// result still stands, nothing is lost.
    private var cloudExtractSurface: Bool {
        prefill?.sourceImage != nil
    }

    private var currencySymbol: String {
        AddVehicleSupport.currencySymbol(for: form.currency)
    }

    private var odometerConflict: OdometerConflict? {
        guard let vehicle else { return nil }
        return form.odometerConflict(vehicle: vehicle,
                                     existingEntries: existingEntries,
                                     distanceUnit: distanceUnit)
    }

    // MARK: - Loading

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        ManualFillUpTestSeed.seedIfRequested()
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            // The selected-car invariant: the entry-creating path writes to the
            // SAME car Home and Trends show, never "the first one" (P1.11).
            guard let vehicle = carSelection.selectedVehicle(vehicles) else {
                return
            }
            self.vehicle = vehicle
            existingEntries = try repository.liveEntries(forVehicle: vehicle.id)
            stations = try repository.liveStations()
            form.currency = vehicle.homeCurrency
            form.fuelKind = vehicle.fuelKinds.first ?? .petrol95
            lastKnown = OdometerLastKnown.lastKnown(in: existingEntries, vehicle: vehicle)
            form.odometer = lastKnown?.odometer.map(String.init) ?? ""
            if let prefill {
                apply(prefill, vehicle: vehicle)
                detectMixedReceipt(prefill)
                startGatewayReading(prefill: prefill)
            }
            // The pre-fill snapshots are taken AFTER the convenience pre-fills
            // (odometer, date, extraction): none of them count as an edit.
            form.initialOdometer = form.odometer
            form.initialDate = form.date
            form.initialTotal = form.total
            form.initialLiters = form.liters
            form.initialPricePerL = form.pricePerL
            form.initialManualRate = form.manualRate
            // P6.3: touch tracking is armed only after the load-time pre-fills
            // have been written - from now on, a change is a user touch.
            gatewayTouchTrackingArmed = true
            currencyLowConfidence = currencyLowConfidence
                || ProcessInfo.processInfo.arguments.contains("-forceCurrencyLowConfidence")
            if ProcessInfo.processInfo.arguments.contains("-screenshotPrefill") {
                // Screenshot hook: land the three-number card in its derived
                // state (total + liters typed, price fills in) without typing.
                form.total = "71.02"
                form.liters = "42.30"
            }
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-manualRate"),
               ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
                // Screenshot hook: pre-fill the manual-rate field so the card
                // renders as converted-from-Manual without typing (the P5.2b
                // screenshot state). Same default-input rules as any pre-fill.
                form.manualRate = ProcessInfo.processInfo.arguments[index + 1]
            }
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-screenshotOdometer"),
               ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
                form.odometer = ProcessInfo.processInfo.arguments[index + 1]
            }
        } catch {
            AppLog.error(operation: "confirmManual.load", category: .ui, error: error)
        }
    }

    /// P2.3: the extraction becomes default input, field by field. A nil value
    /// stays blank and focusable - never `0` (a zero is a wrong fact, a blank
    /// is an honest absence). Every pre-filled value stays editable at the
    /// moment it is offered and afterwards (hard rule 13).
    private func apply(_ prefill: ConfirmPrefill, vehicle: Vehicle) {
        guard let extraction = prefill.extraction else { return }
        currencyLowConfidence = prefill.currencyLowConfidence
        form.resolvedByExtraction.removeAll()
        // P6.3: the fields the ON-DEVICE pipeline resolved are the late-answer
        // boundary (F4) - the on-device result has first claim, and a gateway
        // answer never refills one of them. Recorded before the pre-fill is
        // applied below, because it is about the extraction, not the form.
        gatewayOnDeviceResolved = Self.onDeviceResolvedFields(extraction)
        switch ConfirmQRTotal.resolve(extraction: extraction, qrAnchor: prefill.qrAnchor) {
        case .noAnchor(let ocrTotal):
            applyTotal(ocrTotal)
            // The OCR total is exactly as trustworthy as the other OCR fields.
            if extraction.total != nil { form.resolvedByExtraction.insert(.total) }
        case .ocrConfirmed(let total):
            // The QR grand total AGREES with the OCR total: the value is exact
            // and double-confirmed, never dimmed.
            applyTotal(total)
        case .qrAuthoritative(let total):
            // The QR total outranks the OCR one and fills the field: exact,
            // never dimmed.
            applyTotal(total)
        case .fuelLineStands(let total):
            // The fill-up amount is the fuel line (hard rule 4). OCR-derived,
            // so it dims like any other OCR value until confirmed.
            applyTotal(total)
            form.resolvedByExtraction.insert(.total)
        }
        form.liters = ConfirmFormat.string(fromExtraction: extraction.liters, fractionDigits: 2)
        form.pricePerL = ConfirmFormat.string(fromExtraction: extraction.unitPrice, fractionDigits: 3)
        form.currency = extraction.currency ?? vehicle.homeCurrency
        if let kind = extraction.fuelKind, vehicle.fuelKinds.contains(kind) {
            form.fuelKind = kind
        }
        if let rawDate = extraction.date, let date = ConfirmDate.parse(rawDate) {
            form.date = date
        }
        // Which fields the OCR actually resolved, for the dimming gate (the
        // total is handled above, per its resolution source).
        if extraction.liters != nil { form.resolvedByExtraction.insert(.volume) }
        if extraction.unitPrice != nil { form.resolvedByExtraction.insert(.unitPrice) }
    }

    private func applyTotal(_ total: Decimal?) {
        form.total = total.map { ConfirmFormat.string(decimal: $0, fractionDigits: 2) } ?? ""
    }

    /// P2.4: run the mixed-receipt detector over the scanned lines and seed the
    /// "Also on this receipt" toggles. Car-related lines default to accepted,
    /// non-car lines to dismissed - a suggestion the user can always flip. The
    /// detector is conservative, so an ordinary receipt simply leaves the sheet
    /// as the normal Confirm form.
    private func detectMixedReceipt(_ prefill: ConfirmPrefill) {
        guard let extraction = prefill.extraction else { return }
        detection = MixedReceiptDetector.detect(lines: prefill.ocrLines,
                                                extraction: extraction,
                                                qrAnchor: prefill.qrAnchor)
        if case .mixed(let lines, _, _) = detection {
            acceptedLineIDs = Set(lines.filter(\.isCarRelated).map(\.id))
        }
    }

    // MARK: - P6.3 the gateway reading (docs/API.md rules 2 & 3)

    /// The fields the on-device extraction resolved - the late answer's
    /// "not blank" boundary. The QR-anchored total is NOT one of these: a QR
    /// total is exact, and treating it as on-device-resolved would be fine too
    /// (it is never blank), but the extraction's own fields are the honest set.
    private static func onDeviceResolvedFields(_ extraction: FuelExtraction) -> Set<FieldRef> {
        var resolved = Set<FieldRef>()
        if extraction.total != nil { resolved.insert(.total) }
        if extraction.liters != nil { resolved.insert(.volume) }
        if extraction.unitPrice != nil { resolved.insert(.unitPrice) }
        if extraction.date != nil { resolved.insert(.date) }
        if extraction.currency != nil { resolved.insert(.currency) }
        if extraction.fuelKind != nil { resolved.insert(.fuelKind) }
        return resolved
    }

    /// Fires the background `/extract` request when this scan has a photo and a
    /// gateway is available (signed in, or a seeded test transport). The card
    /// on screen is the on-device result - the app never waits on the gateway
    /// to show it (F4).
    private func startGatewayReading(prefill: ConfirmPrefill) {
        // P6.18b: under `.required` the `/extract` request is withheld - the
        // server has stopped supporting this build (the same set 426 already
        // withholds, docs/CONFIG.md). The on-device result is already on
        // screen; the update notice explains the pause.
        guard config.allowsServerBacked else { return }
        guard let sourceImage = prefill.sourceImage,
              let cgImage = sourceImage.cgImage,
              let transport = GatewayScanStarter.makeTransport() else { return }
        guard let jpeg = GatewayRendition.jpegData(from: cgImage) else { return }
        let request = GatewayExtractRequest(
            kind: "receipt",
            imageJPEG: jpeg,
            hints: gatewayHints())
        gatewaySession.start(transport: transport, request: request) { extraction in
            // A value-captured view struct: `@State` wraps shared storage, so
            // mutating `form` through the copy lands in the box the live view
            // reads. The session's `deliver` already guards the saved state.
            self.applyGatewayAnswer(extraction)
        }
    }

    private func gatewayHints() -> GatewayExtractHints {
        let current = Locale.current
        let language = current.language.languageCode?.identifier ?? "en"
        return GatewayExtractHints(
            currency: form.currency.rawValue,
            locale: language,
            vehicleFuelKinds: vehicle?.fuelKinds.map(\.rawValue) ?? [])
    }

    /// Applies a gateway answer - within budget or late - as a SUGGESTION,
    /// bound by hard rule 13 and F4: only fields that are still blank AND
    /// untouched, on an unsaved entry. Applied fields are marked as resolved
    /// but unconfirmed, so they render dimmed exactly like any other extraction
    /// suggestion until the user confirms them.
    private func applyGatewayAnswer(_ extraction: GatewayExtraction) {
        guard let vehicle else { return }
        let snapshot = GatewaySuggestionSnapshot(
            touched: gatewaySession.touched,
            onDeviceResolved: gatewayOnDeviceResolved,
            saved: gatewaySession.phase == .saved)
        let fillable = GatewaySuggestionPolicy.fillableFields(answer: extraction, snapshot: snapshot)

        for ref in fillable {
            switch ref {
            case .total:
                if let total = extraction.total?.value {
                    form.total = ConfirmFormat.string(decimal: total, fractionDigits: 2)
                    form.resolvedByExtraction.insert(.total)
                }
            case .volume:
                if let volume = extraction.volume?.value {
                    form.liters = ConfirmFormat.string(fromExtraction: volume, fractionDigits: 2)
                    form.resolvedByExtraction.insert(.volume)
                }
            case .unitPrice:
                if let price = extraction.unitPrice?.value {
                    form.pricePerL = ConfirmFormat.string(decimal: price, fractionDigits: 3)
                    form.resolvedByExtraction.insert(.unitPrice)
                }
            case .currency:
                // The form's own currency chip rule: a suggested currency stays
                // a default input, never silently converted.
                if let currency = extraction.currency?.value {
                    form.currency = currency
                }
            case .fuelKind:
                // Only a kind this vehicle actually accepts (docs/EXTRACTION.md:
                // a visible grade is evidence the station sells it, never that
                // this fill used it).
                if let kind = extraction.fuelKind?.value, vehicle.fuelKinds.contains(kind) {
                    form.fuelKind = kind
                }
            case .date:
                if let raw = extraction.date?.value, let date = ConfirmDate.parse(raw) {
                    form.date = date
                }
            default:
                break
            }
        }
    }

    /// The 3 s budget message (docs/API.md rule 2, hard rule 7): it names the
    /// next step - carry on with what was read on-device - and it carries no
    /// upsell (the Pro tier is deferred; monetization appears in no error
    /// surface here, and an upsell mid-capture is explicitly forbidden).
    private var gatewayTimeoutBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hourglass.bottomhalf.filled")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("Cloud reading continues in the background – keep going with what was read here.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gatewayTimeoutMessage")
    }

    // MARK: - Save

    private var saveEnabled: Bool {
        guard let vehicle else { return false }
        return form.canSave(volumeUnit: volumeUnit)
    }

    /// The save-bar label. On a mixed receipt it counts the accepted Expenses
    /// ("Save fill-up + 1 expense"), so the user knows exactly what Save writes.
    private func saveTitle() -> String {
        guard case .mixed(let lines, _, _) = detection else {
            return L10n.localize("Save fill-up")
        }
        let accepted = lines.filter { acceptedLineIDs.contains($0.id) }.count
        if accepted > 0 {
            return String(localized: "Save fill-up + \(accepted) expenses")
        }
        return L10n.localize("Save fill-up")
    }

    private func save() {
        guard let vehicle, let derived = form.derived(volumeUnit: volumeUnit) else { return }
        do {
            let repository = try AppStore.repository()
            let scanned = scannedSavePlan(derived: derived)
            let plan = ReceiptGroupPlanner.plan(detection: detection,
                                                fillUpAmount: derived.total,
                                                acceptedLineIDs: acceptedLineIDs)
            // The scanned save's one receipt photo: written once, shared by the
            // fill-up and every accepted expense. A write failure degrades to
            // no photo, never blocks the entry (ERRORS.md -> Confirm, "Storage full").
            let attachmentIDs = receiptAttachmentIDs(scanned: scanned, repository: repository)
            var toSave = buildFillUp(vehicle: vehicle, derived: derived,
                                     attachments: attachmentIDs,
                                     provenance: scanned.provenance,
                                     extraction: scanned.extraction)
            if let plan {
                // Grouped save (P2.4): the FillUp and every accepted Expense
                // share one purchaseGroupId AND the same receipt photo
                // (PJ.2: one photograph of one receipt, never a copy per row).
                toSave.purchaseGroupId = plan.purchaseGroupId
                let now = Date()
                for expense in plan.expenses {
                    let row = Expense(
                        id: expense.id, createdAt: now, updatedAt: now, deletedAt: nil,
                        vehicleId: vehicle.id, date: form.date, odometer: nil,
                        money: convertForSave(Money(amount: expense.amount, currency: form.currency,
                                                    homeCurrency: vehicle.homeCurrency)),
                        note: nil, attachments: attachmentIDs, provenance: scanned.provenance,
                        conflict: .none, purchaseGroupId: plan.purchaseGroupId,
                        category: expense.category, title: expense.title)
                    try repository.upsertExpense(row)
                }
            }
            try repository.upsertFillUp(toSave)
            hasUnsavedChanges = false
            // A new entry was written with no delta toast - tell Home to
            // reload anyway (docs/ERRORS.md -> Edit entry, row 4; hard rule 2),
            // exactly as Edit entry, Vehicle detail and Recently deleted do on
            // their saves. Without this, Home keeps showing the pre-save state
            // after the sheet dismisses (a `.sheet` never re-triggers the
            // presenter's `.task` on iOS 26).
            toastCenter.noteEntryChanged()
            // P6.3 (F4): a saved entry is corrected by its owner alone -
            // nothing arrives after save, whatever the background request does.
            gatewaySession.markSaved()
            // Odometer arming (P3.6): a save can cross a reminder's dueOdometer
            // window; reconcile arms the notification at write time.
            Task { await notificationCoordinator.reconcile(vehicleId: vehicle.id) }
            dismiss()
        } catch {
            AppLog.error(operation: "confirmManual.save", category: .ui, error: error)
        }
    }
}

// MARK: - PJ.2 the scanned save (one receipt photo, shared)

/// The receipt photo could not be encoded or written (PJ.2); the save degrades
/// to no photo - docs/ERRORS.md -> Confirm, "Storage full".
enum ReceiptAttachmentError: Error {
    case notEncodable
}

private extension ManualFillUpView {
    /// The save's scan shape: the shared attachment id, the provenance, and the
    /// extraction record. `nil` prefill IS the typed path (hard rule 15): no
    /// attachment, `.manual`, no extraction record.
    func scannedSavePlan(derived: ManualFillUpMath.Derived) -> ScannedSavePlan {
        ScannedSavePlanner.plan(
            extraction: prefill?.extraction,
            cropRects: cropRects(from: prefill?.crops ?? [:]),
            qrAnchor: prefill?.qrAnchor,
            declaredProvenance: prefill?.provenance ?? .manual,
            hasPhoto: prefill?.sourceImage != nil,
            saved: ScannedSaveValues(total: derived.total, volumeL: derived.volumeL,
                                     unitPrice: derived.unitPrice, currency: form.currency,
                                     fuelKind: form.fuelKind, date: form.date))
    }

    /// The receipt photo the whole save shares, or `[]` when there is none. A
    /// write failure degrades to no photo, never blocks the entry (hard rule 1).
    func receiptAttachmentIDs(scanned: ScannedSavePlan,
                              repository: TankbookRepository) -> [AttachmentID] {
        guard let attachmentID = scanned.attachmentID else { return [] }
        do {
            try writeReceiptAttachment(id: attachmentID, repository: repository)
            return [attachmentID]
        } catch {
            AppLog.error(operation: "confirmManual.receiptPhotoSave", category: .ui, error: error)
            return []
        }
    }

    /// The prefill's per-field crop evidence becomes the extraction record's
    /// crop rects (`FieldExtraction.cropRect`, image pixel space).
    func cropRects(from crops: [ManualFillUpMath.Field: CropEvidence]) -> [FieldRef: CGRect] {
        crops.reduce(into: [:]) { result, entry in
            result[entry.key.fieldRef] = entry.value.rect
        }
    }

    /// Writes the receipt photo once: file bytes into the shared attachments
    /// directory (the same pool `InvoiceAttachmentFiles` uses, docs/SYNC.md),
    /// one `Attachment` row shared by the fill-up and every accepted expense,
    /// with the inline thumbnail in the payload (P4.6).
    func writeReceiptAttachment(id: AttachmentID,
                                repository: TankbookRepository) throws {
        guard let prefill, let sourceImage = prefill.sourceImage else { return }
        guard let jpeg = sourceImage.jpegData(compressionQuality: 0.8) else {
            throw ReceiptAttachmentError.notEncodable
        }
        let (sha256, relativePath) = try VehiclePhotoStore.save(jpeg, id: id)
        let thumbnail = (try? AttachmentRendition.thumbnailBase64(for: jpeg, kind: .photo)) ?? nil
        let ocrText = prefill.ocrLines.isEmpty ? nil : prefill.ocrLines.map(\.text).joined(separator: "\n")
        // The receipt's own printed date when the extraction read one, else the
        // fiscal QR's timestamp (docs/SCHEMA.md, Attachment.extractedTimestamp).
        let timestamp = (prefill.extraction?.date).flatMap { ConfirmDate.parse($0) }
            ?? prefill.qrAnchor?.date
        let now = Date()
        let attachment = Attachment(
            id: id, createdAt: now, updatedAt: now, deletedAt: nil,
            kind: .photo, file: LocalFileRef(sha256: sha256, relativePath: relativePath),
            extractedTimestamp: timestamp, ocrText: ocrText, thumbnailBase64: thumbnail)
        try repository.upsertAttachment(attachment)
    }
}

// MARK: - The fill-up the save writes

private extension ManualFillUpView {
    /// The `FillUp` the save writes, with the scanned save's attachment id,
    /// provenance and extraction record; the conflict flag is stamped from
    /// `TimelineValidator` (never blocks the save). Kept here for the PJ.11
    /// write-path guard, which pins the validator consult to this file.
    func buildFillUp(vehicle: Vehicle, derived: ManualFillUpMath.Derived,
                     attachments: [AttachmentID], provenance: Provenance,
                     extraction: ExtractionMeta?) -> FillUp {
        let now = Date()
        let money = convertForSave(Money(amount: derived.total, currency: form.currency,
                                         homeCurrency: vehicle.homeCurrency))
        var candidate = FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: form.date, odometer: form.odometerValue,
            money: money, note: nil, attachments: attachments, provenance: provenance,
            conflict: .none, purchaseGroupId: nil,
            volumeL: derived.volumeL, unitPrice: derived.unitPrice,
            fuelKind: form.fuelKind, fuelGrade: nil, isFull: form.isFull,
            tankLevelAfterPct: form.isFull ? 100 : form.tankLevelAfterPct,
            stationId: selectedStation?.id,
            crossCheck: derived.crossCheck, extraction: extraction)
        let validations = TimelineValidator.validate(entries: existingEntries + [candidate],
                                                     vehicle: vehicle)
        candidate.conflict = validations.first { $0.entryID == candidate.id }?.conflict ?? .none
        return candidate
    }
}

// MARK: - Save bar

private extension ManualFillUpView {
    var saveBar: some View {
        VStack(spacing: 8) {
            Button(action: save) {
                Text(saveTitle())
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
            .accessibilityIdentifier("manualFillUpSaveButton")

            if !saveEnabled {
                Text("Enter total and liters to save")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("manualFillUpSaveHint")
            }
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Theme.Palette.midnight)
    }
}

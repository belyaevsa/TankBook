import os
import SwiftUI
import UIKit
import TankbookCore

/// The ServiceEntry sheet (P3.1a): the typed path for a service visit
/// (docs/JOURNEYS.md J7). The scanned invoice path (P3.1b) drops in later as a
/// pre-fill of these same fields - the same screen, never a second one
/// (hard rule 15 - manual and scan are peer paths).
///
/// Matches design/screens/ServiceEntry.dc.html: the mode row, the vendor + total
/// header, the Date / Odometer card (odometer pre-filled from the last known
/// value and editable - hard rule 13), line items with category and cost, "Add
/// line item", and "Save service". A record with one uncategorized item carrying
/// the whole total saves exactly like a multi-item one - nothing pushes the user
/// to itemize (J7).
struct ServiceEntryView: View {
    @Binding var hasUnsavedChanges: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCarSelection.self) private var carSelection
    @Environment(ServiceInvoiceSession.self) private var invoiceSession
    @Environment(ExpenseEntrySession.self) private var expenseSession
    @Environment(ReminderCompletionSession.self) private var completionSession
    @Environment(ReminderNotificationCoordinator.self) private var notificationCoordinator

    @State private var form = ServiceEntryFormState()
    @FocusState private var focus: ServiceEntryFocus?
    @State private var vehicle: Vehicle?
    @State private var showDatePicker = false
    @State private var didLoad = false
    @State private var lastKnownOdometer: Int?
    /// The scanned invoice's pages (P3.1b). Empty on the typed path.
    @State private var pages: [InvoicePage] = []
    /// True when the date row's provenance is the invoice's printed date, which
    /// renders the "· invoice" caption (design/screens/ServiceEntry.dc.html).
    @State private var dateFromInvoice = false
    @State private var selectedPageIndex = 0
    @State private var showDocumentCamera = false
    /// The parts on the shelf and the parts linked into this service (P3.2).
    @State private var shelfParts: [Expense] = []
    @State private var linkedParts: [Expense] = []
    /// A nested sheet over this one: the Expense entry (Parts/Other modes) or
    /// the Parts shelf.
    @State private var nestedSheet: SheetRoute?
    /// The vehicle's tire sets, for the Tires mode picker (P3.3).
    @State private var tireSets: [TireSet] = []
    /// A reminder completion handed off by the ReminderComplete sheet (P3.5):
    /// pre-fills this form and, on save, completes the reminder with the
    /// entry's real id. Consumed at load; held locally for the save.
    @State private var pendingCompletion: ReminderCompletionSession.Pending?

    private static let log = Logger(subsystem: "app.tankbook", category: "serviceEntry")

    private var distanceUnit: DistanceUnit { vehicle?.units.distance ?? .km }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                if vehicle == nil {
                    noVehicleCard
                } else {
                    if !pages.isEmpty {
                        ServiceEntryPageStrip(pages: pages,
                                              selectedIndex: $selectedPageIndex,
                                              onAddPage: addPage,
                                              onRemovePage: removePage)
                    }
                    // Both halves of the row: Service/Tires select a mode
                    // (P3.3), Parts/Other are forward exits into the Expense
                    // entry (P3.2). Each agent wired only its own pair.
                    ServiceEntryModeRow(mode: $form.mode,
                                        onParts: { openExpense(preset: .parts) },
                                        onOther: { openExpense(preset: nil) })
                    if form.mode == .tires {
                        ServiceEntryTireSetCard(
                            tireSets: tireSets,
                            selectedID: form.tireSetId,
                            onSelect: { form.tireSetId = $0 })
                    } else {
                        ServiceEntryHeader(vendor: $form.vendor, totalText: totalText)
                    }
                    ServiceEntryDateOdometerCard(
                        form: $form,
                        focus: $focus,
                        distanceUnit: distanceUnit,
                        showDatePicker: $showDatePicker,
                        odometerRequired: form.requiresOdometer,
                        onFillOdometer: fillOdometer,
                        provenanceCaption: dateProvenanceCaption)
                    if showDatePicker {
                        DatePicker("", selection: $form.date, in: ...Date(),
                                   displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .accessibilityIdentifier("serviceEntryDatePicker")
                            .padding(.horizontal, Theme.Spacing.cardPadding)
                    }
                    if form.mode == .service {
                        ForEach($form.items) { $item in
                            ServiceEntryItemCard(item: $item) {
                                form.items.removeAll { $0.id == item.id }
                            }
                        }
                        ServiceEntryAddItemButton(action: addItem)
                    }
                    ServiceEntryPartsSection(
                        shelfParts: suggestedShelfParts,
                        linkedParts: linkedParts,
                        symbol: symbol,
                        onLink: linkPart,
                        onUnlink: unlinkPart,
                        onViewShelf: { nestedSheet = .partsShelf })
                    ServiceEntryNoteRow(note: $form.note)
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.Palette.midnight)
        .safeAreaInset(edge: .bottom) { saveBar }
        .task { await load() }
        .sheet(isPresented: $showDocumentCamera) {
            DocumentCamera(
                onCancel: { showDocumentCamera = false },
                onResult: { images in
                    showDocumentCamera = false
                    handleAddedPages(images)
                })
        }
        .sheet(item: $nestedSheet) { route in
            SheetDestinationView(route: route)
        }
        .onChange(of: form, initial: true) { _, _ in
            hasUnsavedChanges = form.hasEdits()
        }
    }

    // MARK: - Derived

    private var totalText: String {
        let symbol = AddVehicleSupport.currencySymbol(for: vehicle?.homeCurrency ?? .eur)
        return HomeFormat.entryAmount(form.totalDecimal, symbol: symbol)
    }

    private var symbol: String {
        AddVehicleSupport.currencySymbol(for: vehicle?.homeCurrency ?? .eur)
    }

    private var odometerMissing: Bool {
        form.requiresOdometer && form.odometerValue == nil
    }

    /// On-shelf parts, ordered with the ones matching this service's line-item
    /// categories first (docs/JOURNEYS.md J7b: an oil service offers oil parts
    /// first). The user picks; the app never links automatically (hard rule 13).
    private var suggestedShelfParts: [Expense] {
        PartsShelf.suggested(shelfParts, categories: form.items.map(\.category))
    }

    /// The date row's provenance caption (P3.1b): "· invoice" when the date came
    /// from the invoice's printed date. A `LocalizedStringKey` so the literal
    /// resolves through the String Catalog (the gate scans this computed body).
    private var dateProvenanceCaption: LocalizedStringKey? {
        dateFromInvoice ? "invoice" : nil
    }

    private var saveEnabled: Bool {
        guard vehicle != nil else { return false }
        switch form.mode {
        case .service:
            guard form.hasTitledItem else { return false }
        case .tires:
            guard form.tireSetId != nil else { return false }
        }
        return !odometerMissing
    }

    // MARK: - Actions

    private func addItem() {
        form.items.append(ServiceEntryItemDraft())
    }

    private func fillOdometer() {
        form.odometer = lastKnownOdometer.map(OdometerFormat.grouped) ?? ""
    }

    // MARK: - Parts (P3.2)

    private func openExpense(preset: ExpenseCategory?) {
        expenseSession.pendingPreset = preset
        nestedSheet = .expenseEntry
    }

    private func linkPart(_ part: Expense) {
        shelfParts.removeAll { $0.id == part.id }
        linkedParts.append(part)
        form.linkedPartIds.append(part.id)
    }

    private func unlinkPart(_ part: Expense) {
        linkedParts.removeAll { $0.id == part.id }
        form.linkedPartIds.removeAll { $0 == part.id }
        shelfParts.append(part)
        shelfParts.sort { $0.date > $1.date }
    }

    // MARK: - Loading

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        ServiceEntryTestSeed.seedIfRequested()
        PartsShelfTestSeed.seedIfRequested()
        // The tire-set seed is only for the Tires-mode scenarios (P3.3). Gated
        // on its own flags - calling it on every ServiceEntry presentation would
        // let its `-homeResetDatabase` reset wipe the ServiceEntry seed's
        // vehicle (each seed owns its own once-per-launch reset).
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-seedServiceEntryTires")
            || arguments.contains("-seedTireSets")
            || arguments.contains("-seedTireSetsNoOdometer") {
            TireSetTestSeed.seedIfRequested()
        }
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            guard let vehicle = carSelection.selectedVehicle(vehicles) else { return }
            self.vehicle = vehicle
            let existingEntries = try repository.liveEntries(forVehicle: vehicle.id)
            let lastKnown = existingEntries.compactMap(\.odometer).max() ?? vehicle.initialOdometer
            lastKnownOdometer = lastKnown
            form.odometer = lastKnown.map(OdometerFormat.grouped) ?? ""
            shelfParts = try repository.partsOnShelf(forVehicle: vehicle.id)
            tireSets = try repository.liveTireSets(forVehicle: vehicle.id)
            if let pending = completionSession.pending,
               case .service(let category) = ReminderCompletion.entryKind(for: pending.reminder.category) {
                // The ReminderComplete sheet's "Type amount" hand-off (P3.5):
                // pre-fill category, title and the current odometer - default
                // input the user edits (hard rule 13). Consumed here; the save
                // below completes the reminder with the entry's real id.
                pendingCompletion = pending
                completionSession.pending = nil
                apply(ServiceEntryPrefill(
                    items: [ServiceEntryItemDraft(title: pending.reminder.title,
                                                  category: category)],
                    odometer: pending.completionOdometer.map(OdometerFormat.grouped) ?? "",
                    date: pending.completionDate))
            } else if let prefill = invoiceSession.pendingPrefill {
                apply(prefill)
                invoiceSession.pendingPrefill = nil
            } else if let prefill = ServiceEntryPrefillSeed.from(arguments: ProcessInfo.processInfo.arguments) {
                apply(prefill)
            } else if ProcessInfo.processInfo.arguments.contains("-seedServiceEntryTires") {
                // The Tires-mode screenshot pre-fill (P3.3): a set is chosen for
                // the camera, and the odometer is already pre-filled from the
                // last known value.
                form.mode = .tires
                form.tireSetId = tireSets.first?.id
            }
            // Snapshots are taken AFTER the convenience pre-fills (odometer,
            // date, seed) - none of them count as an edit.
            form.initialVendor = form.vendor
            form.initialItems = form.items
            form.initialOdometer = form.odometer
            form.initialDate = form.date
            form.initialNote = form.note
            form.initialMode = form.mode
            form.initialTireSetId = form.tireSetId
            scheduleAutoAddPageIfRequested()
        } catch {
            Self.log.error("Service entry load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// DEBUG/test-only: `-autoAddServiceEntryPage` appends a page through the
    /// real `handleAddedPages` path a beat after load, so a UI test can prove a
    /// page add never resets a row the user already edited (hard rule 13).
    private func scheduleAutoAddPageIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-autoAddServiceEntryPage") else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            handleAddedPages([InvoicePagePreview.image()])
        }
        #endif
    }

    /// The scanned-path seam (P3.1b): the extraction becomes default input the
    /// user edits. Whatever it produces stays editable at the moment it is
    /// offered and afterwards (hard rule 13).
    private func apply(_ prefill: ServiceEntryPrefill) {
        form.vendor = prefill.vendor
        form.items = prefill.items
        if !prefill.odometer.isEmpty {
            form.odometer = prefill.odometer
        }
        form.date = prefill.date
        pages = prefill.pages
        form.attachments = prefill.pages.map(\.attachment.id)
        form.provenance = prefill.provenance
        dateFromInvoice = prefill.dateFromInvoice
        selectedPageIndex = 0
    }

    // MARK: - Pages (P3.1b)

    private func addPage() {
        showDocumentCamera = true
    }

    private func handleAddedPages(_ images: [UIImage]) {
        Task {
            let newPages = await ServiceInvoiceScanner.appendPages(images: images)
            pages.append(contentsOf: newPages)
            form.attachments = pages.map(\.attachment.id)
            selectedPageIndex = max(0, pages.count - 1)
        }
    }

    /// Removing a page deletes its file - no orphan (docs/ERRORS.md -> Service &
    /// expenses: "Multi-page scan interrupted" names the next step; here the
    /// user removed a page on purpose, so there is nothing to warn about).
    private func removePage(_ page: InvoicePage) {
        pages.removeAll { $0.id == page.id }
        form.attachments = pages.map(\.attachment.id)
        if selectedPageIndex >= pages.count {
            selectedPageIndex = max(0, pages.count - 1)
        }
        do {
            let repository = try AppStore.repository()
            let store = InvoicePageStore(repository: repository, files: InvoiceAttachmentFiles())
            try store.removePage(page.attachment)
        } catch {
            Self.log.error("Page removal failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Save

    private func save() {
        guard let vehicle, saveEnabled else { return }
        do {
            let repository = try AppStore.repository()
            let draft = form.draft(vehicle: vehicle)
            let service = draft.build(vehicleId: vehicle.id, homeCurrency: vehicle.homeCurrency)
            // The other half of each link: the linked expenses carry the record's
            // id, and both halves commit in one transaction (P3.2 - a half-written
            // link is a part that is neither on the shelf nor in the service).
            let now = Date()
            let linkedExpenses = linkedParts.map { part -> Expense in
                var linked = part
                linked.installedInServiceId = service.id
                linked.updatedAt = now
                return linked
            }
            try repository.upsertServiceRecord(service, linkedParts: linkedExpenses)
            // The other half of the P3.5 chain: a reminder completion handed
            // off by the ReminderComplete sheet completes with THIS entry's id.
            if let pending = pendingCompletion {
                ReminderCompletionSession.persistCompletion(
                    reminder: pending.reminder, entryId: service.id,
                    completionDate: pending.completionDate,
                    completionOdometer: pending.completionOdometer,
                    coordinator: notificationCoordinator)
                pendingCompletion = nil
            }
            hasUnsavedChanges = false
            dismiss()
        } catch {
            Self.log.error("Service entry save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Save bar

    private var saveBar: some View {
        VStack(spacing: 8) {
            Button(action: save) {
                Text(form.mode == .tires ? "Save swap" : "Save service")
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
            .accessibilityIdentifier("serviceEntrySaveButton")

            if !saveEnabled {
                Text(saveHint)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("serviceEntrySaveHint")
            }
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Theme.Palette.midnight)
    }

    private var saveHint: String {
        if vehicle == nil { return "" }
        switch form.mode {
        case .service where !form.hasTitledItem:
            return L10n.localize("Add a line item to save")
        case .tires where form.tireSetId == nil:
            return L10n.localize("Select a tire set to save")
        default:
            return ""
        }
    }
}

// MARK: - Focus

/// Which ServiceEntry field holds focus (drives the cyan underline).
enum ServiceEntryFocus: Hashable {
    case odometer
}

// MARK: - No-vehicle hint

extension ServiceEntryView {
    private var noVehicleCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "car")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("No car yet – add one from Garage to start logging services.")
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
        .accessibilityIdentifier("serviceEntryNoVehicleHint")
    }
}

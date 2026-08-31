import Foundation
import TankbookCore

// MARK: - Line item draft

/// One editable line item row on the ServiceEntry screen. `title` + `category`
/// + a typed `cost` string (parsed to `Decimal` on save - never `Double`,
/// docs/SCHEMA.md -> Money). `lifetime` is carried through so the odometer rule
/// (docs/SCHEMA.md) applies the moment a scan or a later task sets a km
/// lifetime; nothing on this screen edits it yet (P3.4 owns the proposal).
struct ServiceEntryItemDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var title = ""
    var category: ServiceCategory = .other("")
    var cost = ""
    var lifetime: ServiceItem.Lifetime?
    /// True when this row was pre-filled by the invoice scanner rather than
    /// typed. A scanned row renders dimmed until the user edits it (hard rule 13:
    /// a scanned value is a default input the user edits, never read-only). The
    /// typed path (P3.1a) never sets this.
    var scanned = false

    /// The typed cost parsed as an exact `Decimal`, or nil when blank. A blank
    /// cost is an honest absence, never a `0` (hard rule 13).
    var costDecimal: Decimal? {
        let trimmed = cost.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed)
    }

    /// True once the item has a title - the row the save gate counts.
    var hasTitle: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Mode

/// Which entry the ServiceEntry sheet is capturing. Only Service and Tires are
/// real records; Parts (P3.2) and Other (Expense) are forward exits rendered as
/// chips in the mode row, not reachable modes.
enum ServiceEntryMode: Equatable {
    case service
    case tires
}

// MARK: - Form state

/// Everything the ServiceEntry screen collects, plus the derived decisions that
/// gate Save (docs/JOURNEYS.md J7). The scanned invoice path (P3.1b) drops in
/// later as a pre-fill of these same fields - a head start the user edits, never
/// a second screen (hard rule 15).
struct ServiceEntryFormState: Equatable {
    var vendor = ""
    var items: [ServiceEntryItemDraft] = []
    var odometer = ""
    var date = Date()
    var note = ""
    /// Which entry this sheet captures. `.service` (line items) or `.tires`
    /// (a seasonal swap mounting one set).
    var mode: ServiceEntryMode = .service
    /// The tire set mounted when `mode == .tires` (P3.3). Nil until a set is
    /// chosen; the odometer rule keys off it.
    var tireSetId: UUID?
    /// The scanned invoice's pages (P3.1b). Empty for the typed path. The files
    /// are written at capture time; removing a page deletes its file.
    var attachments: [AttachmentID] = []
    /// How the record was created. `.manual` (typed) or `.receiptScan` (scanned
    /// invoice). Defaults to `.manual` so the typed path is unchanged.
    var provenance: Provenance = .manual
    /// The shelf parts linked into this service (P3.2). Their ids ride the
    /// record's `usedParts`; the other half of the link (the expense's
    /// `installedInServiceId`) is written at save, so both sides commit together.
    var linkedPartIds: [UUID] = []

    // Snapshots for the discard guard (SCREENMAP rule 1): the form is dirty only
    // for real edits, not for the odometer/date pre-fill. The odometer pre-fill
    // from "last known" is a convenience default, exactly as on ConfirmManual.
    var initialVendor = ""
    var initialItems: [ServiceEntryItemDraft] = []
    var initialOdometer = ""
    var initialDate = Date()
    var initialNote = ""
    var initialMode: ServiceEntryMode = .service
    var initialTireSetId: UUID?

    var odometerValue: Int? {
        let trimmed = odometer.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Int(OdometerFormat.ungrouped(trimmed))
    }

    /// The header total: the sum of the items' exact costs (hard rule 2 -
    /// derived, never stored).
    var totalDecimal: Decimal {
        items.reduce(Decimal.zero) { $0 + ($1.costDecimal ?? Decimal.zero) }
    }

    /// At least one item carries a title - the baseline save gate. A lump sum
    /// (one titled item) satisfies it; nothing forces a second item (J7).
    var hasTitledItem: Bool {
        items.contains(where: \.hasTitle)
    }

    /// Odometer is required when any item sets a km lifetime, or a tire set is
    /// mounted (P3.3) - both anchor on it (docs/SCHEMA.md). Delegates to the
    /// core rule so the save gate, the warning and the L1 test can never
    /// disagree.
    var requiresOdometer: Bool {
        ServiceEntryDraft.requiresOdometer(
            items: items.map { item in
                ServiceItem.make(title: item.title, category: item.category,
                                 lifetime: item.lifetime)
            },
            tireSetId: tireSetId)
    }

    /// The parsed, save-ready shape. This is the conversion the L1 tests drive
    /// too, so a typed or scanned record and a unit test go through the same
    /// build.
    func draft(vehicle: Vehicle) -> ServiceEntryDraft {
        ServiceEntryDraft(
            vendor: vendor,
            items: items.map { item in
                ServiceItem.make(
                    title: item.title,
                    category: item.category,
                    cost: item.costDecimal.map {
                        Money(amount: $0, currency: vehicle.homeCurrency,
                              homeCurrency: vehicle.homeCurrency)
                    },
                    lifetime: item.lifetime)
            },
            date: date,
            odometer: odometerValue,
            note: note,
            tireSetId: tireSetId,
            attachments: attachments,
            provenance: provenance,
            usedParts: linkedPartIds)
    }

    // MARK: Discard guard

    /// Real edits only: a typed vendor/note, an item added or changed, an
    /// odometer moved from its pre-fill, a date moved. Opening the sheet and
    /// closing it with just the convenience pre-fills discards silently.
    func hasEdits() -> Bool {
        if vendor != initialVendor { return true }
        if note != initialNote { return true }
        if items != initialItems { return true }
        // Linking a part is a real edit (the link is committed on save).
        if !linkedPartIds.isEmpty { return true }
        if mode != initialMode { return true }
        if tireSetId != initialTireSetId { return true }
        if OdometerFormat.ungrouped(odometer) != OdometerFormat.ungrouped(initialOdometer) {
            return true
        }
        if !Calendar.current.isDate(date, inSameDayAs: initialDate) { return true }
        return false
    }
}

// MARK: - F9a timeline support (PJ.11)

extension ServiceEntryFormState {
    /// The odometer-conflict quote for the F9a warn on the odometer card
    /// (docs/JOURNEYS.md F9a, docs/ERRORS.md -> Service & expenses). Runs the
    /// candidate `ServiceRecord` through `TimelineValidator` against the
    /// vehicle's existing timeline, exactly as the save path will. The quote
    /// names the conflicting entry when the order check has a previous
    /// neighbour to quote; a pace-only flag has no quote.
    func odometerConflict(vehicle: Vehicle, existingEntries: [any Entry],
                          distanceUnit: DistanceUnit) -> OdometerConflict? {
        guard let odo = odometerValue else { return nil }
        let candidate = candidate(vehicle: vehicle)
        let validations = TimelineValidator.validate(entries: existingEntries + [candidate],
                                                     vehicle: vehicle)
        guard let validation = validations.first(where: { $0.entryID == candidate.id }),
              let flag = validation.flags.first else { return nil }
        switch flag.detail {
        case .order(let previousOdometer, let previousDate, _, _):
            if let previousOdometer, let previousDate, odo <= previousOdometer {
                let day = previousDate.formatted(.dateTime.month(.abbreviated).day())
                let quote = String(format: L10n.localize("%@ already recorded %@ km."),
                                   day, OdometerFormat.grouped(previousOdometer))
                return OdometerConflict(quote: quote, flagKind: flag.kind)
            }
            return OdometerConflict(quote: nil, flagKind: flag.kind)
        case .pace:
            return OdometerConflict(quote: nil, flagKind: flag.kind)
        }
    }

    /// A best-effort candidate `ServiceRecord` used ONLY to run the timeline
    /// check; the entry actually saved is built by the save path. Only
    /// odometer, date and vehicleId influence the check, so the items can be
    /// empty.
    func candidate(vehicle: Vehicle) -> ServiceRecord {
        let now = Date()
        return ServiceRecord(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: date, odometer: odometerValue,
            money: nil, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil, vendor: nil, items: [],
            usedParts: [], tireSetId: tireSetId, proposedReminderId: nil)
    }
}

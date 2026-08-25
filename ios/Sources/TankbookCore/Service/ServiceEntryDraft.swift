import Foundation

/// Construction seam for `ServiceItem` from outside the package. The
/// synthesized memberwise init is internal on a public struct - the same
/// blocker that gave `Vehicle`, `FillUp` and the other entries public
/// initializers - so the ServiceEntry screen builds a line item through this
/// factory instead of a hand-rolled record. The entity's shape is unchanged.
public extension ServiceItem {
    static func make(title: String, category: ServiceCategory,
                     cost: Money? = nil, lifetime: ServiceItem.Lifetime? = nil) -> ServiceItem {
        ServiceItem(title: title, category: category, cost: cost,
                    partNumber: nil, lifetime: lifetime)
    }
}

/// The parsed, save-ready shape of the ServiceEntry form (docs/JOURNEYS.md J7,
/// docs/SCHEMA.md -> ServiceRecord). The typed screen holds raw text; this value
/// type is the decision layer between those strings and the persisted
/// `ServiceRecord`, and every rule here tests without a simulator
/// (docs/TESTING.md, L1).
///
/// The one invariant the whole task exists for: the odometer is REQUIRED only
/// when something on the record anchors on it - a line item that sets a km
/// lifetime, or a mounted tire set. A record with neither saves with a blank
/// odometer, and no UI pressure exists to add one (docs/SCHEMA.md:
/// "odometer ... is REQUIRED whenever any item carries a km lifetime or the
/// record mounts a tire set").
public struct ServiceEntryDraft: Equatable, Sendable {
    public var vendor: String?
    public var items: [ServiceItem]
    public var date: Date
    public var odometer: Int?
    public var note: String?
    /// The tire set mounted by this record (P3.3). Nil in P3.1a; the rule
    /// already honours it so the odometer requirement cannot silently change
    /// when tire sets land.
    public var tireSetId: UUID?

    public init(vendor: String? = nil, items: [ServiceItem], date: Date,
                odometer: Int? = nil, note: String? = nil, tireSetId: UUID? = nil) {
        self.vendor = vendor
        self.items = items
        self.date = date
        self.odometer = odometer
        self.note = note
        self.tireSetId = tireSetId
    }

    /// Whether the form can save, as a decision the view and its tests share.
    public enum SaveReadiness: Equatable, Sendable {
        case ready
        /// A line item carries a km lifetime (or a tire set is mounted) and the
        /// odometer is blank: refuse to save and name the next step.
        case odometerRequired
    }

    /// The odometer rule, both directions: false when nothing anchors on the
    /// odometer (a blank odometer saves), true when an item's km lifetime or a
    /// mounted tire set does.
    public static func requiresOdometer(items: [ServiceItem], tireSetId: UUID?) -> Bool {
        tireSetId != nil || items.contains { $0.lifetime?.km != nil }
    }

    public var requiresOdometer: Bool {
        Self.requiresOdometer(items: items, tireSetId: tireSetId)
    }

    public var readiness: SaveReadiness {
        guard odometer == nil else { return .ready }
        return requiresOdometer ? .odometerRequired : .ready
    }

    /// The header total: the sum of the items' original amounts (hard rule 2 -
    /// derived, never stored). An item without a cost contributes zero, so a
    /// blank-cost row does not break the total.
    public var total: Decimal {
        items.reduce(Decimal.zero) { partial, item in
            partial + (item.cost?.amount ?? Decimal.zero)
        }
    }

    /// A lump sum - exactly one item carrying the whole total - is a first-class
    /// record, never pushed toward itemization (docs/JOURNEYS.md J7). Nothing in
    /// the save path distinguishes it from a multi-item record.
    public var isLumpSum: Bool { items.count == 1 }

    /// Builds the `ServiceRecord` the repository persists. This is THE save
    /// path: the view calls it, and the L1 tests drive it so they exercise the
    /// same conversion a typed or scanned form produces - never a hand-rolled
    /// record. `money` is the item-sum total; a record whose items carry no cost
    /// (a free inspection) saves with no money rather than a fabricated zero.
    public func build(vehicleId: UUID, homeCurrency: CurrencyCode,
                      now: Date = Date()) -> ServiceRecord {
        let money = total > Decimal.zero
            ? Money(amount: total, currency: homeCurrency, homeCurrency: homeCurrency)
            : nil
        return ServiceRecord(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicleId, date: date, odometer: odometer,
            money: money, note: note?.isEmpty == false ? note : nil,
            attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: vendor?.isEmpty == false ? vendor : nil,
            items: items, usedParts: [], tireSetId: tireSetId,
            proposedReminderId: nil)
    }
}

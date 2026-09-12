import Foundation

// MARK: - RV.201 a late recognition, generalised over the entry KIND it is about
//
// Before this row the inbox spoke one vocabulary: `GatewayExtraction`, the fuel
// reading. A service invoice and a shop receipt were recognised on the device
// and handed straight to their form, so they could never arrive late and the
// per-field ask had nothing to offer them. This file is the ONE place the
// reading is generalised: a recognition is fuel, service or expense, and the
// entry it is about is whichever of those three the user saved.
//
// The gateway wire still carries only the fuel shape (docs/API.md -> `/extract`);
// a service or expense reading is device-local until the cloud half (PJ.29)
// carries it through the delivery outbox. Making the producing side deferrable
// is the second half of RV.201 and is filed separately - the seam it plugs into
// is `GatewayInboxPolicy.item(recognition:entry:)` below, the SAME entry point
// the in-process and outbox paths already share.

/// A late reading, tagged by the kind of entry it is about. The three cases are
/// deliberately not interchangeable: a fuel extraction on a service entry is a
/// programming error, and the policy refuses the pair rather than guessing.
public enum InboxRecognition: Sendable, Equatable, Codable {
    /// A fuel receipt or pump display - the shape `POST /extract` returns.
    case fuel(GatewayExtraction)
    /// A service invoice: a vendor, its line items and its total.
    case service(ServiceRecognition)
    /// A shop receipt: an amount and the category it was read as (RV.200).
    case expense(ExpenseRecognition)
}

/// A service invoice read on the device. The fields are the ones the entry
/// carries: `vendor`, the invoice's line items, `money` (total + currency) and
/// `date`. Every value is optional - the parser is a suggestion engine and an
/// unread field is absent, never guessed (hard rule 13).
///
/// `date` is the parsed `Date` the splitter already produced, unlike the fuel
/// recognition's raw `String` (`InvoiceSplitter` parses it once; re-encoding it
/// to a string the scanner never had would only decode it again in the merge).
public struct ServiceRecognition: Sendable, Equatable, Codable {
    public var vendor: GatewayFieldValue<String>?
    public var total: GatewayFieldValue<Decimal>?
    public var currency: GatewayFieldValue<CurrencyCode>?
    public var date: GatewayFieldValue<Date>?
    public var lineItems: [LineItem]

    public init(vendor: GatewayFieldValue<String>? = nil,
                total: GatewayFieldValue<Decimal>? = nil,
                currency: GatewayFieldValue<CurrencyCode>? = nil,
                date: GatewayFieldValue<Date>? = nil,
                lineItems: [LineItem] = []) {
        self.vendor = vendor
        self.total = total
        self.currency = currency
        self.date = date
        self.lineItems = lineItems
    }

    /// One invoice line the splitter resolved. `category` rides along because
    /// `ServiceItem.category` is non-optional, so taking a line item has to
    /// bring one.
    public struct LineItem: Sendable, Equatable, Codable {
        public var title: String
        public var category: ServiceCategory
        /// The line's own money pair, so taking the line brings its currency
        /// rather than guessing one from the record's header.
        public var cost: Money?

        public init(title: String, category: ServiceCategory, cost: Money? = nil) {
            self.title = title
            self.category = category
            self.cost = cost
        }
    }
}

/// A shop receipt read on the device. Per RV.200 the recognition produces the
/// amount and the category it was read as; RV.201 offered exactly those two -
/// a shop receipt has no vendor the schema records and no fuel fields at all.
///
/// `date` is the receipt's printed date, the parsed `Date` the pre-fill already
/// resolves (`ExpensePrefill.date`), so a late read can offer a differing date
/// against the entry the user saved - one shape with the service recognition.
/// It is optional: an unread date is absent, never guessed (hard rule 13).
public struct ExpenseRecognition: Sendable, Equatable, Codable {
    public var total: GatewayFieldValue<Decimal>?
    public var category: GatewayFieldValue<ExpenseCategory>?
    public var date: GatewayFieldValue<Date>?

    public init(total: GatewayFieldValue<Decimal>? = nil,
                category: GatewayFieldValue<ExpenseCategory>? = nil,
                date: GatewayFieldValue<Date>? = nil) {
        self.total = total
        self.category = category
        self.date = date
    }
}

/// The saved entry a late recognition is about, lifted to one type so the merge
/// is ONE function over any kind (the RV.201 spine). The repository hands back
/// whichever entity the item's kind names; nothing here invents a union entity
/// or a second store.
public enum InboxEntry: Sendable, Equatable {
    case fillUp(FillUp)
    case service(ServiceRecord)
    case expense(Expense)

    /// The entry's own id - the value the item routed to, kept readable so a
    /// resolution can re-fetch the live row.
    public var id: UUID {
        switch self {
        case .fillUp(let entry): return entry.id
        case .service(let entry): return entry.id
        case .expense(let entry): return entry.id
        }
    }

    /// The entry date, the field every kind shares.
    public var date: Date {
        switch self {
        case .fillUp(let entry): return entry.date
        case .service(let entry): return entry.date
        case .expense(let entry): return entry.date
        }
    }

    /// The money pair every kind carries (nil when the entry recorded none).
    public var money: Money? {
        switch self {
        case .fillUp(let entry): return entry.money
        case .service(let entry): return entry.money
        case .expense(let entry): return entry.money
        }
    }
}

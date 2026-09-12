import Foundation

// MARK: - RV.38 the inbox for work that finishes after the user moved on
// (docs/JOURNEYS.md F4, amended 2026-09-03); RV.45 the per-field ask
// (amended 2026-09-04); RV.201 the merge generalised over entry KIND
// (amended 2026-09-11).
//
// F4 used to say "once the entry is saved, nothing arrives at all" and
// `GatewayScanSession.markSaved()` dropped the answer. RV.38 reverses that -
// but only because the app ASKS. A late answer no longer silently rewrites a
// saved entry (hard rule 13 still forbids that); it lands in the inbox as a
// suggestion the user accepts, edits or declines, with "leave it as it is" the
// default. The decision - what makes an item, when it clears, and what a taken
// answer changes - lives here in core so the sheet and the tests cannot
// disagree about the boundary, exactly like `GatewaySuggestionPolicy`.
//
// RV.45 (2026-09-04) replaced the blank-fields-only merge with a PER-FIELD one.
// The old `fillableFields` could only ever return `.unitPrice` (on a saved
// `FillUp` the other fields are non-nil by construction), while `shouldOffer`
// also fired on `hasDifference` - so the commonest item was a DISAGREEMENT for
// which the old `merged()` changed nothing, and the card offered an "update"
// that was a guaranteed no-op. The disagreement is the most valuable thing the
// scan produced; it is now shown, and the user ticks per field what to take.
//
// RV.201 (2026-09-11) generalised all of it over the entry KIND. Before this
// row every function took `entry: FillUp` and every offered field was a fill-up
// field, so a service invoice and a shop receipt had nowhere to arrive late to.
// The merge is now ONE function over `InboxEntry` (fill-up, service, expense);
// the fuel-shaped overloads below are thin delegations, never a second
// implementation. The blank-fields-only rule [PJ.48] owns on the ATTACH path
// stays there; this file owns the LATE-ANSWER rule, and both keep the same
// per-field disposition (fill a blank, or OFFER a differing value and never
// apply it without a tick).

/// One pending inbox item: a recognition that arrived after the entry was
/// saved. The reading lives on the device (rule 9 - the gateway holds no
/// conversation); an answer the device never received is queued server-side in
/// the delivery outbox and drained into an item of this same shape (RV.44). An
/// answer that DID arrive is persisted (Codable) and cleared by resolution,
/// never silently.
public struct GatewayInboxItem: Codable, Sendable, Equatable, Identifiable {
    /// The item's own id.
    public var id: UUID
    /// The saved entry the reading is about. The inbox routes to this entry
    /// (hard rule 8: the bell is a second route, never the only one).
    public var entryId: UUID
    /// When the answer arrived.
    public var createdAt: Date
    /// The reading, tagged by the kind of entry it is about (RV.201).
    public var recognition: InboxRecognition

    public init(id: UUID, entryId: UUID, createdAt: Date, recognition: InboxRecognition) {
        self.id = id
        self.entryId = entryId
        self.createdAt = createdAt
        self.recognition = recognition
    }

    /// The fuel-shaped convenience every pre-RV.201 caller used. Delegates to
    /// the general initializer so there is one stored shape, not two.
    public init(id: UUID, entryId: UUID, createdAt: Date, extraction: GatewayExtraction) {
        self.init(id: id, entryId: entryId, createdAt: createdAt, recognition: .fuel(extraction))
    }

    private enum CodingKeys: String, CodingKey {
        case id, entryId, createdAt, recognition
        /// The pre-RV.201 persisted shape, read for backward compatibility.
        case extraction
    }

    /// Reads an item written before the generalization (`extraction`) as a
    /// fuel recognition. Device-local persistence must not drop a pending item
    /// because its JSON predates a shape change.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.entryId = try container.decode(UUID.self, forKey: .entryId)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        if let recognition = try container.decodeIfPresent(InboxRecognition.self, forKey: .recognition) {
            self.recognition = recognition
        } else {
            self.recognition = .fuel(try container.decode(GatewayExtraction.self, forKey: .extraction))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(entryId, forKey: .entryId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(recognition, forKey: .recognition)
    }
}

/// The single place the inbox's decision lives, so the inbox view, the gateway
/// session and the tests cannot disagree about the boundary (the
/// `GatewaySuggestionPolicy` precedent).
public enum GatewayInboxPolicy {

    /// The two ways a field the receipt read can be a decision. They must read
    /// differently to the user (RV.45 honesty rule 3): filling a blank is not
    /// replacing a value the user typed, and the copy must not flatten them.
    public enum Disposition: Equatable, Sendable {
        /// The entry's field is blank; taking the receipt's value fills it.
        case fillsBlank
        /// The entry holds a value and the receipt disagrees; taking it replaces
        /// what the user saved - the act hard rule 13 leaves to the user alone.
        case differs
    }

    /// One row of the comparison table: a field the receipt read that is a
    /// decision for the user. A field that merely agrees is ABSENT (agreement is
    /// not a choice); a field the receipt did not read is absent too.
    public struct FieldOffer: Equatable, Sendable, Identifiable {
        public let field: FieldRef
        public let disposition: Disposition

        public init(field: FieldRef, disposition: Disposition) {
            self.field = field
            self.disposition = disposition
        }

        public var id: FieldRef { field }
    }

    // MARK: - The general shape (RV.201)

    /// Whether a late recognition is worth an inbox item: at least one field it
    /// read would change something (fill a blank or replace a value). An answer
    /// that merely agrees with the saved entry is noise, not work. A recognition
    /// whose kind does not match the entry's kind is refused, never guessed.
    public static func shouldOffer(recognition: InboxRecognition, entry: InboxEntry) -> Bool {
        !offers(recognition: recognition, entry: entry).isEmpty
    }

    /// The one way a recognition becomes an inbox item (RV.44/RV.201): a fresh
    /// item for the entry the answer is about, or nil when the answer is not
    /// worth an item. Both the in-process late answer and the delivery-outbox
    /// drain feed through this single function, so the two paths cannot disagree
    /// about the boundary - one policy, not two.
    public static func item(recognition: InboxRecognition,
                            entry: InboxEntry,
                            now: Date = Date()) -> GatewayInboxItem? {
        guard shouldOffer(recognition: recognition, entry: entry) else { return nil }
        return GatewayInboxItem(id: UUID.v7(), entryId: entry.id, createdAt: now, recognition: recognition)
    }

    /// Every field the recognition read that would change the entry if taken: a
    /// blank it can fill, or a value it reads differently. A field that agrees is
    /// not offered (agreement is not a decision), and a field the recognition
    /// did not read is not offered either.
    public static func offers(recognition: InboxRecognition, entry: InboxEntry) -> [FieldOffer] {
        switch (recognition, entry) {
        case (.fuel(let extraction), .fillUp(let fillUp)):
            return fuelOffers(extraction, fillUp)
        case (.service(let service), .service(let record)):
            return serviceOffers(service, record)
        case (.expense(let expense), .expense(let record)):
            return expenseOffers(expense, record)
        default:
            return []
        }
    }

    /// The per-field merge (RV.201, ONE function over any entry kind): a copy of
    /// the entry with exactly the TICKED fields taken from the recognition,
    /// every other field byte-identical. `taking` is the user's tick set (the
    /// refs of the offered fields they chose). A ref not in the set never
    /// changes; a ref the recognition did not read (or that agrees) is a no-op
    /// even if ticked. When nothing is actually applied the entry is returned
    /// unchanged - byte-identical, no `updatedAt` bump.
    public static func merged(entry: InboxEntry,
                              recognition: InboxRecognition,
                              taking fields: Set<FieldRef>) -> InboxEntry {
        switch (recognition, entry) {
        case (.fuel(let extraction), .fillUp(let fillUp)):
            return .fillUp(mergedFuel(fillUp, extraction, taking: fields))
        case (.service(let service), .service(let record)):
            return .service(mergedService(record, service, taking: fields))
        case (.expense(let expense), .expense(let record)):
            return .expense(mergedExpense(record, expense, taking: fields))
        default:
            return entry
        }
    }

    // MARK: - Fuel-shaped convenience (delegates to the general shape)

    /// The fuel overload every pre-RV.201 call site used. Delegates to the
    /// general `shouldOffer` - one implementation, not a second.
    public static func shouldOffer(extraction: GatewayExtraction, entry: FillUp) -> Bool {
        shouldOffer(recognition: .fuel(extraction), entry: .fillUp(entry))
    }

    /// The fuel overload every pre-RV.201 call site used.
    public static func item(extraction: GatewayExtraction,
                            entry: FillUp,
                            now: Date = Date()) -> GatewayInboxItem? {
        item(recognition: .fuel(extraction), entry: .fillUp(entry), now: now)
    }

    /// The fuel overload every pre-RV.201 call site used.
    public static func offers(extraction: GatewayExtraction, entry: FillUp) -> [FieldOffer] {
        offers(recognition: .fuel(extraction), entry: .fillUp(entry))
    }

    /// The fuel overload every pre-RV.201 call site used.
    public static func merged(entry: FillUp,
                              extraction: GatewayExtraction,
                              taking fields: Set<FieldRef>) -> FillUp {
        guard case .fillUp(let merged) = merged(entry: .fillUp(entry),
                                                recognition: .fuel(extraction),
                                                taking: fields) else { return entry }
        return merged
    }

    // MARK: - The per-kind offers

    /// Fuel: date, fuel kind, volume, unit price, total and currency. Total and
    /// currency live on the money pair; a saved fill-up whose money is nil
    /// carries neither, so there is nothing to compare or take.
    private static func fuelOffers(_ extraction: GatewayExtraction, _ entry: FillUp) -> [FieldOffer] {
        var out: [FieldOffer] = []
        if let offer = dateOffer(current: entry.date, read: extraction.date?.value) { out.append(offer) }
        if let offer = offer(.fuelKind, current: entry.fuelKind, read: extraction.fuelKind?.value) { out.append(offer) }
        if let offer = offer(.volume, current: entry.volumeL, read: extraction.volume?.value) { out.append(offer) }
        if let offer = offer(.unitPrice, current: entry.unitPrice, read: extraction.unitPrice?.value) { out.append(offer) }
        if let money = entry.money {
            if let offer = offer(.total, current: money.amount, read: extraction.total?.value) { out.append(offer) }
            if let offer = offer(.currency, current: money.currency, read: extraction.currency?.value) { out.append(offer) }
        }
        return out
    }

    /// Service: the vendor, the invoice's line items (by position) and the
    /// header's total/currency/date. A line the record does not yet hold is a
    /// blank to fill; a line whose title, category or cost differs is a
    /// disagreement to offer.
    private static func serviceOffers(_ recognition: ServiceRecognition, _ entry: ServiceRecord) -> [FieldOffer] {
        var out: [FieldOffer] = []
        if let offer = dateOffer(current: entry.date, read: recognition.date?.value) { out.append(offer) }
        if let offer = offer(.vendor, current: blankToNil(entry.vendor), read: recognition.vendor?.value) {
            out.append(offer)
        }
        for (index, line) in recognition.lineItems.enumerated() {
            if index < entry.items.count {
                let current = entry.items[index]
                if current.title != line.title || current.category != line.category || current.cost != line.cost {
                    out.append(FieldOffer(field: .lineItem(index), disposition: .differs))
                }
            } else {
                out.append(FieldOffer(field: .lineItem(index), disposition: .fillsBlank))
            }
        }
        if let money = entry.money {
            if let offer = offer(.total, current: money.amount, read: recognition.total?.value) { out.append(offer) }
            if let offer = offer(.currency, current: money.currency, read: recognition.currency?.value) { out.append(offer) }
        }
        return out
    }

    /// Expense: the amount, the category it was read as (RV.200's field set) and
    /// the receipt's printed date. `Expense.category` is non-optional, so a
    /// differing category is always a replacement, never a fill; `Expense.date`
    /// is non-optional too, so a differing date is offered the same way.
    private static func expenseOffers(_ recognition: ExpenseRecognition, _ entry: Expense) -> [FieldOffer] {
        var out: [FieldOffer] = []
        if let offer = dateOffer(current: entry.date, read: recognition.date?.value) { out.append(offer) }
        if let money = entry.money,
           let offer = offer(.total, current: money.amount, read: recognition.total?.value) {
            out.append(offer)
        }
        if let offer = offer(.category, current: entry.category, read: recognition.category?.value) {
            out.append(offer)
        }
        return out
    }

    // MARK: - The per-kind merges

    /// The fuel merge: taking a field replaces exactly that field; the
    /// cross-check is recomputed after a change leaves the pump-card numbers
    /// present (hard rule 2: derived, never stored stale).
    private static func mergedFuel(_ entry: FillUp,
                                   _ extraction: GatewayExtraction,
                                   taking fields: Set<FieldRef>) -> FillUp {
        var result = entry
        var changed = false

        if fields.contains(.date), let rawDate = extraction.date?.value, let parsed = ConfirmDate.parse(rawDate) {
            result.date = parsed
            changed = true
        }
        if fields.contains(.fuelKind), let kind = extraction.fuelKind?.value {
            result.fuelKind = kind
            changed = true
        }
        if fields.contains(.volume), let volume = extraction.volume?.value {
            result.volumeL = volume
            changed = true
        }
        if fields.contains(.unitPrice), let price = extraction.unitPrice?.value {
            result.unitPrice = price
            changed = true
        }
        if fields.contains(.total), let total = extraction.total?.value, let money = result.money {
            result.money = money.replacingAmount(total)
            changed = true
        }
        if fields.contains(.currency), let currency = extraction.currency?.value, let money = result.money {
            result.money = money.replacingCurrency(currency)
            changed = true
        }

        guard changed else { return entry }

        if let money = result.money {
            result.crossCheck = TimelineValidator.crossCheck(
                volumeL: result.volumeL, unitPrice: result.unitPrice, amount: money.amount)
        }
        result.updatedAt = Date()
        return result
    }

    /// The service merge. A taken line item keeps the fields the recognition
    /// does not carry (`partNumber`, `lifetime`) on an existing row, so a merge
    /// can never silently drop a user's own detail (hard rule 8).
    private static func mergedService(_ entry: ServiceRecord,
                                      _ recognition: ServiceRecognition,
                                      taking fields: Set<FieldRef>) -> ServiceRecord {
        var result = entry
        var changed = false

        if fields.contains(.date), let parsed = recognition.date?.value {
            result.date = parsed
            changed = true
        }
        if fields.contains(.vendor), let vendor = recognition.vendor?.value {
            result.vendor = vendor
            changed = true
        }
        for (index, line) in recognition.lineItems.enumerated() where fields.contains(.lineItem(index)) {
            if index < result.items.count {
                var item = result.items[index]
                item.title = line.title
                item.category = line.category
                item.cost = line.cost
                result.items[index] = item
            } else {
                result.items.append(ServiceItem(title: line.title, category: line.category, cost: line.cost))
            }
            changed = true
        }
        if fields.contains(.total), let total = recognition.total?.value, let money = result.money {
            result.money = money.replacingAmount(total)
            changed = true
        }
        if fields.contains(.currency), let currency = recognition.currency?.value, let money = result.money {
            result.money = money.replacingCurrency(currency)
            changed = true
        }

        guard changed else { return entry }
        result.updatedAt = Date()
        return result
    }

    /// The expense merge: the amount, the category and the receipt's date.
    private static func mergedExpense(_ entry: Expense,
                                      _ recognition: ExpenseRecognition,
                                      taking fields: Set<FieldRef>) -> Expense {
        var result = entry
        var changed = false

        if fields.contains(.date), let parsed = recognition.date?.value {
            result.date = parsed
            changed = true
        }
        if fields.contains(.total), let total = recognition.total?.value, let money = result.money {
            result.money = money.replacingAmount(total)
            changed = true
        }
        if fields.contains(.category), let category = recognition.category?.value {
            result.category = category
            changed = true
        }

        guard changed else { return entry }
        result.updatedAt = Date()
        return result
    }

    // MARK: - Field-offer helpers (the blank-vs-differs rule in one place)

    /// A read against an OPTIONAL current value: a blank fills, a different
    /// value is offered, an agreeing value is not a decision at all.
    private static func offer<T: Equatable>(_ field: FieldRef, current: T?, read: T?) -> FieldOffer? {
        guard let read else { return nil }
        guard let current else { return FieldOffer(field: field, disposition: .fillsBlank) }
        return current == read ? nil : FieldOffer(field: field, disposition: .differs)
    }

    /// A read against a NON-OPTIONAL current value: only a disagreement is a
    /// decision (there is no blank to fill).
    private static func offer<T: Equatable>(_ field: FieldRef, current: T, read: T?) -> FieldOffer? {
        guard let read else { return nil }
        return current == read ? nil : FieldOffer(field: field, disposition: .differs)
    }

    /// A date read from the gateway as a raw string: parsed and compared by
    /// calendar day, so a timestamp that lands on the same day is not a decision.
    private static func dateOffer(current: Date, read: String?) -> FieldOffer? {
        guard let raw = read, let parsed = ConfirmDate.parse(raw) else { return nil }
        return dateOffer(current: current, read: parsed)
    }

    /// A date read already parsed by the device pipeline: compared by calendar
    /// day, so a timestamp that lands on the same day is not a decision.
    private static func dateOffer(current: Date, read: Date?) -> FieldOffer? {
        guard let parsed = read else { return nil }
        return Calendar.current.isDate(parsed, inSameDayAs: current) ? nil : FieldOffer(field: .date, disposition: .differs)
    }

    /// An empty or whitespace-only string is a blank, not a value (the same
    /// reading `BlankFieldsOnly` gives a money pair).
    private static func blankToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    // MARK: - RV.64 the recommended action (which button is the loud one)

    /// The two acts the comparison card offers - "leave it as it is" and
    /// "update from the receipt" - keep their ORDER but swap WEIGHT with the
    /// tick count. The card's position of the loud action is decided HERE, in
    /// one place, so the two buttons can never drift apart (RV.64).
    public enum RecommendedInboxAction: Equatable, Sendable {
        /// "Leave it as it is" carries the prominent filled treatment.
        case leaveAsIs
        /// "Update from the receipt" carries the prominent filled treatment.
        case update
    }

    /// Which of the two acts the card presents as its loud, prominent one for a
    /// given number of ticked fields. Zero ticks: the user has not decided yet,
    /// so leave-as-is is the correct default and stays loud (hard rule 13). One
    /// or more ticks: a ticked field IS the user deciding, so the update - the
    /// act that honours those ticks - takes the loud treatment and leave-as-is
    /// dims (hard rule 8: the loudest control must never discard the ticks the
    /// user took the effort to make).
    public static func recommendedAction(tickedCount: Int) -> RecommendedInboxAction {
        tickedCount == 0 ? .leaveAsIs : .update
    }
}

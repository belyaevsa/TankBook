import Foundation

// MARK: - RV.38 the inbox for work that finishes after the user moved on
// (docs/JOURNEYS.md F4, amended 2026-09-03).
//
// F4 used to say "once the entry is saved, nothing arrives at all" and
// `GatewayScanSession.markSaved()` dropped the answer. RV.38 reverses that -
// but only because the app ASKS. A late answer no longer silently rewrites a
// saved entry (hard rule 13 still forbids that); it lands in the inbox as a
// suggestion the user accepts, edits or declines, with "leave it as it is" the
// default. The decision - what makes an item, when it clears, and the
// blank-fields-only merge - lives here in core so the sheet and the tests
// cannot disagree about the boundary, exactly like `GatewaySuggestionPolicy`.

/// One pending inbox item: a gateway reading that arrived after the entry was
/// saved. The extraction lives on the device (rule 9 - the gateway holds no
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
    /// The gateway's full reading, a suggestion the user may accept or decline.
    public var extraction: GatewayExtraction

    public init(id: UUID, entryId: UUID, createdAt: Date, extraction: GatewayExtraction) {
        self.id = id
        self.entryId = entryId
        self.createdAt = createdAt
        self.extraction = extraction
    }
}

/// The single place the inbox's decision lives, so the inbox view, the gateway
/// session and the tests cannot disagree about the boundary (the
/// `GatewaySuggestionPolicy` precedent).
public enum GatewayInboxPolicy {

    /// Whether a late answer is worth an inbox item: there is a blank field it
    /// could fill, or it disagrees with what the user saved. An answer that
    /// merely agrees with the saved entry is noise, not work.
    public static func shouldOffer(extraction: GatewayExtraction, entry: FillUp) -> Bool {
        !fillableFields(extraction: extraction, entry: entry).isEmpty
            || hasDifference(extraction: extraction, entry: entry)
    }

    /// The one way an answer becomes an inbox item (RV.44): a fresh item for the
    /// entry the answer is about, or nil when the answer is not worth an item.
    /// Both the in-process late answer (`AppInbox.recordLateGatewayAnswer`) and
    /// the delivery-outbox drain feed through this single function, so the two
    /// paths cannot disagree about the boundary - one policy, not two.
    public static func item(extraction: GatewayExtraction, entry: FillUp, now: Date = Date()) -> GatewayInboxItem? {
        guard shouldOffer(extraction: extraction, entry: entry) else { return nil }
        return GatewayInboxItem(id: UUID.v7(), entryId: entry.id, createdAt: now, extraction: extraction)
    }

    /// The subset of a gateway answer that may fill a SAVED entry: fields the
    /// answer provides that are still BLANK on the entry. A user-typed (or
    /// derived-then-saved) value is theirs permanently - an accepted re-read
    /// never overwrites one (hard rule 13). For a `FillUp` the only gateway
    /// field that can be blank in practice is `unitPrice` (nil); `volumeL`,
    /// `date`, `fuelKind` and `money` are non-nil on a saved fill-up, and
    /// `money == nil` cannot be filled without inventing a currency the entry
    /// does not carry, so it is deliberately not offered.
    public static func fillableFields(extraction: GatewayExtraction, entry: FillUp) -> Set<FieldRef> {
        var out = Set<FieldRef>()
        if extraction.unitPrice != nil && entry.unitPrice == nil {
            out.insert(.unitPrice)
        }
        return out
    }

    /// The blank-fields-only merge: a copy of the entry with the fillable fields
    /// filled from the answer, everything else byte-identical. The cross-check
    /// is recomputed when the fill leaves all three pump-card numbers present;
    /// a partial fill keeps `.notApplicable` (there is no redundancy to check).
    public static func merged(entry: FillUp, extraction: GatewayExtraction) -> FillUp {
        var result = entry
        let fillable = fillableFields(extraction: extraction, entry: entry)
        if fillable.contains(.unitPrice), let price = extraction.unitPrice?.value {
            result.unitPrice = price
        }
        if let money = result.money {
            result.crossCheck = TimelineValidator.crossCheck(
                volumeL: result.volumeL, unitPrice: result.unitPrice, amount: money.amount)
        }
        result.updatedAt = Date()
        return result
    }

    /// Whether the answer disagrees with a value the user saved - the "find a
    /// difference" half of the ask. Values only, never confidence (the corpus
    /// proved a wrong digit at confidence 1.00, docs/EXTRACTION.md -> pump-004).
    public static func hasDifference(extraction: GatewayExtraction, entry: FillUp) -> Bool {
        if let total = extraction.total?.value, let money = entry.money, total != money.amount {
            return true
        }
        if let volume = extraction.volume?.value, volume != entry.volumeL {
            return true
        }
        if let price = extraction.unitPrice?.value, let current = entry.unitPrice, price != current {
            return true
        }
        if let kind = extraction.fuelKind?.value, kind != entry.fuelKind {
            return true
        }
        if let currency = extraction.currency?.value, let money = entry.money, currency != money.currency {
            return true
        }
        if let rawDate = extraction.date?.value, let date = ConfirmDate.parse(rawDate) {
            if !Calendar.current.isDate(date, inSameDayAs: entry.date) {
                return true
            }
        }
        return false
    }
}

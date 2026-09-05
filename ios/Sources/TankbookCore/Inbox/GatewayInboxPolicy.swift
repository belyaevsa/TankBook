import Foundation

// MARK: - RV.38 the inbox for work that finishes after the user moved on
// (docs/JOURNEYS.md F4, amended 2026-09-03); RV.45 the per-field ask
// (amended 2026-09-04).
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

    /// Whether a late answer is worth an inbox item: at least one field the
    /// receipt read would change something (fill a blank or replace a value). An
    /// answer that merely agrees with the saved entry is noise, not work.
    public static func shouldOffer(extraction: GatewayExtraction, entry: FillUp) -> Bool {
        !offers(extraction: extraction, entry: entry).isEmpty
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

    /// Every field the receipt read that would change the entry if taken: a
    /// blank it can fill, or a value it reads differently. In display order
    /// (date, fuel kind, volume, unit price, total, currency). A field that
    /// agrees is not offered (agreement is not a decision), and a field the
    /// receipt did not read (or a date it could not parse) is not offered either.
    public static func offers(extraction: GatewayExtraction, entry: FillUp) -> [FieldOffer] {
        var out: [FieldOffer] = []

        if let rawDate = extraction.date?.value,
           let parsed = ConfirmDate.parse(rawDate),
           !Calendar.current.isDate(parsed, inSameDayAs: entry.date) {
            out.append(FieldOffer(field: .date, disposition: .differs))
        }

        if let kind = extraction.fuelKind?.value, kind != entry.fuelKind {
            out.append(FieldOffer(field: .fuelKind, disposition: .differs))
        }

        if let volume = extraction.volume?.value, volume != entry.volumeL {
            out.append(FieldOffer(field: .volume, disposition: .differs))
        }

        if let price = extraction.unitPrice?.value {
            if let current = entry.unitPrice {
                if price != current {
                    out.append(FieldOffer(field: .unitPrice, disposition: .differs))
                }
            } else {
                out.append(FieldOffer(field: .unitPrice, disposition: .fillsBlank))
            }
        }

        // total and currency live on the money pair; a saved fill-up whose money
        // is nil carries neither, so there is nothing to compare or take.
        if let money = entry.money {
            if let total = extraction.total?.value, total != money.amount {
                out.append(FieldOffer(field: .total, disposition: .differs))
            }
            if let currency = extraction.currency?.value, currency != money.currency {
                out.append(FieldOffer(field: .currency, disposition: .differs))
            }
        }

        return out
    }

    /// The per-field merge: a copy of the entry with exactly the TICKED fields
    /// taken from the receipt, every other field byte-identical. `taking` is the
    /// user's tick set (the refs of the offered fields they chose). A ref not in
    /// the set never changes; a ref the receipt did not read (or that agrees) is
    /// a no-op even if ticked. When nothing is actually applied the entry is
    /// returned unchanged - byte-identical, no `updatedAt` bump. The cross-check
    /// is recomputed after a change leaves the pump-card numbers present (hard
    /// rule 2: derived, never stored stale).
    ///
    /// ONE function serves both the in-process late answer and the outbox drain
    /// (RV.44): both resolve through `AppInbox.resolve`, which passes the same
    /// tick set here - one policy, not two.
    public static func merged(entry: FillUp, extraction: GatewayExtraction, taking fields: Set<FieldRef>) -> FillUp {
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

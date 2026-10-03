import Foundation

public extension ServiceRecord {
    /// The record with every line's cost in the record's own currency and at
    /// its rate (docs/SCHEMA.md -> ServiceRecord): an invoice has one currency,
    /// the record's `money` carries it, and a line keeps only its amount. Every
    /// write and every read of a service record passes through this, so a
    /// currency change, a rate backfill or a re-home of the total reaches its
    /// lines. A record with no total leaves its lines as they are - there is no
    /// currency to give them.
    func withItemsInRecordCurrency() -> ServiceRecord {
        guard let total = money else { return self }
        var copy = self
        copy.items = items.map { item in
            guard let cost = item.cost else { return item }
            var line = item
            line.cost = total.sharingSnapshot(amount: cost.amount)
            return line
        }
        return copy
    }
}

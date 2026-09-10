import Foundation

/// An invoice line item (docs/SCHEMA.md, ServiceItem). Carried in its own file
/// so `Entities.swift` stays under the lint ceiling.
public struct ServiceItem: Codable, Sendable, Equatable {
    public var title: String
    public var category: ServiceCategory
    public var cost: Money?
    public var partNumber: String?
    public var lifetime: Lifetime?

    /// Memberwise initializer, public so the app target can build a
    /// `ServiceRecord`'s line items for UI tests and seeds (the same
    /// construction blocker `Vehicle` and `FillUp` had; see their notes).
    public init(title: String, category: ServiceCategory, cost: Money?,
                partNumber: String? = nil, lifetime: Lifetime? = nil) {
        self.title = title
        self.category = category
        self.cost = cost
        self.partNumber = partNumber
        self.lifetime = lifetime
    }

    /// Optional service life that drives the next-reminder suggestion.
    public struct Lifetime: Codable, Sendable, Equatable {
        public var km: Int?
        public var months: Int?

        public init(km: Int?, months: Int?) {
            self.km = km
            self.months = months
        }
    }
}

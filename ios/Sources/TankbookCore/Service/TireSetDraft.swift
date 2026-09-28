import Foundation

/// The save-ready shape of the tire-set form (docs/SCHEMA.md -> TireSet).
/// The typed screen holds raw text; this value type is the decision layer
/// between those strings and the persisted `TireSet`, and every rule here tests
/// without a simulator (docs/TESTING.md, L1) - the same pattern as
/// `ServiceEntryDraft` and `ReminderDraft`.
///
/// A tire set with no name is not a set, so a blank name refuses to save and
/// names its next step (hard rule 7). Every tire property is optional; a
/// number the user typed that does not parse refuses too, because dropping it
/// would lose what they typed (hard rule 8).
public struct TireSetDraft: Equatable, Sendable {
    public var name: String
    public var make: String
    public var model: String
    public var size: String
    public var productionWeek: String
    /// The treadwear rating as typed.
    public var treadwear: String
    /// The new tread depth in millimetres as typed; a comma decimal is accepted.
    public var newTreadDepth: String

    public init(name: String, make: String = "", model: String = "", size: String = "",
                productionWeek: String = "", treadwear: String = "", newTreadDepth: String = "") {
        self.name = name
        self.make = make
        self.model = model
        self.size = size
        self.productionWeek = productionWeek
        self.treadwear = treadwear
        self.newTreadDepth = newTreadDepth
    }

    /// Whether the form can save, as a decision the view and its tests share.
    public enum SaveReadiness: Equatable, Sendable {
        case ready
        /// The name is blank: nothing to call the set.
        case nameMissing
        /// The treadwear is not a whole number in `TireMeasure.treadwearRange`.
        case treadwearInvalid
        /// The new tread depth is not a depth in `TireMeasure.depthRange`.
        case treadDepthInvalid
    }

    public var readiness: SaveReadiness {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .nameMissing }
        if case .invalid = TireMeasure.treadwear(treadwear) { return .treadwearInvalid }
        if case .invalid = TireMeasure.depth(newTreadDepth) { return .treadDepthInvalid }
        return .ready
    }

    /// Builds the new `TireSet` the repository persists - THE create path,
    /// shared by the form and the L1 tests. A draft that is not `.ready` still
    /// builds (callers gate save on `readiness`).
    public func build(vehicleId: UUID, now: Date = Date()) -> TireSet {
        applied(to: TireSet(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicleId, name: name, purchaseExpenseId: nil), now: now)
    }

    /// The edit path: applies the form to an existing set in place, keeping its
    /// id, creation stamp and purchase link (a rename must never overwrite
    /// `purchaseExpenseId`). A cleared field clears the property.
    public func applied(to existing: TireSet, now: Date = Date()) -> TireSet {
        var updated = existing
        updated.updatedAt = now
        updated.name = name
        updated.make = Self.text(make)
        updated.model = Self.text(model)
        updated.size = Self.text(size)
        updated.productionWeek = Self.text(productionWeek)
        updated.treadwear = TireMeasure.treadwear(treadwear).value
        updated.newTreadDepthMm = TireMeasure.depth(newTreadDepth).value
        return updated
    }

    private static func text(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Parsing the tire numbers a user types (docs/SCHEMA.md -> TireSet,
/// ServiceRecord.tireReading). Blank means "not given"; text that is not a
/// plausible value is `.invalid`, which the forms refuse rather than drop.
public enum TireMeasure {
    public enum Parsed<Value: Equatable & Sendable>: Equatable, Sendable {
        case blank
        case value(Value)
        case invalid

        public var value: Value? {
            if case .value(let value) = self { return value }
            return nil
        }
    }

    /// A tread depth in millimetres: new tires are about 8-10 mm, and nothing
    /// on a car tire is deeper than this range's top.
    public static let depthRange: ClosedRange<Double> = 0...30
    /// A UTQG treadwear grade.
    public static let treadwearRange: ClosedRange<Int> = 1...2000

    public static func depth(_ raw: String) -> Parsed<Double> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .blank }
        let normalised = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalised), value.isFinite, depthRange.contains(value) else { return .invalid }
        return .value(value)
    }

    public static func treadwear(_ raw: String) -> Parsed<Int> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .blank }
        guard let value = Int(trimmed), treadwearRange.contains(value) else { return .invalid }
        return .value(value)
    }

    /// A depth as the forms show it: "6.5", or "6,5" in a comma locale, with no
    /// trailing zeros.
    public static func depthText(_ value: Double?, locale: Locale = .current) -> String {
        guard let value else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

extension TireReading {
    /// The reading a swap form's two fields describe: nil when both are blank,
    /// `.invalid` when the typed depth does not parse (refused, never dropped).
    public static func from(depth: String, note: String) -> TireMeasure.Parsed<TireReading> {
        let parsed = TireMeasure.depth(depth)
        if parsed == .invalid { return .invalid }
        let reading = TireReading(treadDepthMm: parsed.value,
                                  note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        return reading.isEmpty ? .blank : .value(reading.normalised)
    }

    /// The stored form: a blank note is nil.
    var normalised: TireReading {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return TireReading(treadDepthMm: treadDepthMm, note: trimmed.isEmpty ? nil : trimmed)
    }
}

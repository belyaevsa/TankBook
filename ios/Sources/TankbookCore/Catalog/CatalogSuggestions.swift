import Foundation

/// A ranked suggestion produced by `CatalogSuggester`.
public struct CatalogSuggestion: Equatable, Sendable {
    public let entry: VehicleCatalogEntry
    public let score: Int

    public init(entry: VehicleCatalogEntry, score: Int) {
        self.entry = entry
        self.score = score
    }
}

/// The values a catalog suggestion copies into the Add-car form and, on save,
/// into the `Vehicle` row. Every field stays user-overridable
/// (docs/SCHEMA.md, Vehicle catalog: "the user can always override").
public struct CatalogPrefill: Equatable, Sendable {
    public var make: String
    public var model: String
    public var year: Int
    public var powertrain: Powertrain
    public var fuelKinds: [FuelKind]
    public var tankCapacityL: Double?
    public var batteryCapacityKWh: Double?

    public init(make: String, model: String, year: Int, powertrain: Powertrain,
                fuelKinds: [FuelKind], tankCapacityL: Double?, batteryCapacityKWh: Double?) {
        self.make = make
        self.model = model
        self.year = year
        self.powertrain = powertrain
        self.fuelKinds = fuelKinds
        self.tankCapacityL = tankCapacityL
        self.batteryCapacityKWh = batteryCapacityKWh
    }
}

extension VehicleCatalogEntry {
    /// Maps this entry onto form pre-fill values. The year lands on the range's
    /// end (or the current year for "to present" entries) as a starting guess;
    /// a missing `tankCapacityL` stays nil - pre-fill never guesses a number.
    public func prefill(currentYear: Int = Calendar.current.component(.year, from: Date())) -> CatalogPrefill {
        CatalogPrefill(
            make: make,
            model: model,
            year: yearsEnd ?? currentYear,
            powertrain: powertrain,
            fuelKinds: fuelKinds,
            tankCapacityL: tankCapacityL,
            batteryCapacityKWh: batteryCapacityKWh)
    }
}

/// RV.67: whether the Add-car screen keeps the live suggestion list mounted
/// under the "Make · model · year" field.
///
/// The list must be visible while the user is CHOOSING a model, never merely
/// while that field is first responder. Gating on focus made the list unmount
/// the instant a scroll gesture dismissed the keyboard
/// (`.scrollDismissesKeyboard(.immediately)` clears `@FocusState`), which is
/// exactly the gesture needed to reach the lower rows of a five-row match -
/// a suggestion that unmounts when reached for was never offered at all
/// (hard rule 13). So the gate is a pure function of two DATA inputs, never
/// of focus:
///
/// - `query` - the field's current text;
/// - `accepted` - the exact text a suggestion last wrote into the field
///   (`nil` when none has yet).
///
/// Dismissal falls out of the same two inputs: applying a suggestion makes
/// `query == accepted`; clearing the field empties `query`; editing the
/// accepted text turns it back into a query and re-offers the list. A
/// whitespace-only field counts as cleared, mirroring `CatalogSuggester`, which
/// normalizes such a query to empty.
public enum ModelSuggestionGate {
    public static func shouldShow(query: String, accepted: String?) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed != accepted?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Pure, injectable prefix/fuzzy matcher over make + model. No I/O in the hot
/// path; ranking is deterministic and stable (score descending, then a fixed
/// lexical tie-break), so identical queries always return identical results.
public struct CatalogSuggester {
    public let entries: [VehicleCatalogEntry]

    public init(entries: [VehicleCatalogEntry]) {
        self.entries = entries
    }

    public func suggestions(for rawQuery: String, limit: Int = 8) -> [CatalogSuggestion] {
        let query = Self.normalize(rawQuery)
        guard !query.isEmpty else { return [] }
        let scored = entries.compactMap { entry -> CatalogSuggestion? in
            guard let score = Self.score(entry: entry, query: query), score > 0 else { return nil }
            return CatalogSuggestion(entry: entry, score: score)
        }
        let ranked = scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return Self.tieBreaker(lhs.entry) < Self.tieBreaker(rhs.entry)
        }
        return Array(ranked.prefix(max(0, limit)))
    }

    /// A lowercase, whitespace-collapsed query key. Folding removes diacritics
    /// so "cafe" and "Café" match; case-insensitive folding keeps Cyrillic
    /// (e.g. "лада") intact.
    private static func normalize(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale.current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func score(entry: VehicleCatalogEntry, query: String) -> Int? {
        let make = normalize(entry.make)
        let model = normalize(entry.model)
        let haystack = "\(make) \(model)"

        if haystack == query { return 100 }
        if make == query { return 90 }
        if model == query { return 85 }
        if haystack.hasPrefix(query) { return 80 }
        if make.hasPrefix(query) { return 75 }
        if model.hasPrefix(query) { return 70 }
        if make.contains(query) || model.contains(query) { return 60 }

        let queryWords = query.split(separator: " ")
        if queryWords.allSatisfy({ haystack.contains($0) }) { return 40 }
        return nil
    }

    private static func tieBreaker(_ entry: VehicleCatalogEntry) -> String {
        "\(entry.make)|\(entry.model)|\(entry.yearsStart)|\(entry.generation)"
    }
}

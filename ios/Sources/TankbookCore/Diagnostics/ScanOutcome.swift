import Foundation

/// Where a pre-filled pump field came from, for the beta's scan outcome
/// (docs/CONFIG.md -> "Build channels and experiments", `scanOutcome`).
public enum ScanPrefillKind: String, Sendable, Codable {
    /// The pump law committed it: the numbers closed.
    case closed
    /// A read no currency closes, shown under the "don't multiply up" warning.
    case warned
    /// Committed with the shown-price caution.
    case cautioned
    /// Filled by the receipt parser behind the reader.
    case rules
    /// Nothing was pre-filled.
    case empty
}

/// What the user did with a pre-filled field before saving.
public enum ScanFieldAction: String, Sendable, Codable {
    case kept, edited, cleared, added, untouched
}

/// The three numbers an entry was saved with, for its scan's outcome.
public struct ScanSavedValues: Sendable {
    public var liters: Double?
    public var unitPrice: Decimal?
    public var total: Decimal?

    public init(liters: Double?, unitPrice: Decimal?, total: Decimal?) {
        self.liters = liters
        self.unitPrice = unitPrice
        self.total = total
    }
}

/// How a scanned fill-up ended, and what happened to each pre-filled field -
/// the measurement of how often a closed, warned or cautioned value was right
/// on real fills. Kept beside the scan on the device and sent only in a debug
/// case the user chooses to send, like the scan itself.
public enum ScanOutcome {
    public enum Result: String, Sendable, Codable {
        case saved, discarded, retaken
    }

    public static let fields = ["liters", "unitPrice", "total"]

    /// Each field's pre-fill kind, from what the capture path composed
    /// (`CapturePipeline.composed`): a committed reader field is closed (or
    /// cautioned), an unclosed read's field the rules arm left empty is
    /// warned, anything else the form holds came from the rules arm.
    public static func prefillKinds(reader: FuelExtraction?, rules: FuelExtraction, form: FuelExtraction,
                                    caution: PumpReadingCaution?) -> [String: ScanPrefillKind] {
        let unclosed = caution == .unclosed
        let cautioned: Bool = { if case .shownPriceDiffers? = caution { return true }; return false }()
        func kind(form value: Bool, reader fromReader: Bool, rules fromRules: Bool) -> ScanPrefillKind {
            guard value else { return .empty }
            if unclosed { return fromRules ? .rules : .warned }
            if fromReader { return cautioned ? .cautioned : .closed }
            return .rules
        }
        return [
            "liters": kind(form: form.liters != nil, reader: reader?.liters != nil, rules: rules.liters != nil),
            "unitPrice": kind(form: form.unitPrice != nil, reader: reader?.unitPrice != nil,
                              rules: rules.unitPrice != nil),
            "total": kind(form: form.total != nil, reader: reader?.total != nil, rules: rules.total != nil)
        ]
    }

    /// What the user did with one field: the pre-filled value against the
    /// saved one, equal within half a cent (or half a centilitre).
    public static func action(prefilled: Double?, saved: Double?) -> ScanFieldAction {
        switch (prefilled, saved) {
        case (nil, nil): return .untouched
        case (nil, _?): return .added
        case (_?, nil): return .cleared
        case let (before?, after?): return abs(before - after) < 0.005 ? .kept : .edited
        }
    }

    /// The `outcome.json` body. `saved` is nil when the entry was not saved.
    public static func data(result: Result, at date: Date, kinds: [String: ScanPrefillKind],
                            prefilled: FuelExtraction,
                            saved: ScanSavedValues?) -> Data {
        var body: [String: Any] = ["result": result.rawValue, "at": LogRenderer.timestamp(date)]
        var perField: [String: Any] = [:]
        let before: [String: Double?] = ["liters": prefilled.liters, "unitPrice": prefilled.unitPrice.map(double),
                                         "total": prefilled.total.map(double)]
        let after: [String: Double?] = ["liters": saved?.liters, "unitPrice": saved?.unitPrice.map(double),
                                        "total": saved?.total.map(double)]
        for field in fields {
            var entry: [String: Any] = ["prefill": (kinds[field] ?? .empty).rawValue]
            if saved != nil {
                entry["action"] = action(prefilled: before[field] ?? nil, saved: after[field] ?? nil).rawValue
            }
            perField[field] = entry
        }
        body["fields"] = perField
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    private static func double(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }
}

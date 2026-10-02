import Foundation

public struct SeasonGate: Codable, Equatable, Sendable {
    public let autumnFrom: String
    public let autumnTo: String
    public let springFrom: String
    public let springTo: String

    public init(autumnFrom: String, autumnTo: String, springFrom: String, springTo: String) {
        self.autumnFrom = autumnFrom
        self.autumnTo = autumnTo
        self.springFrom = springFrom
        self.springTo = springTo
    }
}

public struct TireLaw: Equatable, Sendable {
    public enum Kind: String, Sendable { case dated, conditional, none }
    public enum Status: String, Sendable { case verified, reviewDue, withdrawn }

    public let country: String
    public let jurisdiction: String?
    public let vehicleClass: String
    public let kind: Kind
    public let from: String?
    public let to: String?
    public let criteria: String
    public let seasonGate: SeasonGate
    public let sourceURL: URL
    public let checked: String
    public let status: Status
    public let note: String

    public init(country: String, jurisdiction: String? = nil, vehicleClass: String,
                kind: Kind, from: String? = nil, to: String? = nil, criteria: String,
                seasonGate: SeasonGate, sourceURL: URL, checked: String,
                status: Status, note: String) {
        self.country = country
        self.jurisdiction = jurisdiction
        self.vehicleClass = vehicleClass
        self.kind = kind
        self.from = from
        self.to = to
        self.criteria = criteria
        self.seasonGate = seasonGate
        self.sourceURL = sourceURL
        self.checked = checked
        self.status = status
        self.note = note
    }
}

public enum TireLawVerdict: Equatable {
    case required(from: Date, to: Date, source: URL)
    case conditional(from: Date, to: Date)
    case noDatedRule
    case unknown
}

public struct TireLawTable: Sendable {
    public static let advanceNoticeDays = 30
    public let version: Int
    public let rows: [TireLaw]

    public init(version: Int, rows: [TireLaw]) {
        self.version = version
        self.rows = rows
    }

    public static func bundled() throws -> TireLawTable {
        guard let url = Bundle.module.url(forResource: "TireLaws.seed", withExtension: "json") else {
            throw TireLawError.bundleMissing
        }
        return try decode(data: Data(contentsOf: url))
    }

    public static func decode(data: Data) throws -> TireLawTable {
        let seed = try JSONDecoder().decode(Seed.self, from: data)
        let rows = seed.rows.compactMap { row -> TireLaw? in
            guard let kind = TireLaw.Kind(rawValue: row.kind),
                  let status = TireLaw.Status(rawValue: row.status),
                  row.country.count == 2,
                  let sourceURL = URL(string: row.sourceURL),
                  ["https", "http"].contains(sourceURL.scheme?.lowercased() ?? ""),
                  ISO8601DateFormatter().date(from: "\(row.checked)T00:00:00Z") != nil,
                  kind == .none || (dayParts(row.from) != nil && dayParts(row.to) != nil) else {
                return nil
            }
            return TireLaw(country: row.country, jurisdiction: row.jurisdiction,
                           vehicleClass: row.vehicleClass, kind: kind,
                           from: row.from, to: row.to, criteria: row.criteria,
                           seasonGate: row.seasonGate, sourceURL: sourceURL,
                           checked: row.checked, status: status, note: row.note)
        }
        return TireLawTable(version: seed.version, rows: rows)
    }

    public func seasonGate(country: String) -> SeasonGate? {
        rows.first { $0.country == country.uppercased() && $0.jurisdiction == nil && $0.status == .verified }?
            .seasonGate
    }

    public func law(country: String, on date: Date, calendar: Calendar) -> TireLawVerdict {
        let matching = rows.filter { $0.country == country.uppercased() && $0.jurisdiction == nil }
        guard !matching.isEmpty else { return .unknown }
        let verified = matching.filter { $0.status == .verified }
        guard !verified.isEmpty else { return .unknown }

        let relevant = verified.compactMap { row -> (TireLaw, Date, Date)? in
            guard row.kind != .none, let from = row.from, let to = row.to,
                  let fromParts = Self.dayParts(from), let toParts = Self.dayParts(to),
                  let year = calendar.dateComponents([.year], from: date).year else { return nil }
            for startYear in (year - 1)...(year + 1) {
                let endYear = startYear + (toParts < fromParts ? 1 : 0)
                guard let start = calendar.date(from: DateComponents(year: startYear,
                                                                     month: fromParts.month,
                                                                     day: fromParts.day)),
                      let endMonth = calendar.date(from: DateComponents(year: endYear,
                                                                        month: toParts.month,
                                                                        day: 1)),
                      let daysInEndMonth = calendar.range(of: .day, in: .month, for: endMonth),
                      let end = calendar.date(from: DateComponents(
                        year: endYear, month: toParts.month,
                        day: min(toParts.day, daysInEndMonth.count))),
                      let endExclusive = calendar.date(byAdding: .day, value: 1, to: end),
                      let noticeStart = calendar.date(byAdding: .day,
                                                     value: -Self.advanceNoticeDays, to: start)
                else { continue }
                if date >= noticeStart && date < endExclusive { return (row, start, end) }
            }
            return nil
        }
        if let (row, start, end) = relevant.first(where: { $0.0.kind == .dated }) {
            return .required(from: start, to: end, source: row.sourceURL)
        }
        if let (_, start, end) = relevant.first(where: { $0.0.kind == .conditional }) {
            return .conditional(from: start, to: end)
        }
        return .noDatedRule
    }

    private static func dayParts(_ value: String?) -> (month: Int, day: Int)? {
        guard let value, value.count == 5 else { return nil }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let month = Int(parts[0]), let day = Int(parts[1]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        return (month, day)
    }
}

public enum TireLawError: Error { case bundleMissing }

private struct Seed: Decodable {
    let version: Int
    let rows: [Row]

    struct Row: Decodable {
        let country: String
        let jurisdiction: String?
        let vehicleClass: String
        let kind: String
        let from: String?
        let to: String?
        let criteria: String
        let seasonGate: SeasonGate
        let sourceURL: String
        let checked: String
        let status: String
        let note: String
    }
}

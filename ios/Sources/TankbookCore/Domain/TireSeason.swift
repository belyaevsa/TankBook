import Foundation

/// A tire set's season (docs/SCHEMA.md -> TireSet.season). An open set of
/// string values, not a closed enum: a value a newer build adds decodes and
/// re-encodes unchanged here, so it never breaks an older client's sync - the
/// failure a new raw value in a closed enum causes (docs/API.md -> payload
/// change verdicts).
public struct TireSeason: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public static let summer = TireSeason(rawValue: "summer")
    public static let winter = TireSeason(rawValue: "winter")
    public static let allSeason = TireSeason(rawValue: "allSeason")
    /// The choices the app offers, in order.
    public static let offered: [TireSeason] = [.summer, .winter, .allSeason]

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

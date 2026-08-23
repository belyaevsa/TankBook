import Foundation

/// One make/model row in the bundled vehicle catalog (docs/SCHEMA.md,
/// Vehicle catalog). Catalog values are *suggestions* copied into a `Vehicle`
/// row - no `Vehicle` ever references a catalog id, so a catalog correction
/// never mutates a user's garage.
public struct VehicleCatalogEntry: Codable, Equatable, Sendable {
    public let make: String
    public let model: String
    /// Short generation descriptor, e.g. "Mk7/Mk8" or "SPA".
    public let generation: String
    /// `[start, end]` model years; the open end is `nil` ("still in production").
    /// A `null` in the seed pack must never decode to a literal year, because
    /// anything that does date maths on the array would read `0` as 1970-ish.
    public let years: [Int?]
    public let powertrain: Powertrain
    public let fuelKinds: [FuelKind]
    public let tankCapacityL: Double?
    public let batteryCapacityKWh: Double?
    public let packVersion: Int

    public init(make: String, model: String, generation: String, years: [Int?],
                powertrain: Powertrain, fuelKinds: [FuelKind],
                tankCapacityL: Double?, batteryCapacityKWh: Double?,
                packVersion: Int) {
        self.make = make
        self.model = model
        self.generation = generation
        self.years = years
        self.powertrain = powertrain
        self.fuelKinds = fuelKinds
        self.tankCapacityL = tankCapacityL
        self.batteryCapacityKWh = batteryCapacityKWh
        self.packVersion = packVersion
    }

    public var yearsStart: Int { years.first?.flatMap { $0 } ?? 0 }

    /// The last model year, or nil when the range end is unknown/present.
    public var yearsEnd: Int? {
        guard years.count > 1, let end = years[1], end > 0 else { return nil }
        return end
    }

    /// Human label, e.g. "Volvo V60".
    public var title: String { "\(make) \(model)" }
}

/// The seed pack envelope: a version plus the entries it curates. Bumped as
/// the pack is curated; the client checks `packVersion` occasionally and never
/// at launch-blocking time (docs/SCHEMA.md, Vehicle catalog).
public struct VehicleCatalogSeed: Codable, Equatable, Sendable {
    public let packVersion: Int
    public let entries: [VehicleCatalogEntry]

    public init(packVersion: Int, entries: [VehicleCatalogEntry]) {
        self.packVersion = packVersion
        self.entries = entries
    }
}

/// Loads the bundled catalog seed pack. The pack lives in the package bundle,
/// so Add-car autocomplete works with no network on day one; the real
/// `GET /catalog` delta delivery is a later task.
public enum VehicleCatalogStore {
    public static let bundledResourceName = "VehicleCatalog.seed"
    public static let bundledExtension = "json"

    public static func bundledEntries() throws -> [VehicleCatalogEntry] {
        guard let url = Bundle.module.url(forResource: bundledResourceName,
                                          withExtension: bundledExtension) else {
            throw CatalogError.bundleMissing
        }
        return try entries(at: url)
    }

    public static func entries(at url: URL) throws -> [VehicleCatalogEntry] {
        try decode(data: Data(contentsOf: url))
    }

    public static func decode(data: Data) throws -> [VehicleCatalogEntry] {
        let seed = try JSONDecoder().decode(VehicleCatalogSeed.self, from: data)
        return seed.entries
    }
}

public enum CatalogError: Error, Equatable {
    case bundleMissing
}

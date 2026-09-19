import Foundation

// MARK: - The station brand vocabulary (docs/API.md -> "GET /reference/station-brands")

/// One curated chain: a stable id, a display name, its home market and the
/// alias spellings people type or receipts print (`Газпромнефть`, `G-Drive`,
/// `Gazpromneft`). Brands, never individual forecourts - a station is still
/// the user's own `Station`, and only its `brand` is set from this list, once,
/// when the station is created (hard rule 13: a default, never a fact).
public struct StationBrand: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    /// ISO 3166-1 alpha-2 home market, for the device's relevance ordering.
    public let country: String
    public let aliases: [String]

    public init(id: String, name: String, country: String, aliases: [String]) {
        self.id = id
        self.name = name
        self.country = country
        self.aliases = aliases
    }
}

/// A served pack: `full` replaces the held set, `delta` overlays it by id.
public enum StationBrandPackKind: String, Codable, Sendable {
    case full
    case delta
}

public struct StationBrandPack: Codable, Sendable, Equatable {
    public let packVersion: Int
    public let brands: [StationBrand]
    public let kind: StationBrandPackKind

    public init(packVersion: Int, brands: [StationBrand], kind: StationBrandPackKind = .full) {
        self.packVersion = packVersion
        self.brands = brands
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey { case packVersion, brands, kind }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packVersion = try container.decode(Int.self, forKey: .packVersion)
        brands = try container.decode([StationBrand].self, forKey: .brands)
        // The bundled seed carries no kind: it is a full pack by construction.
        kind = try container.decodeIfPresent(StationBrandPackKind.self, forKey: .kind) ?? .full
    }

    /// Applies a served pack to the held set: a full pack replaces it, a delta
    /// overlays by id, and a version not above the held one changes nothing
    /// (rollback protection, docs/SYNC.md "Applying an update").
    public func applying(_ served: StationBrandPack) -> StationBrandPack {
        guard served.packVersion > packVersion else { return self }
        switch served.kind {
        case .full:
            return StationBrandPack(packVersion: served.packVersion, brands: served.brands)
        case .delta:
            var byID = Dictionary(brands.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            for brand in served.brands { byID[brand.id] = brand }
            let merged = byID.values.sorted { ($0.country, $0.name, $0.id) < ($1.country, $1.name, $1.id) }
            return StationBrandPack(packVersion: served.packVersion, brands: merged)
        }
    }
}

extension Station {
    /// What a Log row and a picker show for the station (docs/JOURNEYS.md J4,
    /// RV.180): the BRAND when one is set - the chain is what the user
    /// recognises - else the name. The name stays the site's full printed
    /// line, which is what tells two forecourts of one chain apart.
    public var displayTitle: String {
        guard let brand, !brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return name }
        return brand
    }
}

// MARK: - The bundled seed

public enum StationBrandSeed {
    static let bundledResourceName = "StationBrands.seed"

    /// The pack compiled into the app, so a name typed or imported on day one
    /// groups under its chain without a network (hard rule 1).
    public static func bundledPack() throws -> StationBrandPack {
        guard let url = Bundle.module.url(forResource: bundledResourceName, withExtension: "json") else {
            throw StationBrandSeedError.missingResource
        }
        return try JSONDecoder().decode(StationBrandPack.self, from: Data(contentsOf: url))
    }

    public enum StationBrandSeedError: Error { case missingResource }
}

import Foundation

/// One city of the bundled dictionary (docs/SCHEMA.md -> Places): a GeoNames
/// place with its coordinate, country and the spellings it is matched by.
public struct City: Codable, Sendable, Equatable, Identifiable {
    /// The GeoNames id - stable across dictionary versions.
    public let id: Int
    public let name: String
    public let en: String
    public let ru: String?
    /// ISO 3166-1 alpha-2.
    public let country: String
    public let latitude: Double
    public let longitude: Double
    public let population: Int
    /// The other spellings it answers to: local names, receipt forms, misreads.
    public let aliases: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, en, ru, country = "c", latitude = "lat", longitude = "lon", population = "pop",
             aliases = "alt"
    }

    public init(id: Int, name: String, en: String, ru: String? = nil, country: String,
                latitude: Double, longitude: Double, population: Int, aliases: [String] = []) {
        self.id = id
        self.name = name
        self.en = en
        self.ru = ru
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.population = population
        self.aliases = aliases
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        en = try c.decodeIfPresent(String.self, forKey: .en) ?? name
        ru = try c.decodeIfPresent(String.self, forKey: .ru)
        country = try c.decode(String.self, forKey: .country)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        population = try c.decodeIfPresent(Int.self, forKey: .population) ?? 0
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
    }

    /// The name in the user's language: Russian when asked and known, else English.
    public func displayName(russian: Bool) -> String {
        russian ? (ru ?? en) : en
    }
}

/// A versioned dictionary file - the bundled seed or a served pack.
public struct CityPack: Codable, Sendable, Equatable {
    public let version: Int
    public let cities: [City]

    public init(version: Int, cities: [City]) {
        self.version = version
        self.cities = cities
    }

    /// The bundled seed. A missing or unreadable file is an empty pack - the
    /// home-city question then offers the typed "Other" path only.
    public static let bundled: CityPack = {
        guard let url = Bundle.module.url(forResource: "Cities.seed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let pack = try? JSONDecoder().decode(CityPack.self, from: data) else {
            return CityPack(version: 0, cities: [])
        }
        return pack
    }()
}

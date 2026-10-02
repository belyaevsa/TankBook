import Foundation

/// Where a car is usually kept (docs/SCHEMA.md -> Vehicle.homeCity): the city
/// its owner confirmed, stored on the car as its own copy - name, country and
/// coordinate - so a dictionary update never rewrites it (hard rule 13).
/// `cityId` names the dictionary entry it came from, nil for a city typed
/// under "Other".
public struct HomeCity: Codable, Sendable, Equatable {
    public var cityId: Int?
    public var name: String
    /// ISO 3166-1 alpha-2.
    public var country: String
    public var latitude: Double
    public var longitude: Double

    public init(cityId: Int? = nil, name: String, country: String, latitude: Double, longitude: Double) {
        self.cityId = cityId
        self.name = name
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
    }

    public init(city: City) {
        self.init(cityId: city.id, name: city.en, country: city.country,
                  latitude: city.latitude, longitude: city.longitude)
    }

    /// The name to show: the dictionary's name in the user's language when the
    /// entry is known, else the stored one.
    public func displayName(russian: Bool, dictionary: CityDictionary) -> String {
        cityId.flatMap(dictionary.city(id:))?.displayName(russian: russian) ?? name
    }
}

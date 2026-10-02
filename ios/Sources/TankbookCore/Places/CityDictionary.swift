import Foundation

/// Looks cities up by any of their spellings. Every name is reduced to one
/// matching key - uppercase, diacritics folded (`Rīga` -> `RIGA`), Cyrillic
/// letters that look Latin canonicalised the way the receipt vocabularies are
/// (`FuelKindNormalizer.canonicalKey`), punctuation as spaces - so a receipt's
/// `TALLINN,` and a typed `Tallinn` meet the same entry.
public struct CityDictionary: Sendable {
    public let pack: CityPack
    private let byKey: [String: [Int]]

    public init(pack: CityPack) {
        self.pack = pack
        var index: [String: [Int]] = [:]
        for (position, city) in pack.cities.enumerated() {
            let names = Set([city.name, city.en] + [city.ru].compactMap { $0 } + city.aliases)
            for name in names {
                let key = Self.key(name)
                guard key.count >= 3 else { continue }
                if index[key]?.contains(position) != true { index[key, default: []].append(position) }
            }
        }
        byKey = index
    }

    /// The cities a name can mean, most populous first; `country` narrows them.
    public func cities(named name: String, country: String? = nil) -> [City] {
        (byKey[Self.key(name)] ?? [])
            .map { pack.cities[$0] }
            .filter { country == nil || $0.country == country }
            .sorted { $0.population > $1.population }
    }

    public func city(id: Int) -> City? {
        pack.cities.first { $0.id == id }
    }

    /// The picker's search: names starting with what was typed, the given
    /// country first, then by population. Empty text lists the country's
    /// largest cities.
    public func search(_ text: String, country: String?, limit: Int = 30) -> [City] {
        let typed = Self.key(text)
        let matches = pack.cities.filter { city in
            guard !typed.isEmpty else { return city.country == country }
            let names = [city.name, city.en] + [city.ru].compactMap { $0 } + city.aliases
            return names.contains { Self.key($0).hasPrefix(typed) }
        }
        return Array(matches.sorted {
            let lhsHome = $0.country == country, rhsHome = $1.country == country
            if lhsHome != rhsHome { return lhsHome }
            return $0.population > $1.population
        }.prefix(limit))
    }

    /// The matching key of a name.
    public static func key(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()
        let canonical = FuelKindNormalizer.canonicalKey(folded)
        let letters = canonical.map { $0.isLetter ? $0 : " " }
        return String(letters).split(separator: " ").joined(separator: " ")
    }
}

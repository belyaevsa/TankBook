import Foundation

/// The city a receipt prints in its station address - the suggestion the car's
/// home-city question starts from (docs/SCHEMA.md -> Places). A suggestion only:
/// the user confirms or changes it (hard rule 13), and nil means "ask with an
/// empty city", never a guess.
///
/// Every one-, two- and three-word run of an address line is looked up. A run
/// next to a street word - after it (`ул. Ленинградская`) or before it
/// (`PETERBURI TEE`) - names a street after a city and loses; a run after
/// `г.`/`город` (also when the marker ends the line before), at the end of a
/// line or in a hinted country wins; population breaks ties. A highway named
/// for the cities it joins (`автодороги Москва-Санкт-Петербург`) loses like a
/// street. The company's registered office is not penalised: on the corpus it
/// is usually the station's own city, and often the better-printed line.
public enum ReceiptCityFinder {
    /// Lines past this many from the top are the till's body, not the header
    /// that carries the station address.
    static let headerLines = 16

    /// Single words shorter than this match only after a city marker - short
    /// names collide with receipt words.
    static let minimumBareLength = 5

    static let streetWords: Set<String> = [
        "TEE", "MNT", "PST", "PUIESTEE", "TN", "TANAV", "IELA", "GATVE", "PR", "PROSPEKT", "PROSPEKTAS",
        "ST", "STR", "STREET", "STRASSE", "RD", "ROAD", "AVE", "AVENUE", "UL", "ULICA", "ALLEE", "WEG", "PL",
        "УЛ", "УЛИЦА", "ПР", "ПРОСП", "ПРОСПЕКТ", "ШОССЕ", "Ш", "ПЕР", "ПЕРЕУЛОК", "БУЛЬВАР", "НАБ", "ТРАКТ",
        "АВТОДОРОГА", "АВТОДОРОГИ", "ТРАССА", "ТРАССЫ", "КМ", "KM",
    ].reduce(into: Set<String>()) { $0.insert(CityDictionary.key($1)) }

    /// Till words that are also some city's name in some language (`KASSA` is
    /// Košice in Hungarian): never a city on their own.
    static let tillWords: Set<String> = ["KASSA", "KASSE", "KASSIR", "TOTAL", "SUMMA", "KOKKU", "КАССА", "ИТОГ",
                                         "СУММА", "ЧЕК", "KVIITUNG", "ARVE", "BANK", "KAART"]
        .reduce(into: Set<String>()) { $0.insert(CityDictionary.key($1)) }

    static let cityMarkers: Set<String> = ["Г", "ГОР", "ГОРОД", "G", "GOROD"]
        .reduce(into: Set<String>()) { $0.insert(CityDictionary.key($1)) }

    /// The best city in the receipt's header lines, or nil. `countryHints` are
    /// tried in order (the receipt's currency country, the device region).
    public static func city(in lines: [OCRLine], dictionary: CityDictionary,
                            countryHints: [String] = []) -> City? {
        var best: (score: Int, city: City)?
        var previousLineEndsWithMarker = false
        for line in lines.prefix(headerLines) {
            let words = CityDictionary.key(line.text).split(separator: " ").map(String.init)
            defer { previousLineEndsWithMarker = words.last.map(cityMarkers.contains) ?? false }
            let lineEnds = line.text.trimmingCharacters(in: .whitespaces)
            for start in words.indices {
                for length in 1...3 where start + length <= words.count {
                    let run = words[start..<(start + length)].joined(separator: " ")
                    let afterMarker = start > 0 ? cityMarkers.contains(words[start - 1])
                                                : previousLineEndsWithMarker
                    if length == 1, run.count < minimumBareLength || tillWords.contains(run), !afterMarker { continue }
                    let candidates = dictionary.cities(named: run)
                    guard !candidates.isEmpty else { continue }
                    let next = start + length < words.count ? words[start + length] : nil
                    var score = length > 1 ? 1 : 0
                    if afterMarker { score += 3 }
                    if next == nil || lineEnds.hasSuffix(",") { score += 1 }
                    if let next, streetWords.contains(next) { score -= 5 }
                    if start > 0, streetWords.contains(words[start - 1]) { score -= 5 }
                    for city in candidates {
                        var cityScore = score
                        if let rank = countryHints.firstIndex(of: city.country) { cityScore += 3 - min(rank, 2) }
                        if best == nil || cityScore > best!.score
                            || (cityScore == best!.score && city.population > best!.city.population) {
                            best = (cityScore, city)
                        }
                    }
                }
            }
        }
        guard let best, best.score >= 0 else { return nil }
        return best.city
    }
}

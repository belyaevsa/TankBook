import Foundation

// MARK: - Matching a free-text station name to a brand (RV.115)

/// The case- and script-insensitive matcher. A name matches a brand when one
/// of the brand's spellings (its name or an alias) occurs in the name as a
/// run of WHOLE tokens after normalisation - never as a substring, which is
/// the false-positive guard: `Green` does not match `Greenway`, `Compass` does
/// not match `Encompass`, and a two-letter alias cannot fire inside a longer
/// word. Legal forms and the generic words a receipt prints around a chain
/// (`ООО`, `АЗС`, `Tankstelle`, `Ltd`) are dropped before matching so
/// `ООО "Газпромнефть-Центр" АЗС 12089` still finds `Газпромнефть`. The
/// longest matching spelling wins, so `Circle K` beats a hypothetical `K`.
///
/// A name matching nothing is a first-class result: `nil`, the user's own
/// station with no brand, not an error.
public enum StationBrandMatcher {

    public static func match(_ name: String, brands: [StationBrand]) -> StationBrand? {
        let tokens = normalisedTokens(name)
        guard !tokens.isEmpty else { return nil }
        var best: (brand: StationBrand, length: Int)?
        for brand in brands {
            for spelling in [brand.name] + brand.aliases {
                let needle = normalisedTokens(spelling)
                guard !needle.isEmpty, needle.count <= tokens.count, contains(tokens, run: needle) else { continue }
                let length = needle.joined().count
                if length > (best?.length ?? 0) { best = (brand, length) }
            }
        }
        return best?.brand
    }

    /// The words matching ignores: legal forms, the generic "station" nouns in
    /// the scripts the app serves, and the connective noise a printed line
    /// carries. Lowercased, transliterated form.
    static let noiseTokens: Set<String> = [
        "ooo", "oao", "zao", "pao", "ao", "ip", "tov", "too", "azs", "agzs", "azk", "aes",
        "ltd", "llc", "inc", "gmbh", "ag", "oy", "ab", "as", "sia", "uab", "sp", "zoo", "sro", "kft",
        "station", "tankstelle", "tankstation", "tankla", "tanklad", "teenindusjaam", "stacja",
        "stacija", "degvielas", "uzpilde", "asema", "huoltoasema", "gas", "petrol", "fuel", "servis",
        "service", "the", "and", "und", "ja", "ir", "un"
    ]

    /// Lowercased, Cyrillic transliterated to Latin, split on anything that is
    /// not a letter or a digit, noise dropped. Digits are kept: a forecourt
    /// number is a token, and it never equals a brand spelling.
    public static func normalisedTokens(_ text: String) -> [String] {
        let folded = transliterate(text.lowercased())
        return folded
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !noiseTokens.contains($0) }
    }

    private static func contains(_ tokens: [String], run: [String]) -> Bool {
        guard run.count <= tokens.count else { return false }
        for start in 0...(tokens.count - run.count) where Array(tokens[start..<(start + run.count)]) == run {
            return true
        }
        return false
    }

    /// A fixed Cyrillic-to-Latin map (the GOST-like spelling people actually
    /// type: `ж` -> `zh`, `х` -> `kh`, `ц` -> `ts`, `ч` -> `ch`, `ш` -> `sh`,
    /// `щ` -> `shch`, `ю` -> `yu`, `я` -> `ya`; `ё` folds to `e`, signs drop).
    /// Kazakh letters map to their nearest Latin. Deterministic and offline;
    /// `StringTransform.toLatin` would have been locale- and OS-version-
    /// dependent, which a matcher two devices must agree on cannot be.
    static func transliterate(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            if let latin = cyrillic[scalar] {
                out += latin
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    private static let cyrillic: [Unicode.Scalar: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh", "з": "z",
        "и": "i", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r",
        "с": "s", "т": "t", "у": "u", "ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh",
        "щ": "shch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
        // Kazakh
        "ә": "a", "ғ": "g", "қ": "k", "ң": "n", "ө": "o", "ұ": "u", "ү": "u", "һ": "h", "і": "i",
        // Ukrainian / Belarusian
        "є": "ye", "ї": "yi", "ґ": "g", "ў": "u"
    ]
}

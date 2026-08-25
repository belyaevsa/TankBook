import Foundation

/// Maps a raw OCR'd fuel product token onto the SCHEMA FuelKind vocabulary
/// (docs/SCHEMA.md). Anchoring to a *product line* is the caller's job; this
/// type only turns a product line's text into a kind.
public enum FuelKindNormalizer {
    /// A line that can name a fuel grade: it carries a fuel word (БЕНЗИН, ДТ,
    /// СУГ, ...) or the АИ-NN-K5 octane pattern. A bare "98" from "АЗС-98" or
    /// "ТРК №3" fails this test and is ignored.
    public static func isProductLine(_ text: String) -> Bool {
        let upper = text.uppercased()
        let fuelWords = ["БЕНЗИН", "БЕНЗ", "ДИЗ", "ДТ", "СУГ", "КПГ", "ПРОПАН", "МЕТАН",
                         "АВТОГАЗ", "DIESEL", "PETROL", "BENZIN", "GASOLINE", "G-DRIVE",
                         "GDRIVE", "ЭКТО", "V-POWER", "ULTIMATE", "EXCELLIUM"]
        // A grade code must not run into more letters: "ДТ" occurs inside
        // "ПОДТВЕРЖДЕНА" ("Операция подтверждена вводом ПИН" - the card terminal
        // line on every Russian card receipt), which made a payment
        // confirmation look like a diesel product line (receipt-034).
        if fuelWords.contains(where: { matchesFuelToken($0, in: upper) }) { return true }
        return upper.firstMatch(of: /А[ИН][\s\-–]*\d{2,3}/) != nil
    }

    /// Normalises a product line to a FuelKind, or nil when the line names no
    /// recognised fuel.
    public static func normalize(_ productText: String) -> FuelKind? {
        let upper = productText.uppercased()

        // Fuel families first: their names can contain digits that look like an
        // octane (ДТ-Л-К5, ДТ-3-К5), so they must win over octane matching.
        // Every family match is anchored to a WORD START. As a bare substring,
        // "ДТ" matches "ПОДТВЕРЖДЕНА" - the card-terminal confirmation line
        // printed on Russian card receipts - and classified receipt-034's
        // АИ-95 fill as DIESEL. `fuelKind` is a stored domain field, so that is
        // a confident wrong value, which is the one thing hard rule 13 forbids.
        if ["ДТ", "ДИЗ", "DIESEL"].contains(where: { matchesFuelToken($0, in: upper) }) {
            return .diesel
        }
        if ["СУГ", "LPG", "GPL", "ПРОПАН", "АВТОГАЗ"].contains(where: { matchesFuelToken($0, in: upper) }) {
            return .lpg
        }
        if ["КПГ", "CNG", "МЕТАН"].contains(where: { matchesFuelToken($0, in: upper) }) {
            return .cng
        }

        guard let octane = octane(in: upper) else { return nil }
        switch octane {
        case 92: return .petrol92
        case 95: return .petrol95
        case 98: return .petrol98
        case 100: return .petrol100
        default: return nil
        }
    }

    /// Fuel ABBREVIATIONS, which are never the start of a longer word: a grade
    /// code is always followed by a separator, a digit or the end of the line
    /// ("ДТ-Л-К5", "ДТ", "СУГ 1"). Everything else in the vocabulary is a word
    /// stem that legitimately continues ("ДИЗ" in "ДИЗЕЛЬНОЕ").
    private static let abbreviations: Set<String> = ["ДТ", "СУГ", "КПГ", "LPG", "GPL", "CNG"]

    /// Whether `needle` names a fuel in `text`.
    ///
    /// For an abbreviation the character AFTER the match must not be a letter.
    /// That is the rule that separates "ДТ-3-К3" from "ПОДТВЕРЖДЕНА" - and note
    /// it deliberately checks the FOLLOWING character rather than the preceding
    /// one: real OCR glues words together ("зимнеекдт-3-к3" is a corpus case),
    /// so requiring a word START would reject genuine diesel lines. What never
    /// happens is a grade code running straight into more letters.
    ///
    /// For a stem, a plain containment stands.
    static func matchesFuelToken(_ needle: String, in text: String) -> Bool {
        guard abbreviations.contains(needle) else { return text.contains(needle) }
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: needle, range: searchRange) {
            let followedByLetter = found.upperBound < text.endIndex
                && text[found.upperBound].isLetter
            if !followedByLetter { return true }
            guard found.upperBound < text.endIndex else { return false }
            searchRange = found.upperBound..<text.endIndex
        }
        return false
    }

    /// The octane number from "АИ-95-К5", "АН-95" (garbled), "G-DRIVE 95",
    /// "ЭКТО-100". Returns nil when no octane is present.
    static func octane(in upper: String) -> Int? {
        if let match = upper.firstMatch(of: /А[ИН][\s\-–]*(\d{2,3})/), let value = Int(match.1) {
            return value
        }
        if let match = upper.firstMatch(of: /(?:БЕНЗИН|PETROL|BENZIN|GASOLINE|G-DRIVE|GDRIVE|ЭКТО)[^\d]*(\d{2,3})/),
           let value = Int(match.1) {
            return value
        }
        return nil
    }
}

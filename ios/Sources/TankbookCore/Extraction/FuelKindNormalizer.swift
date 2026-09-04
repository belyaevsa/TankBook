import Foundation

/// Maps a raw OCR'd fuel product token onto the SCHEMA FuelKind vocabulary
/// (docs/SCHEMA.md). Anchoring to a *product line* is the caller's job; this
/// type only turns a product line's text into a kind.
public enum FuelKindNormalizer {
    // MARK: - Homoglyph canonicalisation (P2.11)

    /// Cyrillic letters that share a glyph with a Latin letter, mapped to their
    /// Latin twin. Vision picks glyphs by SHAPE, not by the document's language
    /// (docs/EXTRACTION.md), so a Russian receipt OCRs as a *mixture* of the
    /// two scripts - receipt-034's product line is `Plus (AИ-95-К5), л` with a
    /// **Latin A** and a Cyrillic И. The full confusable set: А/A, О/O, Р/P,
    /// С/C, Е/E, Х/X, К/K, М/M, В/B, Н/H, Т/T.
    static let latinTwin: [Character: Character] = [
        "А": "A", "О": "O", "Р": "P", "С": "C", "Е": "E", "Х": "X",
        "К": "K", "М": "M", "В": "B", "Н": "H", "Т": "T"
    ]

    /// The canonical form of `text`: every confusable Cyrillic letter becomes
    /// its Latin twin.
    ///
    /// **This is a matching key, never a stored representation.** A station
    /// name must survive exactly as printed (docs/SCHEMA.md -> Station): if the
    /// receipt says `Circle K`, the entry stores `Circle K`, not a
    /// transliterated variant. Nothing the extractor persists is ever derived
    /// from this function's output - only the extractor's *comparison* path
    /// touches it.
    static func canonicalKey(_ text: String) -> String {
        String(text.map { latinTwin[$0] ?? $0 })
    }

    /// The full matching key: uppercase, then homoglyph canonicalisation. Applied
    /// to BOTH the OCR'd line and every keyword it is compared against, so the
    /// two scripts can never disagree about a glyph that looks like a twin.
    private static func matchingKey(_ text: String) -> String {
        canonicalKey(text.uppercased())
    }

    /// The octane pattern in canonical form: a Latin A (Cyrillic А becomes it)
    /// followed by a Cyrillic И or a Latin H (Cyrillic Н becomes it) - the
    /// `А[ИН]` of a Cyrillic-printed `АИ-95` after canonicalisation. И is not
    /// in the confusable set and stays Cyrillic in the matching key.
    private static var octanePattern: Regex<(Substring, Substring)> { /A[ИH][\s\-–]*(\d{2,3})/ }

    /// The grade-word alternation in canonical form (see `canonicalKey`):
    /// "БЕНЗИН" -> "БЕHЗИH", "ЭКТО" -> "ЭKТO"; the Latin keywords are unchanged.
    private static var gradeWordsPattern: Regex<(Substring, Substring)> {
        /(?:БЕHЗИH|PETROL|BENZIN|GASOLINE|G-DRIVE|GDRIVE|ЭKТO)[^\d]*(\d{2,3})/
    }

    /// A line that can name a fuel grade: it carries a fuel word (БЕНЗИН, ДТ,
    /// СУГ, ...) or the АИ-NN-K5 octane pattern. A bare "98" from "АЗС-98" or
    /// "ТРК №3" fails this test and is ignored.
    public static func isProductLine(_ text: String) -> Bool {
        let upper = matchingKey(text)
        let fuelWords = ["БЕНЗИН", "БЕНЗ", "ДИЗ", "ДТ", "СУГ", "КПГ", "ПРОПАН", "МЕТАН",
                         "АВТОГАЗ", "DIESEL", "PETROL", "BENZIN", "GASOLINE", "G-DRIVE",
                         "GDRIVE", "ЭКТО", "V-POWER", "ULTIMATE", "EXCELLIUM", "MILES"]
        // A grade code must not run into more letters: "ДТ" occurs inside
        // "ПОДТВЕРЖДЕНА" ("Операция подтверждена вводом ПИН" - the card terminal
        // line on every Russian card receipt), which made a payment
        // confirmation look like a diesel product line (receipt-034).
        if fuelWords.contains(where: { matchesFuelToken(matchingKey($0), in: upper) }) { return true }
        if upper.firstMatch(of: octanePattern) != nil { return true }
        // A smeared octane prefix (`AM-95`, `АЙ-100`) is a grade only when the
        // Euro-5 suffix corroborates it on the same line - see
        // `corroboratedSmearedOctane`.
        return corroboratedSmearedOctane(in: upper) != nil
    }

    /// Normalises a product line to a FuelKind, or nil when the line names no
    /// recognised fuel.
    public static func normalize(_ productText: String) -> FuelKind? {
        let upper = matchingKey(productText)

        // Fuel families first: their names can contain digits that look like an
        // octane (ДТ-Л-К5, ДТ-3-К5), so they must win over octane matching.
        // Every family match is anchored to a WORD START. As a bare substring,
        // "ДТ" matches "ПОДТВЕРЖДЕНА" - the card-terminal confirmation line
        // printed on Russian card receipts - and classified receipt-034's
        // АИ-95 fill as DIESEL. `fuelKind` is a stored domain field, so that is
        // a confident wrong value, which is the one thing hard rule 13 forbids.
        if ["ДТ", "ДИЗ", "DIESEL"].contains(where: { matchesFuelToken(matchingKey($0), in: upper) }) {
            return .diesel
        }
        if ["СУГ", "LPG", "GPL", "ПРОПАН", "АВТОГАЗ"]
            .contains(where: { matchesFuelToken(matchingKey($0), in: upper) }) {
            return .lpg
        }
        if ["КПГ", "CNG", "МЕТАН"].contains(where: { matchesFuelToken(matchingKey($0), in: upper) }) {
            return .cng
        }
        if let kind = circleKLoyaltyGrade(in: upper) { return kind }

        guard let octane = octane(in: upper) else {
            // The octane prefix is smeared beyond the canonical `A[ИH]` pattern.
            // It is still accepted when the Euro-5 suffix corroborates it - see
            // `corroboratedSmearedOctane` for why that is corroboration and not
            // resolution by resemblance.
            guard let corroborated = corroboratedSmearedOctane(in: upper) else { return nil }
            return Self.kind(forOctane: corroborated)
        }
        return Self.kind(forOctane: octane)
    }

    /// Maps an octane number onto the FuelKind vocabulary, or nil when it is
    /// not a retail grade (e.g. receipt-027's `АИ-96`).
    private static func kind(forOctane octane: Int) -> FuelKind? {
        switch octane {
        case 92: return .petrol92
        case 95: return .petrol95
        case 98: return .petrol98
        case 100: return .petrol100
        default: return nil
        }
    }

    /// The Circle K loyalty grade names, which are the product string on every
    /// Estonian receipt in the corpus and name a fuel nowhere else in the
    /// vocabulary: `D B0 miles` (diesel, B0 = no biodiesel) and `95E0 miles`
    /// (petrol 95, E0 = no ethanol). Four fixtures print the first and two the
    /// second, and `Spike/ReceiptSpike/fixtures/receipts/README.md` has called
    /// this "vocabulary work, not parsing work" since receipt-042.
    ///
    /// The zero is matched as `[0OÓ]` because it is a zero the OCR reads as a
    /// letter: the corpus carries `D B0`, `D BO` and `D BÓ` for the same grade
    /// (receipt-001, receipt-045, receipt-046). The `MILES` suffix is REQUIRED
    /// on both, which is what keeps a bare `D` or a bare `95` on some other
    /// line from reaching this path.
    private static func circleKLoyaltyGrade(in upper: String) -> FuelKind? {
        guard upper.contains("MILES") else { return nil }
        if upper.firstMatch(of: /\bD\s*B[0OÓ]\b/) != nil { return .diesel }
        if let match = upper.firstMatch(of: /\b(\d{2,3})E\d\b/), let octane = Int(match.1) {
            switch octane {
            case 92: return .petrol92
            case 95: return .petrol95
            case 98: return .petrol98
            case 100: return .petrol100
            default: return nil
            }
        }
        return nil
    }

    /// Fuel ABBREVIATIONS, which are never the start of a longer word: a grade
    /// code is always followed by a separator, a digit or the end of the line
    /// ("ДТ-Л-К5", "ДТ", "СУГ 1"). Everything else in the vocabulary is a word
    /// stem that legitimately continues ("ДИЗ" in "ДИЗЕЛЬНОЕ").
    private static let abbreviations: Set<String> = ["ДТ", "СУГ", "КПГ", "LPG", "GPL", "CNG"]

    /// `abbreviations` in canonical form, so the membership test compares keys
    /// of the same script as the input ("СУГ" canonicalises to "CУГ", "КПГ" to
    /// "KПГ" - the Cyrillic С and К each have a Latin twin).
    private static var canonicalAbbreviations: Set<String> {
        Set(abbreviations.map(canonicalKey))
    }

    /// Whether `needle` names a fuel in `text`. Both arguments are canonical
    /// matching keys (see `matchingKey`).
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
        guard canonicalAbbreviations.contains(needle) else { return text.contains(needle) }
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
    /// "ЭКТО-100". Returns nil when no octane is present. Expects a canonical
    /// matching key (see `matchingKey`).
    static func octane(in upper: String) -> Int? {
        if let match = upper.firstMatch(of: octanePattern), let value = Int(match.1) {
            return value
        }
        if let match = upper.firstMatch(of: gradeWordsPattern), let value = Int(match.1) {
            return value
        }
        return nil
    }

    // MARK: - A smeared octane, corroborated by the Euro-5 suffix

    /// The octane number immediately before a `-К5`/`-K5` suffix, or nil.
    ///
    /// Thermal print smears the `И` of `АИ-95` into letters the canonical
    /// octane pattern `A[ИH]` cannot read: `AM-95` (И -> M, receipt-032),
    /// `АЙ-100` (И -> Й, receipt-018). `И -> M` is not a homoglyph pair - `M`
    /// is already the twin of `М` in `latinTwin` - so widening the octane
    /// letter class would be resolution by resemblance, the move
    /// `HIGH-WATER.md` forbids and `receipt-027`'s `АИ-96` exists to punish.
    ///
    /// The `-К5`/`-K5` suffix is the corroboration instead. It is the Euro-5
    /// environmental-grade suffix, itself a fuel token that only attaches to a
    /// grade code, and it sits on the SAME line as the octane it confirms. A
    /// line that merely *resembles* a grade (`AM-95` with no suffix, the
    /// receipt-044 case) stays unresolved, and a line that carries a valid
    /// octane but is not a grade (`АИ-96-К5` on receipt-027) still maps to nil
    /// because `kind(forOctane:)` has no 96.
    ///
    /// What it would take to fire on a non-fuel line: a string of two or three
    /// digits immediately followed by the literal token `K5` where the digits
    /// are a retail octane (92/95/98/100). A card authorisation code
    /// `4XK5RH` (receipt-044) has its `K5` preceded by `X`, not by digits, and
    /// `ДТ-Л-К5` has no digit before `K5` at all - so neither fires.
    static func corroboratedSmearedOctane(in upper: String) -> Int? {
        guard upper.contains("K5") else { return nil }
        let pattern = /(\d{2,3})\s*[-–]?\s*K5/
        guard let match = upper.firstMatch(of: pattern), let octane = Int(match.1) else { return nil }
        return octane
    }
}

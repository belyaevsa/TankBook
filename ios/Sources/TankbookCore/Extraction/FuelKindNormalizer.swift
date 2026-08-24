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
        if fuelWords.contains(where: upper.contains) { return true }
        return upper.firstMatch(of: /А[ИН][\s\-–]*\d{2,3}/) != nil
    }

    /// Normalises a product line to a FuelKind, or nil when the line names no
    /// recognised fuel.
    public static func normalize(_ productText: String) -> FuelKind? {
        let upper = productText.uppercased()

        // Fuel families first: their names can contain digits that look like an
        // octane (ДТ-Л-К5, ДТ-3-К5), so they must win over octane matching.
        if upper.contains("ДТ") || upper.contains("ДИЗ") || upper.contains("DIESEL") {
            return .diesel
        }
        if upper.contains("СУГ") || upper.contains("LPG") || upper.contains("GPL")
            || upper.contains("ПРОПАН") || upper.contains("АВТОГАЗ") {
            return .lpg
        }
        if upper.contains("КПГ") || upper.contains("CNG") || upper.contains("МЕТАН") {
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

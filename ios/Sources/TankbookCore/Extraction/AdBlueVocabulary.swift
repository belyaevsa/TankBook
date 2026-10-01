import Foundation

/// The words a receipt prints for diesel exhaust fluid (docs/EXTRACTION.md ->
/// AdBlue). AdBlue is never a fuel: a line it names is never the fuel line,
/// and a receipt that names only AdBlue pre-fills an AdBlue top-up
/// (docs/SCHEMA.md -> AdBlue). Matched through `FuelKindNormalizer.canonicalKey`
/// so a Cyrillic letter Vision reads as its Latin twin cannot stop a match,
/// and anchored to a word start so a longer word that merely contains a token
/// does not count.
public enum AdBlueVocabulary {
    static let words = ["ADBLUE", "AD BLUE", "AD-BLUE", "AUS 32", "AUS32", "AUS-32", "HARNSTOFF",
                        "DIESEL EXHAUST FLUID", "МОЧЕВИНА", "АДБЛЮ"]

    /// Whether the text names AdBlue.
    public static func names(_ text: String) -> Bool {
        let key = FuelKindNormalizer.canonicalKey(text.uppercased())
        return words.contains { word in
            let token = FuelKindNormalizer.canonicalKey(word)
            var search = key.startIndex..<key.endIndex
            while let found = key.range(of: token, range: search) {
                if found.lowerBound == key.startIndex
                    || !key[key.index(before: found.lowerBound)].isLetter { return true }
                search = found.upperBound..<key.endIndex
            }
            return false
        }
    }

    /// How many lines after an AdBlue product name may still belong to its item
    /// block (a label-per-line till prints name, price, volume and amount on
    /// separate lines).
    static let itemBlockLength = 6

    /// The indices of the lines that make up AdBlue items: each line naming
    /// AdBlue and the lines after it, through the item's own operand pair
    /// (`10.00 л X 0.899`) or, on a label-per-line till that prints none, up
    /// to the next fuel product line or total label - at most
    /// `itemBlockLength` lines. Ending at the pair keeps the next item on the
    /// receipt (a coffee) out of the AdBlue item.
    static func itemLineIndices(in lines: [OCRLine]) -> Set<Int> {
        var indices = Set<Int>()
        for (index, line) in lines.enumerated() where names(line.text) {
            indices.insert(index)
            var next = index + 1
            while next < lines.count, next <= index + itemBlockLength {
                let text = lines[next].text
                if FuelExtractor.namesFuel(text) || TotalLabel.classify(text) != nil { break }
                indices.insert(next)
                if OperandPair(line: text) != nil { break }
                next += 1
            }
        }
        return indices
    }
}

extension FuelExtractor {
    /// A fuel product line that is not an AdBlue line ("Diesel Exhaust Fluid"
    /// carries a fuel word and is still not fuel).
    static func namesFuel(_ text: String) -> Bool {
        FuelKindNormalizer.isProductLine(text) && !AdBlueVocabulary.names(text)
    }

    /// An AdBlue line is never the fuel line (docs/EXTRACTION.md -> AdBlue).
    /// With a fuel product beside it, the AdBlue item's lines leave the fuel
    /// ladder; with no fuel product the receipt is an AdBlue top-up
    /// (`isAdBlue`), and the ladder reads its numbers.
    static func separatingAdBlue(_ candidates: [OCRLine], rawLines: [OCRLine]) -> ([OCRLine], Bool?) {
        guard rawLines.contains(where: { AdBlueVocabulary.names($0.text) }) else { return (candidates, nil) }
        guard candidates.contains(where: { namesFuel($0.text) }) else { return (candidates, true) }
        let item = AdBlueVocabulary.itemLineIndices(in: candidates)
        return (candidates.enumerated().filter { !item.contains($0.offset) }.map(\.element), nil)
    }
}

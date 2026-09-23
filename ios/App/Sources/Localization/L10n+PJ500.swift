import Foundation

// What the Confirm sheet says about a pump reading the law
// committed without checking it fully (decision 11, docs/EXTRACTION.md).
extension L10n {
    /// The display's price differs from the one the pair works out to.
    static func pumpShownPriceDiffersMessage(shown: String, implied: String) -> String {
        let format = localize(
            "The display shows %1$@ a litre, but these numbers work out to %2$@ – a discount, or a misread? Check the total and the litres.")
        return String(format: format, shown, implied)
    }
}

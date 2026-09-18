import Foundation

/// The service form's cloud line-offer copy (docs/JOURNEYS.md J7 "every page
/// reaches the cloud", docs/ERRORS.md -> Service & expenses). Whole phrases
/// per language, never concatenation.
extension L10n {
    /// The caption over a paired row's offer strip.
    static var serviceLineOfferCaption: String { localize("From the invoice") }
    /// The caption over a new-line card: a line the local split did not have.
    static var serviceLineOfferNewCaption: String { localize("Also on the invoice") }
    /// Take the invoice's line: replaces the row's title, category and cost.
    static var serviceLineOfferTake: String { localize("Take") }
    /// Keep mine: the default, made explicit.
    static var serviceLineOfferKeep: String { localize("Keep") }
    /// Append the new line to the split.
    static var serviceLineOfferAdd: String { localize("Add") }
    /// Drop the new-line offer.
    static var serviceLineOfferDismiss: String { localize("Dismiss") }
    /// The arithmetic gate's flag under the header total.
    static var serviceReadingDoesNotAddUp: String {
        localize("The reading doesn't add up to the invoice total – check the lines.")
    }
    /// The inbox card's flag on a total offer whose lines do not add up.
    static var inboxReadingDoesNotAddUp: String { localize("Doesn't add up – check the lines") }
    /// The page-cap note: no cloud reading was started, every page is kept.
    static func servicePageCapNote(_ cap: Int) -> String {
        let phrase = localize("This invoice has more pages than the cloud reading takes (%lld) – "
                              + "every page is kept and split on the device. Check the lines.")
        return String(format: phrase, cap)
    }
}

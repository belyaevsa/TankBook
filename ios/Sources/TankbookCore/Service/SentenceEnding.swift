import Foundation

/// Ends a composed sentence without doubling the period.
///
/// RV.77, found by opening the RU screenshot: a catalogue phrase ends in "."
/// because it is a sentence, and its last token is often a formatted date. In
/// English that date is "Sep 3" and the result reads correctly; **in Russian an
/// abbreviated month carries its own period** - "3 сент.", "сент. 2027 г." - so
/// the same composition rendered "3 сент..".
///
/// A full localised phrase per language - the usual fix for composed copy -
/// cannot help here, because the doubling comes from the **value**, not the
/// phrase: the same Russian sentence is correct with a numeric value and wrong
/// with an abbreviated month. This lives in core so any surface composing a
/// sentence around a locale-formatted value can use it.
public enum SentenceEnding {
    /// Collapses a trailing doubled period to one, leaving an ellipsis alone.
    public static func normalized(_ text: String) -> String {
        guard text.hasSuffix(".."), !text.hasSuffix("...") else { return text }
        return String(text.dropLast())
    }
}

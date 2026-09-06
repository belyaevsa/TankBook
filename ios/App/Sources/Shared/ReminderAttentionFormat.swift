import Foundation

/// The per-car attention count's words (RV.79, design/screens/
/// GarageReminderCounts.dc.html): the amber strip on a Garage or Car switcher
/// row reads "2 needs attention". A FULL localised count phrase per language -
/// the number carries real Russian plural rules (rule 10, never
/// concatenation) - composed in ONE place so the two surfaces and their
/// VoiceOver labels can never disagree. Colour is never the only channel
/// (hard rule 5): this text is what the count "reads" as for VoiceOver.
enum ReminderAttentionFormat {
    static func text(_ count: Int) -> String {
        String(localized: "\(count) needs attention")
    }
}

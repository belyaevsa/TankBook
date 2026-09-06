import Foundation
import TankbookCore

/// The multi-car mapping gate's copy (RV.86) - in its own file so `L10n.swift`
/// stays under its 700-line lint budget (the same reason `L10nSyncChip` sits
/// apart). Each phrase is a full localised sentence per language, never
/// concatenation (hard rule 10, and the RU pass on P1.4).
extension L10n {
    /// "Which cars come in?" - the `.cars` step's title. Shown only when the
    /// file's parse exposes more than one distinct source car.
    static var importCarsTitle: String {
        localize("Which cars come in?")
    }

    /// "5 cars in this file. Choose where each one lands, or leave it out." -
    /// the `.cars` intro, plural on the file's car count.
    static func importCarsIntro(_ count: Int) -> String {
        String(localized: "\(count) cars in this file. Choose where each one lands, or leave it out.")
    }

    /// "Landing in 3 cars." - the `.cars` gate's destination-count caption (the
    /// M in "Import N fill-ups into M cars"; N sits on the bar's own button, so
    /// each count keeps its own full localised phrase and its own plural).
    static func importLandsInCars(_ count: Int) -> String {
        String(localized: "Landing in \(count) cars.")
    }

    /// "Choose where each car goes, then import." - the `.cars` hint while a
    /// source car still lacks a destination (the gate's Continue stays disabled).
    static var importCarsHint: String {
        localize("Choose where each car goes, then import.")
    }
}

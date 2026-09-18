import Foundation
import TankbookCore

/// RV.118: the headline's provenance line (docs/JOURNEYS.md J8). Three whole
/// localised count phrases - each with its own plural rules - joined by the
/// middle dot the app already uses between independent facts; never a count
/// glued to a word.
extension L10n {
    static func headlineProvenance(_ provenance: HeadlineProvenance) -> String {
        let fills = String(localized: "\(provenance.fillCount) fills")
        let fullTanks = String(localized: "\(provenance.fullTankCount) full-tank")
        if provenance.underFloor {
            return [localize("Not enough data yet"), fills, fullTanks].joined(separator: " · ")
        }
        let span = String(localized: "last \(provenance.spanDays ?? 0) days")
        return [fills, span, fullTanks].joined(separator: " · ")
    }
}

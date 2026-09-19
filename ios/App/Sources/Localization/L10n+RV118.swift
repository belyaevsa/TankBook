import Foundation
import TankbookCore

/// RV.118: the headline's provenance line (docs/JOURNEYS.md J8). The span is
/// the headline's own honest label ("last 5 months" - the same words the tile
/// has always carried, so an extended window still names its real span), then
/// two whole localised count phrases with their own plural rules, joined by
/// the middle dot the app uses between independent facts; never a count glued
/// to a word.
extension L10n {
    /// `withSpan: false` drops the span - Home's first-estimate line already
    /// prints the label above the figure and must not say it twice.
    static func headlineProvenance(_ provenance: HeadlineProvenance, withSpan: Bool = true) -> String {
        let fills = String(localized: "\(provenance.fillCount) fills")
        let fullTanks = String(localized: "\(provenance.fullTankCount) full-tank")
        if provenance.underFloor {
            return [localize("Not enough data yet"), fills, fullTanks].joined(separator: " · ")
        }
        guard withSpan, let label = provenance.label else {
            return [fills, fullTanks].joined(separator: " · ")
        }
        return [honestSpanLabel(label), fills, fullTanks].joined(separator: " · ")
    }
}

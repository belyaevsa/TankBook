import Foundation
import TankbookCore

/// The after-save toast copy for an `AfterSaveInsight` (docs/JOURNEYS.md J3 →
/// Done). Each case is one full localised phrase per language - never a value
/// spliced into a shared stem (RU declines "best" and "tank" differently, so
/// the sentence is the translation unit). The figure is rendered at the
/// tile's precision in the car's headline unit, the way Home prints it.
enum AfterSaveInsightMessage {
    static func text(for insight: AfterSaveInsight, vehicle: Vehicle) -> String {
        text(for: insight, unit: vehicle.headlineUnit)
    }

    static func text(for insight: AfterSaveInsight, unit headlineUnit: HeadlineUnit) -> String {
        switch insight {
        case .segmentClosed(let per100, let isBestThisYear):
            let figure = ManualFillUpFormat.decimal(
                ConsumptionDisplay.value(per100: per100, unit: headlineUnit), fractionDigits: 1)
            let unit = L10n.headlineUnit(headlineUnit)
            let format = L10n.localize(isBestThisYear ? "%1$@ %2$@ – best this year"
                                                      : "%1$@ %2$@ – this tank")
            return String(format: format, figure, unit)
        case .needsAnotherFullTank:
            return L10n.localize("One more full tank and your consumption appears")
        }
    }
}

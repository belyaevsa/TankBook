import SwiftUI
import TankbookCore

// MARK: - Headline block

/// The hero: average consumption in DIN Condensed, with the honest label line
/// below - "Best this year", a "first estimate" label, or the D4 hint when no
/// segment has closed yet (docs/ERRORS.md -> Home, row D4).
struct HomeHeadlineBlock: View {
    let stats: HomeStats
    let vehicle: Vehicle
    let onTypeIt: () -> Void

    var body: some View {
        if let headline = stats.headline {
            VStack(alignment: .leading, spacing: 6) {
                Text("Average consumption")
                    .font(.caption)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("homeHeadlineEyebrow")
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(ManualFillUpFormat.decimal(headline.value, fractionDigits: 1))
                        .font(.custom(AppFonts.dinCondensedBold, size: 68))
                        .foregroundStyle(Theme.Palette.ink)
                        .accessibilityIdentifier("homeHeadlineValue")
                        .accessibilityLabel(headlineValueVoiceOverLabel(headline))
                    Text(L10n.headlineUnit(vehicle.headlineUnit))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .tracking(0.4)
                        .accessibilityHidden(true)
                }
                labelLine(headline)
                provenanceLine
            }
        } else if stats.needsAnotherFullTank {
            VStack(alignment: .leading, spacing: 6) {
                d4Hint
                provenanceLine
            }
        }
    }

    /// RV.118: what the figure is made of - "6 fills · last 90 days · 4 full
    /// tanks" - or, under the floor, "Not enough data yet · 2 fills · 1 full
    /// tank". The numbers are the engine's own (`HomeStats.provenance`).
    @ViewBuilder
    private var provenanceLine: some View {
        if let provenance = stats.provenance {
            Text(L10n.headlineProvenance(provenance))
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("homeHeadlineProvenance")
        }
    }

    /// The hero figure's VoiceOver label: the value with its SPOKEN unit
    /// ("liters per 100 kilometers", never the "L/100km" a screen reader reads
    /// as "L one hundred k m") plus the derived trend (docs/DESIGN.md ->
    /// Accessibility floor). A nil trend is omitted, never "steady".
    private func headlineValueVoiceOverLabel(_ headline: Headline) -> String {
        let value = ManualFillUpFormat.decimal(headline.value, fractionDigits: 1)
        let unit = L10n.spokenHeadlineUnit(vehicle.headlineUnit)
        var parts = ["\(value) \(unit)"]
        if let trend = stats.headlineTrend { parts.append(L10n.trend(trend)) }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func labelLine(_ headline: Headline) -> some View {
        if stats.isFirstEstimate, case .firstEstimate = headline.label {
            // The same localized honest label Trends renders, from the same
            // function - Home and Trends can never disagree about the wording
            // (docs/SCHEMA.md -> HEADLINE; P1.10).
            Text(L10n.honestSpanLabel(headline.label))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
                .accessibilityIdentifier("homeFirstEstimateLabel")
        } else if let best = stats.bestThisYear {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.caption2.weight(.bold))
                Text("Best this year")
                    .font(.caption.weight(.semibold))
                Text(ManualFillUpFormat.decimal(best, fractionDigits: 1))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.Palette.ink)
            }
            .foregroundStyle(Theme.Palette.taillight)
            .accessibilityIdentifier("homeBestThisYear")
        }
    }

    private var d4Hint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("One more full tank and your consumption appears")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityIdentifier("homeD4Hint")
            Button("Type it", action: onTypeIt)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.action)
                .accessibilityIdentifier("homeD4CaptureButton")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .formCard()
    }
}

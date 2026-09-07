import SwiftUI
import TankbookCore

// MARK: - RV.106 the month divider's honest figure

/// The log-stream month divider, split into its own file so `HomeSections.swift`
/// stays under the lint ceiling (700). Same struct, same members - the three
/// divider methods live here because RV.106 grew them and they are one concern:
/// a month whose rows are still waiting on a rate must never print a bare `0 €`.
extension HomeRecentEntries {
    /// The month's divider: name on the left, the month's total spend in DIN on
    /// the right (docs/DESIGN.md); the name carries the year outside the current
    /// one (RV.89). One accessibility element, label a full localised phrase.
    ///
    /// The figure is exactly as honest as the data allows (RV.106): a month
    /// whose rows are still waiting on a rate never prints a bare `0 €`. A
    /// partial month (some rows converted) shows its known sum in DIN with the
    /// pending count beneath it; a month where no row has converted yet shows
    /// the pending phrase INSTEAD of a figure - the divider says why there is
    /// no number (hard rule 7).
    func monthDivider(_ section: LogStream.Section) -> some View {
        let monthName = HomeFormat.monthHeading(section.monthStart)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(monthName)
                .font(.caption)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 8)
            dividerFigure(section.total)
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: L10n.localize("%@ · %@"),
                                   monthName, dividerText(section.total)))
        .accessibilityIdentifier("logMonthDivider")
    }

    /// The divider's trailing figure slot. `.complete` is the number alone;
    /// `.partial` is the known sum in DIN with the pending phrase beneath it;
    /// `.pending` is the pending phrase alone - a figure slot that would read
    /// `0 €` is never built (RV.106).
    @ViewBuilder
    private func dividerFigure(_ total: LogStream.MonthTotal) -> some View {
        switch total {
        case .complete(let amount):
            Text(HomeFormat.spend(amount, symbol: currencySymbol))
                .font(.custom(AppFonts.dinAlternateBold, size: 16))
                .foregroundStyle(Theme.Palette.ink)
        case .partial(let amount, let pendingCount):
            VStack(alignment: .trailing, spacing: 1) {
                Text(HomeFormat.spend(amount, symbol: currencySymbol))
                    .font(.custom(AppFonts.dinAlternateBold, size: 16))
                    .foregroundStyle(Theme.Palette.ink)
                Text(L10n.pendingRates(pendingCount))
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        case .pending(let pendingCount):
            Text(L10n.pendingRates(pendingCount))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
    }

    /// The divider's full readout for the accessibility label: the month, the
    /// figure when one exists, and the pending phrase when the figure is
    /// partial or absent (hard rule 7 - the label never asserts a bare total
    /// the data cannot support).
    private func dividerText(_ total: LogStream.MonthTotal) -> String {
        switch total {
        case .complete(let amount):
            return HomeFormat.spend(amount, symbol: currencySymbol)
        case .partial(let amount, let pendingCount):
            return "\(HomeFormat.spend(amount, symbol: currencySymbol)) · \(L10n.pendingRates(pendingCount))"
        case .pending(let pendingCount):
            return L10n.pendingRates(pendingCount)
        }
    }
}

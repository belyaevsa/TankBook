import SwiftUI
import TankbookCore

// MARK: - RV.103 the whole-month reveal behind the preview

/// Scroll targets inside the log stream, for the DEBUG screenshot hook that
/// parks Home at the reveal seam (`-homeScrollLogReveal`). Kept beside the
/// reveal code that carries the seam.
enum HomeLogRevealAnchor {
    /// The load-more row's own view identity - the seam between the visible
    /// whole months and the hidden ones.
    static let seamID = "homeLogRevealSeam"
}

/// The visible slice of the log stream for a reveal state. Built over the
/// stream's whole months, so every month divider that renders sits above a
/// complete month (it sums exactly the rows beneath it - the divider-honesty
/// fence), and a purchase group (one collapsed row inside one month) is never
/// split by a page boundary.
struct HomeLogReveal {
    /// The whole months currently visible, newest first.
    let months: [LogStream.Section]
    /// Entries still hidden behind the reveal - what the load-more affordance
    /// counts (hard rule 7).
    let hiddenEntryCount: Int

    init(vehicle: Vehicle, entries: [any Entry],
         duplicateResolutions: Set<DuplicateDetector.PairKey>,
         pageCount: Int, initialRowCount: Int) {
        let stream = LogStream(vehicle: vehicle, entries: entries,
                               duplicateResolutions: duplicateResolutions)
        let pages = stream.revealPages(initialRowCount: initialRowCount,
                                       pageRowCount: initialRowCount)
        guard !pages.isEmpty else {
            months = []
            hiddenEntryCount = 0
            return
        }
        let shown = min(max(pageCount, 1), pages.count)
        months = pages.prefix(shown).flatMap(\.months)
        hiddenEntryCount = pages[shown - 1].hiddenEntryCount
    }
}

extension HomeRecentEntries {

    /// RV.106 month-divider and RV.103 reveal pieces live in this file so
    /// `HomeSections.swift` stays under the lint ceiling (700). Same struct,
    /// same members - the divider methods and the load-more row are one
    /// concern: the Log stream's honest, whole-month rendering.

    /// The F9 pending-rates footnote (kept here, not in `HomeSections.swift`,
    /// to hold that file under the lint ceiling). RV.111: the "Check for rates"
    /// action is a demand drain, and when the last demand pass left a pre-window
    /// row pending the footnote names the manual rate instead (`deadEnd`).
    var pendingRatesFootnote: some View {
        PendingRatesFootnote(count: pendingRateCount,
                             identifier: "homePendingRatesFootnote",
                             onCheck: onCheckRates,
                             deadEnd: PendingRatesFootnote.showsDeadEnd(entries))
    }

    /// The "Show N older entries" row, rendered as the last element of the
    /// visible log while the reveal has hidden months left (hard rule 7).
    /// Tapping reveals the next whole-month page; when the whole log is shown
    /// the row disappears. Carried in this extension file (not the struct's
    /// own) purely to keep `HomeSections.swift` under the lint ceiling.
    func loadMoreRow(_ hiddenEntryCount: Int) -> some View {
        Button {
            revealedPageCount += 1
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                Text(L10n.olderEntries(hiddenEntryCount))
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.Palette.action)
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("homeLogOlderButton")
        .id(HomeLogRevealAnchor.seamID)
    }

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

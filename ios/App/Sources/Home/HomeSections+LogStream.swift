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
    /// The excluded-entries footnote's view identity (RV.141), so the DEBUG
    /// screenshot hook can park Home at it (`-homeScrollToExcludedFootnote`).
    static let excludedFootnoteID = "homeExcludedFootnoteAnchor"
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
         stations: [Station],
         pageCount: Int, initialRowCount: Int) {
        let stream = LogStream(vehicle: vehicle, entries: entries,
                               duplicateResolutions: duplicateResolutions,
                               stations: stations)
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
    /// no number (hard rule 7). Every figure is stated in the currency its rows
    /// were recorded in, and a month whose known rows span currencies shows the
    /// per-currency breakdown rather than a bare cross-currency sum (RV.145).
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
    /// `.mixed` is the per-currency breakdown (RV.145 - a month whose known
    /// figures span home currencies has no bare total) with the pending phrase
    /// beneath it when rows still wait; `.pending` is the pending phrase alone -
    /// a figure slot that would read `0 €` is never built (RV.106).
    @ViewBuilder
    private func dividerFigure(_ total: LogStream.MonthTotal) -> some View {
        if case .pending(let pendingCount) = total {
            // A month where no row has converted: the pending phrase in place
            // of a figure (a slot that would read `0 €` is never built).
            Text(L10n.pendingRates(pendingCount))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        } else if let figure = HomeFormat.spend(total), let note = pendingNote(total) {
            // Partial (or mixed with rows still waiting): the figure with the
            // pending phrase beneath it - visibly partial, never a bare total.
            VStack(alignment: .trailing, spacing: 1) {
                Text(figure)
                    .font(.custom(AppFonts.dinAlternateBold, size: 16))
                    .foregroundStyle(Theme.Palette.ink)
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        } else if let figure = HomeFormat.spend(total) {
            // Complete (or a mixed month whose rows all converted): the figure
            // alone - the divider carries the total's own currency (RV.145).
            Text(figure)
                .font(.custom(AppFonts.dinAlternateBold, size: 16))
                .foregroundStyle(Theme.Palette.ink)
        }
    }

    /// The divider's full readout for the accessibility label: the month, the
    /// figure when one exists, and the pending phrase when the figure is
    /// partial or absent (hard rule 7 - the label never asserts a bare total
    /// the data cannot support).
    private func dividerText(_ total: LogStream.MonthTotal) -> String {
        switch total {
        case .pending(let pendingCount):
            return L10n.pendingRates(pendingCount)
        case .complete, .partial, .mixed:
            let figure = HomeFormat.spend(total) ?? ""
            if let note = pendingNote(total) {
                return "\(figure) · \(note)"
            }
            return figure
        }
    }

    /// The pending phrase a divider carries under a partial figure, or a mixed
    /// one that still has rows waiting; `nil` when the month is fully stated
    /// (`.complete`) or has no figure at all (`.pending` - the phrase is the
    /// whole slot there).
    private func pendingNote(_ total: LogStream.MonthTotal) -> String? {
        switch total {
        case .partial(_, _, let pendingCount):
            return L10n.pendingRates(pendingCount)
        case .mixed(_, let pendingCount):
            // A mixed month whose every member HAS converted is fully stated -
            // its breakdown is the whole truth and there is nothing waiting, so
            // the phrase would read "0 entries pending rates" beneath a
            // complete figure. `HomeFormat.groupPendingNote` guards the same
            // case for the group header (PJ.56); this is the divider's half.
            return pendingCount > 0 ? L10n.pendingRates(pendingCount) : nil
        case .complete, .pending:
            return nil
        }
    }
}

// MARK: - Log entry money figure

/// The trailing money figure on a log row (docs/DESIGN.md -> "Entry card
/// content"). Every amount renders with its currency's SYMBOL, converted or
/// not (RV.145, decided 2026-09-08): a converted entry shows its HOME amount
/// with the home currency's symbol ("71.02 €"); a rate-pending entry (F9) has
/// no home figure, so it shows the ORIGINAL amount with the ORIGINAL
/// currency's symbol - dimmed under its own identifier, the state the row's
/// footnote and the divider's pending phrase explain. The symbol travels with
/// the figure it belongs to, and a currency whose symbol is not distinct from
/// its code (CHF) falls back to the code - a money figure is never bare
/// (docs/DESIGN.md -> Money). The S8 backfill replaces a pending row with the
/// home figure the moment a rate lands.
struct LogEntryAmount: View {
    let money: Money

    var body: some View {
        if let homeAmount = money.homeAmount {
            Text(HomeFormat.entryAmount(homeAmount,
                                        symbol: AddVehicleSupport.moneySymbol(for: money.homeCurrency)))
                .font(.custom(AppFonts.dinAlternateBold, size: 16))
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityIdentifier("homeEntryAmount")
        } else {
            Text(HomeFormat.entryAmount(money.amount,
                                        symbol: AddVehicleSupport.moneySymbol(for: money.currency)))
                .font(.custom(AppFonts.dinAlternateBold, size: 16))
                .foregroundStyle(Theme.Palette.inkSoft)
                .accessibilityIdentifier("homeEntryAmountPending")
        }
    }
}

// MARK: - The month-total figure text (RV.145)

extension HomeFormat {
    /// The divider/vitals figure text for a month total (RV.145): every amount
    /// is rendered with the symbol of the currency it is DENOMINATED in - the
    /// one the total carries, never the vehicle's - so a figure and its marker
    /// cannot come from two different objects. A `.mixed` month (known figures
    /// spanning home currencies) renders its per-currency breakdown, never a
    /// bare cross-currency sum (hard rule 3). `nil` for a `.pending` month,
    /// which prints no figure at all - the pending phrase replaces it. Lives
    /// beside the divider (this file) so `HomeSections.swift` stays under the
    /// lint ceiling.
    static func spend(_ total: LogStream.MonthTotal) -> String? {
        switch total {
        case .complete(let amount, let currency), .partial(let amount, let currency, _):
            return spend(amount, symbol: AddVehicleSupport.moneySymbol(for: currency))
        case .mixed(let subtotals, _):
            return mixedSpend(subtotals)
        case .pending:
            return nil
        }
    }

    /// "1 432 € · 87 $" - a mixed month's per-currency breakdown (RV.145),
    /// each figure exact and paired with its own currency's marker, joined by
    /// the app's list separator. The parts are deliberately NOT summed: the
    /// month is mixed precisely because no single number states it honestly.
    static func mixedSpend(_ subtotals: [LogStream.SpendSubtotal]) -> String {
        subtotals
            .map { spend($0.amount, symbol: AddVehicleSupport.moneySymbol(for: $0.currency)) }
            .joined(separator: " · ")
    }

    // MARK: - Purchase-group header figure text (RV.166, PJ.56)

    /// The text a purchase-group header states for its own `total` - the same
    /// figure the month divider over the same members would state, in the
    /// row-level style the group's figures always used (two fraction digits,
    /// RV.166). `.complete` and `.partial` state their exact known sum;
    /// `.mixed` states its per-currency breakdown - each figure paired with its
    /// own currency's symbol (RV.145), never a summed cross-currency total
    /// (hard rule 3); `.pending` has no figure at all (`nil`) - the header
    /// prints the pending phrase in place of a number (PJ.56).
    static func groupFigure(_ total: LogStream.MonthTotal) -> String? {
        switch total {
        case .complete(let amount, let currency), .partial(let amount, let currency, _):
            return entryAmount(amount, symbol: AddVehicleSupport.moneySymbol(for: currency))
        case .mixed(let subtotals, _):
            return subtotals
                .map { entryAmount($0.amount,
                                   symbol: AddVehicleSupport.moneySymbol(for: $0.currency)) }
                .joined(separator: " · ")
        case .pending:
            return nil
        }
    }

    /// The pending phrase a purchase-group header carries for a `total` that is
    /// not fully stated (PJ.56) - the SAME phrase the month divider prints over
    /// the same members (RV.166): beneath the known figure for `.partial`,
    /// beneath the breakdown for a `.mixed` whose members still wait, and ALONE
    /// for `.pending`, where it is the whole slot (a `0 €` is never built -
    /// RV.106). `nil` for a fully-stated total: `.complete`, and a `.mixed`
    /// whose every member has converted.
    static func groupPendingNote(_ total: LogStream.MonthTotal) -> String? {
        switch total {
        case .partial(_, _, let pendingCount), .pending(let pendingCount):
            return L10n.pendingRates(pendingCount)
        case .mixed(_, let pendingCount):
            return pendingCount > 0 ? L10n.pendingRates(pendingCount) : nil
        case .complete:
            return nil
        }
    }
}

// MARK: - Purchase group header figure (RV.166, PJ.56)

extension HomeRecentEntries {

    /// The group header's trailing figure, from the group's OWN `total`
    /// classification (never recomputed here - hard rule 2). Every case states
    /// exactly what the month divider over the same members states (RV.166,
    /// PJ.56 - both reduce the receipt through the shared accumulator, so they
    /// must not explain the same classification differently):
    ///
    /// - `.complete` is the bare DIN total rendered with the currency it is
    ///   denominated in (RV.145 - never the vehicle's, which is how a euro
    ///   receipt once printed a dollar figure).
    /// - `.partial` prints that known sum with the pending phrase beneath it -
    ///   visibly partial, never a bare total that reads as the whole receipt
    ///   while a member still waits on a rate (RV.166).
    /// - `.mixed` (known lines spanning home currencies) prints the per-currency
    ///   breakdown - each figure exact with its own symbol, never a summed
    ///   cross-currency total (hard rule 3, RV.145) - with the pending phrase
    ///   beneath it when a member still waits.
    /// - `.pending` (no member has a home figure) prints the pending phrase in
    ///   place of a figure - a slot that would read `0 €` is never built
    ///   (RV.106), and the header says why instead of leaving blank space the
    ///   divider one row up already explains (PJ.56).
    ///
    /// The figures and notes come from `HomeFormat.groupFigure` /
    /// `HomeFormat.groupPendingNote` - the seams the L1 tests assert through,
    /// so a `.complete` / `.partial` rendering is unchanged to the pixel (a
    /// single-child `VStack` lays out its child at the child's own size).
    /// Kept in this file so `HomeSections.swift` stays under the lint ceiling.
    @ViewBuilder
    func groupTotalFigure(_ group: LogStream.LogGroup) -> some View {
        if let figure = HomeFormat.groupFigure(group.total) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(figure)
                    .font(.custom(AppFonts.dinAlternateBold, size: 16))
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityIdentifier("logGroupGrandTotal")
                if let note = HomeFormat.groupPendingNote(group.total) {
                    groupPendingText(note)
                }
            }
        } else if let note = HomeFormat.groupPendingNote(group.total) {
            groupPendingText(note)
        }
    }

    private func groupPendingText(_ note: String) -> some View {
        Text(note)
            .font(.caption2)
            .foregroundStyle(Theme.Palette.inkSoft)
            .accessibilityIdentifier("logGroupPendingRates")
    }
}

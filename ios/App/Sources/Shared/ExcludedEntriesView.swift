import SwiftUI
import TankbookCore

/// The list an "N entries excluded" footnote opens when more than one entry is
/// out of the derived figures (RV.141; docs/ERRORS.md -> Home, rows F9a and S2).
/// Reached from the Home Log and Trends footnotes; it shows the SELECTED car's
/// excluded entries - exactly the population the count counts (conflicts plus
/// the non-counting members of unresolved duplicate pairs) - each row naming
/// the entry, why it is out, and opening it on tap (hard rule 7: a row names
/// its next step, and the resolution the reason points at - fix the odometer or
/// date, Merge or Keep both - lives on the surfaces the tap reaches).
///
/// The count and this list MUST agree (RV.141): they are derived from the same
/// `ExcludedEntries.derive(in:duplicatePairs:)`, so a footnote that says N never
/// opens a list of fewer (or more) rows.
struct ExcludedEntriesView: View {
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(AppCarSelection.self) private var carSelection
    @State private var rows: [Row] = []
    @State private var didLoad = false

    struct Row: Identifiable, Equatable {
        let id: UUID
        let kind: LogStream.Kind
        let title: String
        let date: Date
        /// The fill quantity in the vehicle's own volume unit ("42.3 l"),
        /// already formatted (nil for non-fill entries).
        let litresText: String?
        /// The odometer in the vehicle's own distance unit ("122 800 km"),
        /// already formatted (nil when the entry has none).
        let odometerText: String?
        let reason: EntryExclusionReason
        /// The trailing money figure, already formatted with its currency's
        /// symbol (RV.145: a figure and its marker travel together).
        let amount: String?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if rows.isEmpty {
                    emptyState
                } else {
                    ForEach(rows) { row in
                        rowCard(row)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Theme.Palette.midnight)
        .task { await load() }
        .onChange(of: toastCenter.revision) { _, _ in
            // An edit saved (with or without a delta toast) may have resolved an
            // exclusion - the list reloads so a fixed conflict or resolved
            // duplicate leaves it, exactly as the flagged list behaves (RV.72).
            Task { await reload() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.title3)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("Nothing is excluded right now")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .formCard()
        .accessibilityIdentifier("excludedEntriesEmptyState")
    }

    private func rowCard(_ row: Row) -> some View {
        NavigationLink(value: Route.editEntry(row.id)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: reasonIcon(row.reason))
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.warn)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.Palette.ink)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if let amount = row.amount {
                                Text(amount)
                                    .font(.custom(AppFonts.dinAlternateBold, size: 16))
                                    .foregroundStyle(Theme.Palette.ink)
                                    .monospacedDigit()
                                    .accessibilityIdentifier("excludedEntryAmount")
                            }
                        }
                        Text(L10n.excludedReason(row.reason))
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("excludedEntryReason")
                        detailsLine(row)
                    }
                }
                .contentShape(Rectangle())
                .padding(.horizontal, Theme.Spacing.cardPadding)
                .padding(.vertical, 12)
            }
            .formCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("excludedEntryRow")
    }

    /// "42.3 l · 122 800 km · Sep 7" - the identity that lets the user find the
    /// row in the Log, in the car's own units. Segments wrap to a second line at
    /// large type instead of clipping (P6.13).
    private func detailsLine(_ row: Row) -> some View {
        SubtitleFlow(spacing: 3, lineSpacing: 2) {
            if let litresText = row.litresText {
                Text(litresText)
                    .monospacedDigit()
            }
            if let odometerText = row.odometerText {
                separator()
                Text(odometerText)
                    .monospacedDigit()
            }
            separator()
            Text(HomeFormat.day(row.date))
        }
        .font(.caption)
        .foregroundStyle(Theme.Palette.inkSoft)
    }

    @ViewBuilder
    private func separator() -> some View {
        Text("·")
            .foregroundStyle(Theme.Palette.inkSoft.opacity(0.6))
    }

    /// The row's reason is told apart by shape as well as text (docs/DESIGN.md
    /// accessibility floor): a conflict wears the amber triangle the Log badge
    /// uses, an unresolved duplicate the twin-document glyph of its card.
    private func reasonIcon(_ reason: EntryExclusionReason) -> String {
        switch reason {
        case .timelineConflict: "exclamationmark.triangle.fill"
        case .consumptionOutlier: "fuelpump.fill"
        case .unresolvedDuplicate: "doc.on.doc"
        }
    }

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        #if DEBUG
        // RV.141 pose: `-presentScreen excludedEntries` shows this list directly
        // (simctl cannot tap through the footnote), so a direct present seeds
        // the list's own data before the first query. Harmless when the list was
        // reached through the footnote - the seed is idempotent.
        ExcludedEntriesTestSeed.seedForDirectPresentIfRequested()
        #endif
        await reload()
    }

    /// Car-scoped, like the footnote count it answers: the selected vehicle's
    /// live entries, derived through the SAME `ExcludedEntries.derive` HomeStats
    /// uses, so the count that opened this list and the rows shown here are one
    /// population.
    private func reload() async {
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            guard let selected = carSelection.selectedVehicle(vehicles) else {
                rows = []
                return
            }
            let units = selected.units
            let entries = try repository.liveEntries(forVehicle: selected.id)
            let stations = try repository.liveStations()
            let resolutions = (try? repository.resolvedDuplicateKeys()) ?? []
            let pairs = DuplicateDetector.pairs(in: entries.compactMap { $0 as? FillUp },
                                                resolved: resolutions)
            let excluded = ExcludedEntries.derive(in: entries, duplicatePairs: pairs)
            rows = excluded.map { excludedEntry in
                let entry = entries.first { $0.id == excludedEntry.id }
                let litresText = (entry as? FillUp).map {
                    "\(ManualFillUpFormat.decimal($0.volumeL, fractionDigits: 1)) \(L10n.volumeUnit(units.volume))"
                }
                let odometerText = entry?.odometer.map {
                    "\(OdometerFormat.grouped($0)) \(L10n.distanceUnit(units.distance))"
                }
                return Row(id: excludedEntry.id,
                           kind: entry.map(Self.kind) ?? .expense,
                           title: entry.map { EntryTitle.text($0, stations: stations) }
                               ?? L10n.localize("Entry"),
                           date: excludedEntry.date,
                           litresText: litresText,
                           odometerText: odometerText,
                           reason: excludedEntry.reason,
                           amount: Self.amountText(entry))
            }
        } catch {
            rows = []
        }
    }

    // MARK: - Row identity

    private static func kind(_ entry: any Entry) -> LogStream.Kind {
        switch entry {
        case is FillUp: .fuel
        case is ChargeSession: .charge
        case is ServiceRecord: .service
        case is Expense: .expense
        default: .expense
        }
    }

    /// The trailing figure, rendered exactly as a Log row renders it: the HOME
    /// amount with the home currency's symbol when one exists, otherwise the
    /// ORIGINAL amount with the original symbol (a rate-pending row has no home
    /// figure - RV.145, the figure and its marker always travel together).
    private static func amountText(_ entry: (any Entry)?) -> String? {
        guard let money = entry?.money else { return nil }
        if let homeAmount = money.homeAmount {
            return HomeFormat.entryAmount(homeAmount,
                                          symbol: AddVehicleSupport.moneySymbol(for: money.homeCurrency))
        }
        return HomeFormat.entryAmount(money.amount,
                                      symbol: AddVehicleSupport.moneySymbol(for: money.currency))
    }
}

// MARK: - The reason captions

extension L10n {
    /// The reason caption on an excluded-entry row (RV.141; docs/ERRORS.md ->
    /// Home, rows F9a and S2). Two causes, two fixes: a timeline conflict is
    /// fixed by editing the odometer or the date; an unresolved duplicate by
    /// Merge or Keep both. Full localised phrases per language - never a shared
    /// stem with a reason noun spliced in.
    static func excludedReason(_ reason: EntryExclusionReason) -> String {
        switch reason {
        case .timelineConflict:
            String(localized: "Timeline conflict – check the odometer or date")
        case .consumptionOutlier:
            String(localized: "Unusual consumption – check the litres or odometer")
        case .unresolvedDuplicate:
            String(localized: "Possible duplicate – Merge or Keep both")
        }
    }
}

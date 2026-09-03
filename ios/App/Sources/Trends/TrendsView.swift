import SwiftUI
import TankbookCore

/// The Trends tab root content (P1.10), replacing the P1.1 placeholder: the
/// four-tile grid (consumption, cost/km, monthly spend, price/L) with honest
/// labels and the excluded-entry footnote (design/screens/TrendsB.dc.html,
/// docs/ERRORS.md -> Trends).
///
/// Every figure comes from `TrendsStats`, which derives them from the
/// Consumption engine - Trends does no arithmetic of its own (hard rule 2). A
/// tile with nothing honest to show is OMITTED, never "N/A", "–" or "0.0". The
/// consumption tile's label is the headline's honest span from the engine
/// ("last 3 months" / "last 5 months" / "first estimate · 1 fill cycle"),
/// rendered through the same localized function Home uses, so the two screens
/// never disagree about a number or its wording.
struct TrendsView: View {
    let presentSheet: (SheetRoute) -> Void

    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(AppCarSelection.self) private var carSelection
    @Environment(ReminderNotificationCoordinator.self) private var notificationCoordinator
    @State private var vehicle: Vehicle?
    @State private var entries: [any Entry] = []
    @State private var didSeed = false
    @State private var resolvedDuplicateKeys: Set<DuplicateDetector.PairKey> = []
    /// `notifications.monthlySummary` (default OFF, docs/SCHEMA.md) - the J8
    /// opt-in toggle that lives on Trends (docs/NOTIFICATIONS.md, "surfaced in
    /// Trends"). Loaded from the synced preference on every `load`, flipped
    /// through the notification coordinator, which persists and reschedules.
    @State private var monthlySummaryEnabled = false

    /// Derived, never stored (hard rule 2): recomputed from the current entries
    /// on every render - `TrendsStats` wraps `HomeStats`, so Home and Trends
    /// share the same engine values.
    private var stats: TrendsStats? {
        guard let vehicle else { return nil }
        return TrendsStats(vehicle: vehicle, entries: entries,
                           duplicateResolutions: resolvedDuplicateKeys)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                // The shared tab-root header (RV.21): same one-row title + gear
                // treatment as Log and Garage, so Settings sits in the same
                // place on every tab root.
                TabRootHeader(title: "Trends", titleIdentifier: "trendsHeaderTitle")
                content
                if vehicle != nil {
                    MonthlySummaryToggle(isOn: $monthlySummaryEnabled)
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            // Same as Home: the raised capture circle sits above the
            // `safeAreaInset` inset, so this clearance keeps the last tile
            // clear of it.
            .padding(.bottom, AppTabBar.contentBottomClearance)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.Palette.midnight)
        .task { await load() }
        .onChange(of: carSelection.selectedID) { _, _ in
            // Same selected car as Home: a switch reloads Trends too (P1.11).
            Task { await load() }
        }
        .onChange(of: toastCenter.revision) { _, _ in
            // An edit saved (with or without a delta toast) changed the data:
            // reload so the derived tiles reflect it immediately.
            Task { await load() }
        }
        .onChange(of: monthlySummaryEnabled) { _, enabled in
            Task { await notificationCoordinator.setMonthlySummaryEnabled(enabled) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vehicle == nil {
            TrendsNoCarLayout(presentSheet: presentSheet)
        } else if let stats {
            fullLayout(stats)
        }
    }

    @ViewBuilder
    private func fullLayout(_ stats: TrendsStats) -> some View {
        if stats.home.hasEntries {
            tileGrid(stats)
            if stats.home.excludedEntryCount > 0 {
                ExcludedEntriesFootnote(
                    count: stats.home.excludedEntryCount,
                    identifier: "trendsExcludedFootnote",
                    destination: stats.home.excludedEntryIDs.first.map(Route.editEntry))
                    .padding(.top, 4)
            }
            if stats.pendingRateCount > 0 {
                PendingRatesFootnote(count: stats.pendingRateCount,
                                     identifier: "trendsPendingRatesFootnote")
                    .padding(.top, 4)
            }
        } else {
            TrendsEmptyEntriesCard(onTypeIt: { presentSheet(.confirmManual) })
        }
    }

    // MARK: - The tile grid

    private static let twoColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private func tileGrid(_ stats: TrendsStats) -> some View {
        let symbol = AddVehicleSupport.currencySymbol(for: stats.vehicle.homeCurrency)
        return LazyVGrid(columns: Self.twoColumns, spacing: 10) {
            if let headline = stats.home.headline {
                StatTile(title: L10n.localize("Consumption"),
                         value: ManualFillUpFormat.decimal(headline.value, fractionDigits: 1),
                         identifier: "trendsConsumptionTile",
                         unit: TrendsFormat.consumptionUnit(stats.vehicle.headlineUnit),
                         caption: L10n.honestSpanLabel(headline.label),
                         series: stats.consumptionSeries.map(\.value),
                         seriesColor: Self.consumptionColor(stats.vehicle),
                         trend: stats.consumptionTrend)
            }
            if let costPerKm = stats.home.costPerKm, let spanMonths = stats.costPerKmSpanMonths {
                StatTile(title: L10n.localize("Cost / km"),
                         value: ManualFillUpFormat.decimal(costPerKm, fractionDigits: 2),
                         identifier: "trendsCostPerKmTile",
                         unit: symbol,
                         caption: L10n.honestSpanLabel(.window(months: spanMonths)),
                         series: stats.costSeries.map(\.value),
                         trend: stats.costTrend)
            }
            if let monthSpend = stats.home.monthSpend {
                StatTile(title: String(format: L10n.localize("Spend · %@"), TrendsFormat.month()),
                         value: HomeFormat.spend(monthSpend, symbol: symbol),
                         identifier: "trendsSpendTile",
                         series: stats.spendSeries.map(\.value),
                         seriesColor: Theme.Palette.taillight,
                         bars: true)
            }
            if let lastPrice = stats.home.lastUnitPrice {
                StatTile(title: L10n.localize("Price / L"),
                         value: ManualFillUpFormat.decimal(lastPrice, fractionDigits: 3),
                         identifier: "trendsPriceTile",
                         unit: symbol,
                         caption: TrendsFormat.priceCaption(series: stats.priceSeries),
                         series: stats.priceSeries.map(\.value))
            }
        }
    }

    /// Fuel figures render in `taillight`, electric in `headlight` - one accent
    /// per region, never both (docs/DESIGN.md palette rules).
    private static func consumptionColor(_ vehicle: Vehicle) -> Color {
        vehicle.powertrain == .ev ? Theme.Palette.headlight : Theme.Palette.taillight
    }

    // MARK: - Loading

    private func load() async {
        // Seeding runs once (idempotent anyway); the data reloads every time
        // the view appears or an edit revision lands, so Trends never shows
        // stale derived tiles after an entry change (hard rule 2).
        if !didSeed {
            didSeed = true
            #if DEBUG
            TrendsTestSeed.seedIfRequested()
            #endif
        }
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            guard let selected = carSelection.selectedVehicle(vehicles) else {
                return
            }
            self.vehicle = selected
            entries = try repository.liveEntries(forVehicle: selected.id)
            resolvedDuplicateKeys = (try? repository.resolvedDuplicateKeys()) ?? []
            monthlySummaryEnabled = (try? repository.livePreferences())?
                .notifications.monthlySummary ?? false
        } catch {
            AppLog.error(operation: "trends.load", category: .ui, error: error)
        }
    }
}

/// The J8 opt-in toggle (docs/NOTIFICATIONS.md: `notifications.monthlySummary`,
/// default off, surfaced in Trends). "Monthly summary" with a one-line caption
/// naming the format and the humane fire time; the figure inside the caption is
/// the doc's own copy, so the promise is visible before the first push arrives.
private struct MonthlySummaryToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Monthly summary")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("August: 212 € on the Volvo, on the 1st.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
        .tint(Theme.Palette.action)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .formCard()
        .accessibilityIdentifier("trendsMonthlySummaryToggle")
    }
}

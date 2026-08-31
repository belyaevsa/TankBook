import SwiftUI
import TankbookCore

/// The parts shelf (P3.2, docs/JOURNEYS.md J7b): `.parts` expenses not yet
/// installed in any service. The "on shelf" state is VISIBLE on purpose - a
/// silent shelf means forgotten parts, and the journey names that as the failure
/// mode. The list is derived (`PartsShelf.onShelf`), never stored.
struct PartsShelfView: View {
    @Environment(AppCarSelection.self) private var carSelection

    @State private var vehicle: Vehicle?
    @State private var shelfParts: [Expense] = []
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                if shelfParts.isEmpty {
                    emptyState
                } else {
                    ForEach(shelfParts, id: \.id) { part in
                        PartsShelfRow(expense: part, symbol: symbol)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.Palette.midnight)
        .task { await load() }
    }

    private var symbol: String {
        AddVehicleSupport.currencySymbol(for: vehicle?.homeCurrency ?? .eur)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("Parts you buy sit here until installed")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.center)
            Text("Log a part as an expense and it appears here, ready for the next service.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("partsShelfEmptyState")
    }

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        #if DEBUG
        PartsShelfTestSeed.seedIfRequested()
        #endif
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            guard let vehicle = carSelection.selectedVehicle(vehicles) else { return }
            self.vehicle = vehicle
            shelfParts = try repository.partsOnShelf(forVehicle: vehicle.id)
        } catch {
            AppLog.error(operation: "partsShelf.load", category: .ui, error: error)
        }
    }
}

/// One on-shelf part: title, its purchase provenance ("bought Mar 3 · 12.40 €")
/// and the visible "On shelf" badge.
struct PartsShelfRow: View {
    let expense: Expense
    let symbol: String

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
                Text(partSubtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            onShelfBadge
        }
        .padding(13)
        .formCard()
        .accessibilityIdentifier("partsShelfRow")
    }

    private var partSubtitle: String {
        let date = HomeFormat.day(expense.date)
        let amount = HomeFormat.entryAmount(expense.money?.amount ?? 0, symbol: symbol)
        return L10n.partBought(date: date, amount: amount)
    }

    private var onShelfBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "shippingbox.fill")
                .font(.caption2)
            Text("On shelf")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(Theme.Palette.inkSoft)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.Palette.inkSoft.opacity(0.12)))
        .overlay(Capsule().stroke(Theme.Palette.inkSoft.opacity(0.4), lineWidth: 1))
        .accessibilityIdentifier("partsShelfOnShelfBadge")
    }
}

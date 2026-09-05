import SwiftUI
import TankbookCore

/// The Log filtered to flagged entries (docs/SCREENMAP.md: Settings -->|"N
/// entries need a look"| Log). Reached from Settings' flagged row and, since
/// RV.66, directly from the sync chip's body when the account-wide flagged
/// count is non-zero.
///
/// This is a **view** of the entries carrying a `ConflictState` - the count is
/// derived and the screen resolves nothing (hard rule 8): tapping an entry
/// opens Edit entry, where the F9a inline discrepancy and its ranked fixes
/// live. A conflict is decidable only with the entry in front of the user.
///
/// The list is ACCOUNT-wide (it iterates every live vehicle), which is exactly
/// why each row names its car: a list reached from an account-wide signal mixes
/// entries from several cars, and a row whose title is a station name shared by
/// two cars tells the user nothing about WHERE the problem is (RV.66). The car
/// name is the first thing the row says.
struct FlaggedEntriesView: View {
    @State private var rows: [Row] = []
    @State private var didLoad = false

    struct Row: Identifiable {
        let id: UUID
        let title: String
        let subtitle: String
        /// The entry's date, kept for ordering (the subtitle is a string that
        /// leads with the car name and cannot be sorted by).
        let date: Date
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if rows.isEmpty {
                    emptyState
                } else {
                    ForEach(rows) { row in
                        NavigationLink(value: Route.editEntry(row.id)) {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Palette.warn)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.Palette.ink)
                                        .lineLimit(1)
                                    Text(row.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(Theme.Palette.inkSoft)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.Palette.inkSoft)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .formCard()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("flaggedEntryRow")
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Theme.Palette.midnight)
        .task { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.title3)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("Nothing needs a look")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("Any entry that needs your attention shows up here.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .formCard()
        .accessibilityIdentifier("flaggedEntriesEmptyState")
    }

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        do {
            let repository = try AppStore.repository()
            let stations = try repository.liveStations()
            let vehicles = try repository.liveVehicles()
            var flagged: [Row] = []
            for vehicle in vehicles {
                for entry in try repository.liveEntries(forVehicle: vehicle.id)
                where entry.conflict != .none {
                    flagged.append(Row(id: entry.id,
                                       title: Self.title(entry, stations: stations),
                                       subtitle: Self.subtitle(entry, vehicleName: vehicle.name),
                                       date: entry.date))
                }
            }
            rows = flagged.sorted { $0.date > $1.date }
        } catch {
            rows = []
        }
    }

    /// "Volvo V60 · Sep 3" - the car name first, so a list that mixes cars says
    /// where each problem lives before the date does. The list sorts by the
    /// entry's date (never this string), so the leading car name cannot disturb
    /// the order.
    private static func subtitle(_ entry: any Entry, vehicleName: String) -> String {
        "\(vehicleName) · \(HomeFormat.day(entry.date))"
    }

    private static func title(_ entry: any Entry, stations: [Station]) -> String {
        switch entry {
        case let fill as FillUp:
            if let stationID = fill.stationId,
               let name = stations.first(where: { $0.id == stationID })?.name {
                return name
            }
            return fill.fuelKind.fuelKindLabel
        case let charge as ChargeSession:
            return charge.provider ?? L10n.localize("Charge")
        case let service as ServiceRecord:
            return service.vendor ?? L10n.localize("Service")
        case let expense as Expense:
            return expense.title.isEmpty ? L10n.localize("Expense") : expense.title
        default:
            return L10n.localize("Entry")
        }
    }
}

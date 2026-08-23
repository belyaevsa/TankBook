import os
import SwiftUI
import TankbookCore

/// The Recently deleted screen (P1.7) - design/screens/RecentlyDeleted.dc.html.
/// A pushed route reached from Settings (docs/SCREENMAP.md).
///
/// This is where hard rule 8 - **nothing lost silently** - is visible: every
/// tombstone P1.6 wrote lives here with a countdown telling the user how long
/// they have to change their mind, and a Restore pill that clears it. Restore
/// routes through the repository's `restoreEntry`, so the entry re-enters the
/// Log AND the statistics (stats are derived - docs/SCHEMA.md, Recalculation on
/// edit - so the next recompute sees the live row again).
///
/// Two surfaces are sync-shaped and therefore fixture-driven until P4
/// (docs/SYNC.md S1/S4: the losing version is kept as the undo log): the
/// "Overwritten by sync" section (`-forceSyncOverwritten`) and the "removed on
/// iPad" device attribution (`-forceRemovedElsewhere`). See
/// RecentlyDeletedTestSeed.
struct RecentlyDeletedView: View {
    @Environment(AppToastCenter.self) private var toastCenter
    @State private var deleted: [DeletedEntry] = []
    @State private var vehicles: [UUID: Vehicle] = [:]
    @State private var stations: [Station] = []
    @State private var fixtures = RecentlyDeletedFixtures.fromLaunchArguments()
    @State private var showPurgeConfirm = false
    @State private var didLoad = false

    private static let log = Logger(subsystem: "app.tankbook", category: "recentlyDeleted")

    private var hasAnythingToDelete: Bool {
        !deleted.isEmpty || !fixtures.syncOverwritten.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                intro

                if deleted.isEmpty && fixtures.syncOverwritten.isEmpty {
                    emptyState
                } else {
                    deletedSection
                    if !fixtures.syncOverwritten.isEmpty {
                        syncOverwrittenSection
                    }
                    deleteAllNow
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Theme.Palette.midnight)
        .task { await load() }
        .alert("Delete everything here?",
               isPresented: $showPurgeConfirm) {
            Button("Delete all now", role: .destructive) { performPurgeAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every deleted entry is removed permanently. This can't be undone.")
        }
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Deleted entries stay here for 30 days, then are removed permanently.")
            Text("Entries here don't count in your statistics.")
        }
        .font(.subheadline)
        .foregroundStyle(Theme.Palette.inkSoft)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recentlyDeletedIntro")
    }

    // MARK: - Deleted entries

    private var deletedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(deleted) { entry in
                deletedRow(entry)
            }
        }
    }

    private func deletedRow(_ deletedEntry: DeletedEntry) -> some View {
        let device = fixtures.deletedOnDeviceByEntryID[deletedEntry.id]
        return HStack(spacing: 12) {
            Circle()
                .fill(dotColor(deletedEntry.entry))
                .frame(width: 9, height: 9)
                .opacity(0.55)
            VStack(alignment: .leading, spacing: 2) {
                Text(titleLine(deletedEntry.entry))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineLimit(2)
                Text(subtitle(deletedEntry, device: device))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft.opacity(0.72))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button {
                restore(deletedEntry.id)
            } label: {
                Text("Restore")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.Palette.headlight)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.clear))
                    .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recentlyDeletedRestoreButton")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recentlyDeletedRow")
    }

    // MARK: - Overwritten by sync (fixture until P4)

    private var syncOverwrittenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overwritten by sync")
                .font(.caption)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Theme.Palette.inkSoft)
                .padding(.top, 6)
            ForEach(fixtures.syncOverwritten) { row in
                syncOverwrittenRow(row)
            }
        }
    }

    private func syncOverwrittenRow(_ row: SyncOverwrittenRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(width: 17, height: 17)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineLimit(2)
                Text(row.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft.opacity(0.72))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            // Presentational until the real merge log feeds it (P4): the
            // Compare screen's diff UI is out of scope for P1.7.
            Button("Compare") {}
                .buttonStyle(.plain)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.Palette.headlight)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
                .accessibilityIdentifier("recentlyDeletedCompareButton")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recentlyDeletedSyncRow")
    }

    // MARK: - Delete all now

    private var deleteAllNow: some View {
        Button("Delete all now") {
            showPurgeConfirm = true
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.Palette.inkSoft)
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .accessibilityIdentifier("recentlyDeletedDeleteAllButton")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "trash.slash")
                .font(.title3)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("No deleted entries")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("Anything you delete stays here for 30 days, in case you change your mind.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .formCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recentlyDeletedEmptyState")
    }

    // MARK: - Row composition

    private func titleLine(_ entry: any Entry) -> String {
        let title = Self.title(entry, stations: stations)
        let quantity = quantityText(entry)
        let amount = amountText(entry)
        return [title, quantity, amount].compactMap { $0 }.joined(separator: " · ")
    }

    private func subtitle(_ entry: DeletedEntry, device: String?) -> String {
        let day = HomeFormat.day(entry.deletedAt)
        let daysLeft = String(localized: "\(TombstoneCountdown.daysRemaining(deletedAt: entry.deletedAt)) days left")
        var parts = [String(format: L10n.localize("Deleted %@"), day), daysLeft]
        if let device {
            parts.append(String(format: L10n.localize("removed on %@"), device))
        }
        return parts.joined(separator: " · ")
    }

    private func quantityText(_ entry: any Entry) -> String? {
        switch entry {
        case let fill as FillUp:
            let unit = vehicles[fill.vehicleId]?.units.volume ?? .l
            return "\(ManualFillUpFormat.decimal(fill.volumeL, fractionDigits: 1)) \(L10n.volumeUnit(unit))"
        case let charge as ChargeSession:
            return "\(ManualFillUpFormat.decimal(charge.energyKWh, fractionDigits: 0)) \(L10n.kWh)"
        default:
            return nil
        }
    }

    private func amountText(_ entry: any Entry) -> String? {
        guard let money = entry.money, let homeAmount = money.homeAmount else { return nil }
        let symbol = AddVehicleSupport.currencySymbol(for: money.homeCurrency)
        return HomeFormat.entryAmount(homeAmount, symbol: symbol)
    }

    private func dotColor(_ entry: any Entry) -> Color {
        switch entry {
        case is FillUp: return Theme.Palette.taillight
        case is ChargeSession: return Theme.Palette.headlight
        default: return Theme.Palette.inkSoft
        }
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

    // MARK: - Actions

    private func restore(_ id: UUID) {
        do {
            let repository = try AppStore.repository()
            if try repository.restoreEntry(id: id) {
                toastCenter.noteEntryChanged()
                reload()
            }
        } catch {
            Self.log.error("Restore failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func performPurgeAll() {
        do {
            let repository = try AppStore.repository()
            try repository.purgeAllTombstones()
            toastCenter.noteEntryChanged()
            reload()
        } catch {
            Self.log.error("Delete all failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Loading

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        RecentlyDeletedTestSeed.seedIfRequested()
        fixtures = RecentlyDeletedFixtures.fromLaunchArguments()
        reload()
    }

    private func reload() {
        do {
            let repository = try AppStore.repository()
            deleted = try repository.deletedEntries()
            let allVehicles = try repository.liveVehicles()
            var byID: [UUID: Vehicle] = [:]
            for vehicle in allVehicles { byID[vehicle.id] = vehicle }
            for vehicleID in deleted.map(\.vehicleId) where byID[vehicleID] == nil {
                if let vehicle = try? repository.vehicle(id: vehicleID) {
                    byID[vehicleID] = vehicle
                }
            }
            vehicles = byID
            stations = try repository.liveStations()
        } catch {
            Self.log.error("Recently deleted load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

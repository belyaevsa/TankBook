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
/// RV.104 adds the row's SECOND door: Accept. A flag on an entry from years
/// back can be a gap nobody remembers - a missing fill, a sold-and-rebought
/// car - that no fix can heal without inventing history. Accept records the
/// user's deliberate per-entry judgement (`FlagAcceptance`, keyed on the
/// entry's odometer + date) and clears the derived flag; the acceptance rides
/// the record's payload to the next device and the validator takes it as INPUT,
/// so a UI-only dismissal is never undone by the next sync. Editing the entry
/// later re-checks it (hard rule 8), and the acceptance stays visible and
/// reversible in Edit entry.
///
/// The list is ACCOUNT-wide (it iterates every live vehicle), which is exactly
/// why each row names its car: a list reached from an account-wide signal mixes
/// entries from several cars, and a row whose title is a station name shared by
/// two cars tells the user nothing about WHERE the problem is (RV.66). The car
/// name is the first thing the row says.
struct FlaggedEntriesView: View {
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(AppSync.self) private var sync
    @State private var rows: [Row] = []
    @State private var didLoad = false
    @State private var pendingAccept: Row?
    @State private var acceptReason = ""

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
        // RV.72: this list is a resolution surface (hard rule 8) - the row a
        // user fixes in Edit entry must leave the list when they come back. A
        // save bumps the toast-center revision (Edit entry, Inbox, Recently
        // deleted - every place that resolves or retires an entry), exactly as
        // Home/Trends/Garage reload on it; the .task one-shot cannot see that
        // pop-back because the pushed destination stays alive in the stack.
        .onChange(of: toastCenter.revision) { _, _ in
            Task { await reload() }
        }
        // RV.104: the Accept confirmation. The reason is OPTIONAL and kept - it
        // is what makes the decision readable a year later (the
        // `AnomalyDismissal` precedent). The accept itself is per entry and
        // deliberate; there is deliberately no bulk accept.
        .alert("Accept this entry?", isPresented: acceptAlertBinding) {
            TextField("Reason (optional)", text: $acceptReason)
            Button("Accept") { performAccept() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This entry will stop needing a look. Editing its odometer or date will re-check it.")
        }
        #if DEBUG
        // RV.72 test seam: resolves one flagged entry and bumps the revision
        // WHILE THE LIST STAYS ON SCREEN - the case the pop-back test cannot
        // reach, because a pop-back also fires `.onAppear` and would pass
        // against an appear-only reload. Found by the orchestrator's mutation:
        // swapping the revision observation for `.onAppear` left the whole suite
        // green, so the reason this fix is the right one was untested.
        .task { await FlaggedEntriesTestSeed.resolveOneInPlaceIfRequested(toastCenter) }
        #endif
    }

    /// A flagged row: the entry's own edit door on the left (the F9a fix
    /// surface, the same whole-row tap as before RV.104) and the RV.104 Accept
    /// door on the right - two peer paths, exactly as the row's problem has two
    /// honest resolutions: fix the facts, or say the facts are fine.
    private func rowCard(_ row: Row) -> some View {
        HStack(spacing: 0) {
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
                            .accessibilityIdentifier("flaggedEntrySubtitle")
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                .padding(.leading, 16)
                .padding(.trailing, 10)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("flaggedEntryRow")
            Button {
                acceptReason = ""
                pendingAccept = row
            } label: {
                Text("Accept")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
            .accessibilityIdentifier("flagAcceptButton")
        }
        .formCard()
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

    /// The alert binds through a separate bool so clearing `pendingAccept`
    /// dismisses it and cancelling needs no bookkeeping of its own.
    private var acceptAlertBinding: Binding<Bool> {
        Binding(get: { pendingAccept != nil },
                set: { if !$0 { pendingAccept = nil } })
    }

    /// The deliberate per-entry accept: stores the `FlagAcceptance` keyed to
    /// the entry's current facts and clears the derived conflict. The flagged
    /// count is derived (hard rule 2), so it drops by exactly this one row, and
    /// Settings' copy of it refreshes through `AppSync`.
    private func performAccept() {
        guard let row = pendingAccept else { return }
        pendingAccept = nil
        do {
            let repository = try AppStore.repository()
            let reason = acceptReason.trimmingCharacters(in: .whitespacesAndNewlines)
            if try repository.acceptFlag(id: row.id, reason: reason.isEmpty ? nil : reason) {
                toastCenter.noteEntryChanged()
                Task { await sync.refresh() }
            }
        } catch {
            AppLog.error(operation: "flaggedEntries.accept", category: .ui, error: error)
        }
    }

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        await reload()
    }

    /// The query, unguarded - called on the first appearance by `load()` and on
    /// every revision bump since (RV.72). Account-wide, live rows only.
    private func reload() async {
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

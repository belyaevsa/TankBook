import SwiftUI
import TankbookCore

/// RV.150 + RV.156 - the Stations list (docs/SCREENMAP.md -> Stations): every
/// station the account has ever logged at, reached from the Garage tab root.
/// Each row opens that station's settings - the screen where a coordinate the
/// app captured becomes visible and removable. Station management beyond this
/// (rename, merge, brands) is RV.115's fence; this screen lists, opens, and
/// (RV.156) adds by name.
///
/// RV.156: the list carries the add door too, so a station can be named where
/// stations are managed and not only mid-entry. The dashed "+ Add station" card
/// sits at the end in both states (the Garage's own "Add car" tile idiom), and
/// creation goes through the shared deterministic `createStation` rule - the
/// same minting the entry row uses, so the two doors can never disagree.
///
/// The row's caption states whether the station carries a recorded location, so
/// the per-station settings affordance is discoverable before the tap; the
/// caption is derived on read, never stored (hard rule 2).
struct StationsListView: View {
    @State private var stations: [Station] = []
    @State private var didLoad = false
    @State private var isAddingStation = false
    @State private var newStationName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if stations.isEmpty {
                    emptyState
                } else {
                    ForEach(stations, id: \.id) { station in
                        NavigationLink(value: Route.stationSettings(station.id)) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(station.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.Palette.ink)
                                        .lineLimit(1)
                                    Text(station.location != nil ? "Location saved"
                                                                : "No location")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Palette.inkSoft)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.Palette.inkSoft)
                            }
                            .padding(.horizontal, Theme.Spacing.cardPadding)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                            .formCard()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("stationListRow")
                        .accessibilityLabel(locationLabel(station))
                    }
                }
                addStationCard
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Theme.Palette.midnight)
        .task { await load() }
        .onAppear { if didLoad { reload() } }
        .alert("Add station", isPresented: $isAddingStation) {
            TextField("Station name", text: $newStationName)
                .accessibilityIdentifier("addStationNameField")
            Button("Cancel", role: .cancel) { newStationName = "" }
            Button("Add") { submitNewStation() }
        }
    }

    /// The add door (RV.156): the dashed "+ Add station" card at the end of the
    /// list, in both states - the empty state's copy points at it, and a list
    /// that already has rows can always gain one more.
    private var addStationCard: some View {
        Button {
            beginAddingStation()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
                Text("Add station")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Theme.Palette.hairline,
                                  style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("stationsAddStationButton")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse")
                .font(.title3)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("No stations yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("Stations appear here when you log a fill-up at one, or add one.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .formCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stationsEmptyState")
    }

    /// The row's VoiceOver label: the station's name (runtime) plus its
    /// location status through the catalogue - never an English literal riding
    /// a String expression (the P5.3 shape).
    private func locationLabel(_ station: Station) -> String {
        station.location != nil
            ? "\(station.name), \(L10n.localize("Location saved"))"
            : "\(station.name), \(L10n.localize("No location"))"
    }

    private func beginAddingStation() {
        newStationName = ""
        isAddingStation = true
    }

    /// Creates the named station through the shared deterministic rule (RV.156)
    /// and reloads so it appears in the list. An empty or whitespace-only name
    /// is a cancel; a name that exactly matches an existing station resolves to
    /// it and writes nothing, so the list never gains a duplicate row.
    private func submitNewStation() {
        let trimmed = newStationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isAddingStation = false
            return
        }
        do {
            let repository = try AppStore.repository()
            guard try repository.createStation(named: trimmed) != nil else {
                isAddingStation = false
                return
            }
            newStationName = ""
            isAddingStation = false
            reload()
        } catch {
            // A failed local write keeps the dialog open with the name intact -
            // the user can retry or cancel (hard rule 7).
            AppLog.error(operation: "station.create", category: .ui, error: error)
        }
    }

    // MARK: - Loading

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        #if DEBUG
        StationSettingsTestSeed.seedIfRequested()
        #endif
        reload()
    }

    private func reload() {
        do {
            let repository = try AppStore.repository()
            stations = try repository.liveStations()
        } catch {
            AppLog.error(operation: "stations.load", category: .ui, error: error)
        }
    }
}

import SwiftUI
import TankbookCore

/// RV.150 - the Stations list (docs/SCREENMAP.md -> Stations): every station
/// the account has ever logged at, reached from the Garage tab root. Each row
/// opens that station's settings - the screen where a coordinate the app
/// captured becomes visible and removable. Station management beyond this
/// (rename, merge, brands) is RV.115's fence; this screen only lists and opens.
///
/// The row's caption states whether the station carries a recorded location, so
/// the per-station settings affordance is discoverable before the tap; the
/// caption is derived on read, never stored (hard rule 2).
struct StationsListView: View {
    @State private var stations: [Station] = []
    @State private var didLoad = false

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
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Theme.Palette.midnight)
        .task { await load() }
        .onAppear { if didLoad { reload() } }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse")
                .font(.title3)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("No stations yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("Stations appear here when you log a fill-up at one.")
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

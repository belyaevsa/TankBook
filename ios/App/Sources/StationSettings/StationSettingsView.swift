import SwiftUI
import TankbookCore

/// RV.150 - the per-station settings screen (docs/SCREENMAP.md -> Station
/// settings). This is where the coordinate the fill-up save captures silently
/// becomes visible and removable (property 1 of the product decision: "silently"
/// is bounded to the capture moment; the value must be inspectable and
/// changeable where per-station settings live - the Garage). The screen shows
/// the station's recorded location and, when one exists, the control that
/// clears it. Clearing acts immediately - the coordinate is derived (a later
/// save at the station with a fix re-adopts it), so it is reversible, exactly
/// the asymmetry Vehicle detail's archive row already uses. Station management
/// beyond this (rename, merge, brands) is RV.115's fence, not this screen's.
///
/// `stationID` is nil only for a debug pose: the screen then falls back to the
/// first live station so screenshots have a deterministic target.
struct StationSettingsView: View {
    let stationID: UUID?

    @State private var station: Station?
    @State private var didLoad = false
    @State private var loadFailed = false
    @State private var isPickingBrand = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let station {
                    header(station)
                    section("Brand") { brandCard(station) }
                    section("Location") { locationCard(station) }
                    section("Favourite") { favouriteCard(station) }
                } else if loadFailed {
                    notFound
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.midnight)
        .sheet(isPresented: $isPickingBrand) {
            if let station {
                StationBrandPickerSheet(station: station) { setBrand($0) }
            }
        }
        .task { await load() }
        .onAppear { if didLoad { reload() } }
    }

    private func section(_ title: LocalizedStringKey,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionEyebrow(title)
            content()
        }
    }

    /// The station's own identity: the site's name in the card header - the
    /// full printed line that tells two forecourts of one chain apart (RV.180).
    private func header(_ station: Station) -> some View {
        Text(station.name)
            .font(.title3.weight(.bold))
            .foregroundStyle(Theme.Palette.ink)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.cardPadding)
            .formCard()
    }

    /// RV.115 / RV.180: the chain this site belongs to - what the Log row and
    /// the picker show. Matched from the vocabulary when the station was
    /// created, a DEFAULT the user changes here (hard rule 13); "No brand" is
    /// a first-class state, never a gap to fill.
    private func brandCard(_ station: Station) -> some View {
        Button {
            isPickingBrand = true
        } label: {
            HStack {
                Text(station.brand ?? L10n.localize("No brand"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(station.brand == nil ? Theme.Palette.inkSoft : Theme.Palette.ink)
                    .accessibilityIdentifier("stationSettingsBrandValue")
                Spacer(minLength: 8)
                Text("Change")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
            }
            .padding(Theme.Spacing.cardPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .formCard()
        .accessibilityIdentifier("stationSettingsBrandButton")
    }

    /// The brand write - the user's pick, kept forever: no pack update, sync
    /// merge or re-scan rewrites it (`setStationBrand`). Field NAME only in
    /// the log (hard rule 12).
    private func setBrand(_ brand: String?) {
        do {
            let repository = try AppStore.repository()
            if let station {
                _ = try loggedWrite(AppLog.shared, op: .update,
                                    entityType: Station.entityType,
                                    entityId: station.id, source: .manual,
                                    fieldsChanged: ["brand"]) {
                    try repository.setStationBrand(id: station.id, brand)
                }
            }
            reload()
        } catch {
            AppLog.error(operation: "stationSettings.setBrand", category: .ui, error: error)
        }
    }

    private func locationCard(_ station: Station) -> some View {
        VStack(spacing: 0) {
            FieldRow("Location") {
                if let coordinate = station.location {
                    Text(StationCoordinateText.string(coordinate))
                        .font(.custom(AppFonts.dinAlternateBold, size: 15))
                        .foregroundStyle(Theme.Palette.ink)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("stationSettingsLocationValue")
                } else {
                    Text("Not set")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .accessibilityIdentifier("stationSettingsLocationValue")
                }
            }
            if station.location != nil {
                CardDivider()
                // The removal control: immediate and reversible (a later save at
                // this station with a fix re-adopts the coordinate).
                Button {
                    clearLocation()
                } label: {
                    Text("Remove location")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stationSettingsRemoveLocation")
            }
        }
        .formCard()
    }

    /// PJ.55: the favourite control. `Station.favorite` is the one station field
    /// that cannot be inferred from use (the save stamp fills `lastUsedAt`,
    /// `defaults` and `location`), so it needs an explicit control: a favourite
    /// within 300 m is the ranking's first rung (PJ.19). The toggle is
    /// reversible - clearing writes `false` and persists like setting does -
    /// and never inferred from visit count (hard rule 13).
    private func favouriteCard(_ station: Station) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { station.favorite },
                set: { setFavorite($0) }
            )) {
                Text("Favourite station")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
            }
            .tint(Theme.Palette.action)
            .accessibilityIdentifier("stationSettingsFavoriteToggle")
            Text("A favourite within 300 m is proposed first when you log a fill-up.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.cardPadding)
        .formCard()
    }

    private var notFound: some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.slash")
                .font(.title3)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("Station not found")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .formCard()
    }

    private func clearLocation() {
        do {
            let repository = try AppStore.repository()
            if let station {
                _ = try loggedWrite(AppLog.shared, op: .update,
                                    entityType: Station.entityType,
                                    entityId: station.id, source: .manual) {
                    try repository.clearStationLocation(id: station.id)
                }
            }
            reload()
        } catch {
            AppLog.error(operation: "stationSettings.clearLocation", category: .ui, error: error)
        }
    }

    /// The favourite write, wrapped in the mutation pair so the diagnostics log
    /// answers "did the favourite write land?" without a domain value: the
    /// station id and the field NAME only (hard rule 12). A failed write leaves
    /// the toggle reverted by `reload()` and names its next step in the log.
    private func setFavorite(_ favorite: Bool) {
        do {
            let repository = try AppStore.repository()
            if let station {
                _ = try loggedWrite(AppLog.shared, op: .update,
                                    entityType: Station.entityType,
                                    entityId: station.id, source: .manual,
                                    fieldsChanged: ["favorite"]) {
                    try repository.setStationFavorite(id: station.id, favorite)
                }
            }
            reload()
        } catch {
            AppLog.error(operation: "stationSettings.setFavorite", category: .ui, error: error)
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
            let stations = try repository.liveStations()
            // A real push always names a station; nil is the debug pose, which
            // falls back to the first live station (the seed's own row).
            guard let target = stationID.flatMap({ id in
                stations.first { $0.id == id }
            }) ?? stations.first else {
                station = nil
                loadFailed = true
                return
            }
            station = target
            loadFailed = false
        } catch {
            AppLog.error(operation: "stationSettings.load", category: .ui, error: error)
        }
    }
}

/// Coordinates as display text. Runtime data, never localised (hard rule 10 is
/// about copy); formatted through a POSIX locale so the string is identical in
/// every device locale - the RU screenshots and the UI tests assert on it.
enum StationCoordinateText {
    static func string(_ coordinate: GeoCoordinate) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 4
        formatter.maximumFractionDigits = 4
        let latitude = formatter.string(from: NSNumber(value: coordinate.latitude)) ?? "\(coordinate.latitude)"
        let longitude = formatter.string(from: NSNumber(value: coordinate.longitude)) ?? "\(coordinate.longitude)"
        return "\(latitude), \(longitude)"
    }
}

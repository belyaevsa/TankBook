import SwiftUI
import TankbookCore

/// The brand picker (RV.115 / RV.180): the vocabulary ordered by relevance on
/// the device - the capture in hand, the brands the user already fuels at,
/// the device region, the server's hint, then the rest - with a search field
/// over every spelling, "No brand" as a first-class choice, and the user's
/// own word as a choice when nothing listed fits. The pick is written to the
/// station and is theirs permanently (hard rule 13).
struct StationBrandPickerSheet: View {
    let station: Station
    /// The currency the capture in hand is in, when the picker opens from a
    /// Confirm sheet; nil from the Garage.
    var currency: CurrencyCode?
    let onPicked: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var stations: [Station] = []

    private var brands: [StationBrand] { StationBrandRegistry.brands }

    private var ordered: [StationBrand] {
        let signals = StationBrandOrdering.signals(stations: stations, brands: brands, currency: currency)
        let all = StationBrandOrdering.ordered(brands, signals: signals)
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return all }
        let tokens = StationBrandMatcher.normalisedTokens(needle).joined(separator: " ")
        return all.filter { brand in
            ([brand.name] + brand.aliases).contains { spelling in
                StationBrandMatcher.normalisedTokens(spelling).joined(separator: " ").contains(tokens)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(title: L10n.localize("No brand"), selected: station.brand == nil,
                        identifier: "stationBrandNone") { pick(nil) }
                    let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !typed.isEmpty, !brands.contains(where: { $0.name == typed }) {
                        row(title: String(format: L10n.localize("Use “%@”"), typed),
                            selected: station.brand == typed, identifier: "stationBrandOwn") { pick(typed) }
                    }
                }
                Section {
                    ForEach(ordered) { brand in
                        row(title: brand.name, selected: station.brand == brand.name,
                            identifier: "stationBrand_\(brand.id)") { pick(brand.name) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.midnight)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Search brands"))
            .navigationTitle(Text("Brand"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                        .accessibilityIdentifier("stationBrandCancel")
                }
            }
        }
        .task {
            stations = (try? AppStore.repository().liveStations()) ?? []
        }
    }

    private func row(title: String, selected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.Palette.action)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.Palette.dash)
        .accessibilityIdentifier(identifier)
    }

    private func pick(_ brand: String?) {
        onPicked(brand)
        dismiss()
    }
}

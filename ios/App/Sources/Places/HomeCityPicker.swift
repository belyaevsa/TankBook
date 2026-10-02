import CoreLocation
import SwiftUI
import TankbookCore

/// Choosing where a car is usually kept (docs/SCHEMA.md -> Vehicle.homeCity):
/// a search over the bundled city dictionary, the car's country first, and an
/// "Other city" path for a place the dictionary does not hold - the typed name
/// is found by Apple's geocoder (network, no location permission). The choice
/// is the user's, stored on the car as its own copy (hard rule 13).
struct HomeCityPicker: View {
    let vehicleName: String
    /// The country to list first: the receipt's or the device region's.
    let countryHint: String?
    let current: HomeCity?
    let onPick: (HomeCity?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var showOther = false

    static var isRussian: Bool { Bundle.main.preferredLocalizations.first == "ru" }

    private var results: [City] {
        AppCities.dictionary.search(text, country: countryHint ?? current?.country)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { city in
                    Button {
                        onPick(HomeCity(city: city))
                        dismiss()
                    } label: {
                        cityRow(city)
                    }
                    .accessibilityIdentifier("homeCityResult_\(city.id)")
                }
                Button {
                    showOther = true
                } label: {
                    Label("Other city", systemImage: "magnifyingglass")
                        .foregroundStyle(Theme.Palette.ink)
                }
                .accessibilityIdentifier("homeCityOther")
                if current != nil {
                    Button {
                        onPick(nil)
                        dismiss()
                    } label: {
                        Text("No home city")
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                    .accessibilityIdentifier("homeCityClear")
                }
            }
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("City"))
            .navigationTitle(Text(String(format: L10n.localize("Where is %@ usually kept?"), vehicleName)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("homeCityCancel")
                }
            }
            .navigationDestination(isPresented: $showOther) {
                OtherCityForm(countryHint: countryHint ?? current?.country) { city in
                    onPick(city)
                    dismiss()
                }
            }
        }
    }

    private func cityRow(_ city: City) -> some View {
        HStack {
            Text(city.displayName(russian: Self.isRussian))
                .foregroundStyle(Theme.Palette.ink)
            Spacer(minLength: 8)
            Text(Self.countryName(city.country))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
    }

    static func countryName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}

/// A city the dictionary does not hold: typed, then found by the geocoder. A
/// miss says what to do next (hard rule 7) and keeps the typed name.
private struct OtherCityForm: View {
    let countryHint: String?
    let onFound: (HomeCity) -> Void

    @State private var name = ""
    @State private var searching = false
    @State private var failed = false

    var body: some View {
        Form {
            Section {
                TextField("City", text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("otherCityName")
            } footer: {
                if failed {
                    Text("Couldn't find that city. Check the spelling, or try again when you're online.")
                        .foregroundStyle(Theme.Palette.warn)
                        .accessibilityIdentifier("otherCityNotFound")
                }
            }
            Button {
                Task { await find() }
            } label: {
                if searching { ProgressView() } else { Text("Find") }
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || searching)
            .accessibilityIdentifier("otherCityFind")
        }
        .navigationTitle(Text("Other city"))
    }

    private func find() async {
        searching = true
        failed = false
        defer { searching = false }
        let typed = name.trimmingCharacters(in: .whitespaces)
        let query = countryHint.map { "\(typed), \(HomeCityPicker.countryName($0))" } ?? typed
        let placemark = try? await CLGeocoder().geocodeAddressString(query).first
        AppLog.shared.emit(HomeCityTyped(found: placemark != nil))
        guard let placemark, let location = placemark.location, let country = placemark.isoCountryCode else {
            failed = true
            return
        }
        onFound(HomeCity(name: placemark.locality ?? typed, country: country,
                         latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
    }
}

import SwiftUI
import TankbookCore

/// The car's home city on its details screen: shown, and changed or cleared at
/// any time through the same picker the one-time question uses (hard rule 13).
struct VehicleHomeCityRow: View {
    @Binding var homeCity: HomeCity?
    let vehicleName: String
    @State private var picking = false

    var body: some View {
        Button {
            picking = true
        } label: {
            HStack {
                Text("Home city")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer(minLength: 8)
                Text(valueText)
                    .font(.subheadline)
                    .foregroundStyle(homeCity == nil ? Theme.Palette.inkSoft : Theme.Palette.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.vertical, 12)
            .formCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vehicleDetailHomeCity")
        .sheet(isPresented: $picking) {
            HomeCityPicker(vehicleName: vehicleName, countryHint: homeCity?.country ?? Locale.current.region?.identifier,
                           current: homeCity) { homeCity = $0 }
        }
    }

    private var valueText: String {
        guard let homeCity else { return L10n.localize("Not set") }
        let name = homeCity.displayName(russian: HomeCityPicker.isRussian, dictionary: AppCities.dictionary)
        return "\(name), \(HomeCityPicker.countryName(homeCity.country))"
    }
}

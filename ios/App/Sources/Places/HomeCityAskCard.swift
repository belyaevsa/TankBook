import SwiftUI
import TankbookCore

/// The one-time home-city question on Home (docs/SCHEMA.md -> Vehicle.homeCity),
/// raised by the car's first scanned receipt: the city the receipt printed as a
/// one-tap answer, another city through the picker, or Not now - asked once,
/// never again for this car. The answer is stored on the car and editable in its
/// details at any time (hard rule 13).
struct HomeCityAskCard: View {
    let vehicle: Vehicle
    @State private var answered = false
    @State private var picking = false

    private var suggestion: City?? {
        guard !answered, vehicle.homeCity == nil,
              case .pending(let id)? = HomeCityAsk.state(for: vehicle.id) else { return nil }
        return .some(id.flatMap(AppCities.dictionary.city(id:)))
    }

    var body: some View {
        if let suggestion {
            card(suggestion)
                .sheet(isPresented: $picking) {
                    HomeCityPicker(vehicleName: vehicle.name,
                                   countryHint: suggestion?.country ?? Locale.current.region?.identifier,
                                   current: nil) { picked in
                        if let picked { save(picked, action: "chosen", suggested: suggestion != nil) }
                    }
                }
        }
    }

    private func card(_ suggestion: City?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(format: L10n.localize("Where is %@ usually kept?"), vehicle.name))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityIdentifier("homeCityAskTitle")
            Text("For tyre-change advice and the local rules. You can change it any time in the car's details.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let suggestion {
                    primary(Text(String(format: L10n.localize("Yes, %@"),
                                        suggestion.displayName(russian: HomeCityPicker.isRussian))),
                            identifier: "homeCityAskYes") {
                        save(HomeCity(city: suggestion), action: "confirmed", suggested: true)
                    }
                    secondary(Text("Another city"), identifier: "homeCityAskChoose") { picking = true }
                } else {
                    primary(Text("Choose city"), identifier: "homeCityAskChoose") { picking = true }
                }
                Spacer(minLength: 0)
                Button("Not now") { dismiss(suggested: suggestion != nil) }
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("homeCityAskNotNow")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .formCard()
    }

    private func primary(_ label: Text, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label.font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.midnight)
                .lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Theme.Palette.taillight))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func secondary(_ label: Text, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label.font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func save(_ city: HomeCity, action: String, suggested: Bool) {
        do {
            let repository = try AppStore.repository()
            var updated = vehicle
            updated.homeCity = city
            updated.updatedAt = Date()
            try loggedWrite(AppLog.shared, op: .update, entityType: Vehicle.entityType,
                            entityId: updated.id, source: .manual) { try repository.upsertVehicle(updated) }
            HomeCityAsk.set(.done, for: vehicle.id)
            AppLog.shared.emit(HomeCityAsked(action: action, suggested: suggested))
            answered = true
        } catch {
            AppLog.error(operation: "homeCity.save", category: .ui, error: error)
        }
    }

    private func dismiss(suggested: Bool) {
        HomeCityAsk.set(.done, for: vehicle.id)
        AppLog.shared.emit(HomeCityAsked(action: "dismissed", suggested: suggested))
        answered = true
    }
}

import SwiftUI
import TankbookCore

/// What a tire set is for: summer, winter or all-season (docs/SCHEMA.md ->
/// TireSet.season). Optional and the user's to set or clear - tapping the
/// chosen chip again clears it (hard rule 13).
struct TireSeasonCard: View {
    @Binding var season: TireSeason?

    var body: some View {
        HStack(spacing: 6) {
            Text("Season")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 8)
            ForEach(TireSeason.offered, id: \.self) { option in
                chip(option)
            }
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 10)
        .formCard()
    }

    private func chip(_ option: TireSeason) -> some View {
        let selected = season == option
        return Button {
            season = selected ? nil : option
        } label: {
            Text(Self.label(option))
                .font(.footnote.weight(selected ? .bold : .semibold))
                .foregroundStyle(selected ? Theme.Palette.ink : Theme.Palette.inkSoft)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? Theme.Palette.taillight.opacity(0.14) : Theme.Palette.dash))
                .overlay(Capsule().stroke(selected ? Theme.Palette.taillight : Theme.Palette.hairline,
                                          lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("tireSeason_\(option.rawValue)")
    }

    static func label(_ season: TireSeason) -> String {
        switch season {
        case .summer: L10n.localize("Summer")
        case .winter: L10n.localize("Winter")
        case .allSeason: L10n.localize("All-season")
        default: season.rawValue
        }
    }
}

import SwiftUI
import TankbookCore

/// The km / months **lifetime** fields on a service line item (PJ.22). Split
/// out of `EditEntryServiceItemRow` so that file stays under the linter's
/// length ceiling; the value it edits is the item's own `lifetime`, which is the
/// interval the post-save reminder offer counts from (J7). Both halves are
/// optional and independent, and an empty pair clears the lifetime rather than
/// storing a `Lifetime(km: nil, months: nil)`.
struct ServiceItemLifetimeFields: View {
    @Binding var lifetime: ServiceItem.Lifetime?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lifetime")
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(1.0)
                .foregroundStyle(Theme.Palette.inkSoft)
                .accessibilityIdentifier("editEntryServiceItemLifetimeLabel")
            HStack(spacing: 6) {
                field(value: km, unit: L10n.localize("km"),
                      identifier: "editEntryServiceItemLifetimeKm")
                Text("or")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
                field(value: months, unit: L10n.localize("months"),
                      identifier: "editEntryServiceItemLifetimeMonths")
            }
        }
    }

    private func field(value: Binding<String>, unit: String,
                       identifier: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            TextField("", text: value)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.custom(AppFonts.dinAlternateBold, size: 15))
                .foregroundStyle(Theme.Palette.ink)
                .frame(maxWidth: 78)
                .accessibilityIdentifier(identifier)
                .numericInput(value, kind: .integer)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.Palette.midnight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var km: Binding<String> {
        Binding(
            get: { lifetime?.km.map(OdometerFormat.grouped) ?? "" },
            set: { text in
                lifetime = Self.lifetime(km: Self.parsedInteger(text),
                                         months: lifetime?.months)
            }
        )
    }

    private var months: Binding<String> {
        Binding(
            get: { lifetime?.months.map(String.init) ?? "" },
            set: { text in
                lifetime = Self.lifetime(km: lifetime?.km,
                                         months: Self.parsedInteger(text))
            }
        )
    }

    /// The lifetime pair, or nil when both halves are blank - clearing both
    /// fields clears the lifetime.
    private static func lifetime(km: Int?, months: Int?) -> ServiceItem.Lifetime? {
        guard km != nil || months != nil else { return nil }
        return ServiceItem.Lifetime(km: km, months: months)
    }

    private static func parsedInteger(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Int(OdometerFormat.ungrouped(trimmed))
    }
}

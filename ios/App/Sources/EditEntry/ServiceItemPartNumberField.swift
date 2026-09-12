import SwiftUI
import TankbookCore

/// The optional **part number** on a service line item (PJ.61). Split out of the
/// item rows so the create and edit doors render one view, exactly as the
/// lifetime fields do; the value it edits is the item's own `partNumber`, the
/// catalogue identifier a part is reordered by (docs/SCHEMA.md). Free text and
/// optional - a blank field stores no part number rather than an empty string,
/// and clearing it clears the stored one.
struct ServiceItemPartNumberField: View {
    @Binding var partNumber: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Part number")
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(1.0)
                .foregroundStyle(Theme.Palette.inkSoft)
                .accessibilityIdentifier("editEntryServiceItemPartNumberLabel")
            TextField("", text: text)
                .font(.custom(AppFonts.dinAlternateBold, size: 15))
                .foregroundStyle(Theme.Palette.inkSoft)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.Palette.midnight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("editEntryServiceItemPartNumber")
        }
    }

    /// A blank field is an absent part number, never an empty string.
    private var text: Binding<String> {
        Binding(
            get: { partNumber ?? "" },
            set: { partNumber = $0.isEmpty ? nil : $0 }
        )
    }
}

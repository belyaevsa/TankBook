import SwiftUI
import TankbookCore

/// PU.29 (decision 7): a frame read as a pump display while the build is below
/// the pump-photo gate arrives at Confirm with its reading AND this notice -
/// the reading is a head start the user edits (hard rules 13 and 15), the
/// notice says how far to trust it and what to do (hard rule 7). Amber is
/// attention, never colour alone (hard rule 5); the words carry the meaning.
struct PumpDisplayAlphaNotice: View {
    let shown: Bool

    var body: some View {
        if shown {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.warn)
                Text(L10n.pumpDisplayAlphaMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityIdentifier("confirmPumpAlphaNotice")
        } else {
            EmptyView()
        }
    }
}

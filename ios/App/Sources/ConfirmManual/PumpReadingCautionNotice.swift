import SwiftUI
import TankbookCore

/// Decision 11 (docs/EXTRACTION.md): a pump reading the law committed without being
/// able to check it fully. The fields stay pre-filled and editable (hard rule 13);
/// this line says what went unchecked and what to look at (hard rule 7). Amber
/// is attention, and the words carry the meaning (hard rule 5).
struct PumpReadingCautionNotice: View {
    let caution: PumpReadingCaution?

    var body: some View {
        if let message {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.warn)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityIdentifier("confirmPumpCautionNotice")
        } else {
            EmptyView()
        }
    }

    private var message: String? {
        switch caution {
        case .shownPriceDiffers(let shown, let implied):
            return L10n.pumpShownPriceDiffersMessage(shown: Self.price(shown), implied: Self.price(implied))
        case nil:
            return nil
        }
    }

    private static func price(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(2...3)))
    }
}

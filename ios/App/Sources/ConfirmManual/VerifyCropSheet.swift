import SwiftUI
import TankbookCore

// MARK: - Focus

/// Which ConfirmManual field holds focus (drives the cyan underline).
enum ManualFillUpFocus: Hashable {
    case total, liters, pricePerL, odometer

    /// The pump-card figure this focus targets, if any (the odometer is not
    /// part of the three-number card, so it is not in the confidence set).
    var mathField: ManualFillUpMath.Field? {
        switch self {
        case .total: return .total
        case .liters: return .volume
        case .pricePerL: return .unitPrice
        case .odometer: return nil
        }
    }
}

// MARK: - Tap-to-verify crop sheet (P2.3)

/// One field's crop, presented by the sheet's `.sheet(item:)`.
struct VerifyCrop: Identifiable {
    let field: ManualFillUpMath.Field
    let evidence: CropEvidence

    var id: String { field.rawValue }
}

/// The tap-to-verify sheet: the crop of the source image a pre-filled value
/// came from, so the user can check it without leaving the Confirm sheet. The
/// evidence is dumb geometry + image; when no crop is attached the verify
/// affordance is simply absent (degrade to no-op, never a dead affordance).
struct VerifyCropSheet: View {
    @Environment(\.dismiss) private var dismiss
    let evidence: CropEvidence

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.midnight.ignoresSafeArea()
                VStack(spacing: 16) {
                    if let image = evidence.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 420)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.Palette.taillight, lineWidth: 2)
                            )
                    }
                    Text("From the receipt photo")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .accessibilityIdentifier("verifyCropCaption")
                }
                .padding(Theme.Spacing.screenMargin)
            }
            .navigationTitle("Check the value")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("verifyCropDoneButton")
                }
            }
        }
    }
}

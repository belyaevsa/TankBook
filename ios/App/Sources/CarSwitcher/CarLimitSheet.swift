import SwiftUI
import TankbookCore

/// The free-tier car-limit sheet (P1.11, docs/ERRORS.md -> Car switcher /
/// Garage, the row's only state): presented when "Add car" is tapped at the
/// cap. Copy verbatim from the doc, all three next steps present and
/// reachable. This is the ONLY place monetization may appear in the app
/// (hard rule 5) - existing cars are never locked, the cap only refuses adds
/// (the anti-CarScope rule, docs/COMPETITORS.md), and the sheet is never
/// shown mid-capture.
struct CarLimitSheet: View {
    /// "Archive a car" - the way to free a slot. Leads to the vehicle detail
    /// that will hold archiving (P1.12).
    let onArchive: () -> Void
    /// "Pro" - the paywall (P6). Present and reachable now, real later.
    let onPro: () -> Void
    /// Cancel: dismiss, everything intact.
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "car")
                .font(.system(size: 24))
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(width: 52, height: 52)
                .background(Theme.Palette.dash)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.Palette.hairline, lineWidth: 1))
                .padding(.top, 16)

            Text("Free keeps up to 3 cars. Archive one, or go Pro.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .accessibilityIdentifier("carLimitMessage")

            VStack(spacing: 8) {
                Button(action: onArchive) {
                    Text("Archive a car")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.Palette.midnight)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.Palette.taillight)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("carLimitArchiveButton")

                Button(action: onPro) {
                    Text("Pro")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.Palette.dash)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13)
                            .stroke(Theme.Palette.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("carLimitProButton")

                Button("Cancel", action: onCancel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
                    .accessibilityIdentifier("carLimitCancelButton")
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.midnight)
    }
}

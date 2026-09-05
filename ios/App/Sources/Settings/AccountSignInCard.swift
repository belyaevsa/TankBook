import SwiftUI
import TankbookCore

/// The signed-out account card's issue branch (RV.58, PR.1): the revoked-device
/// and session-expired cards share the whole shape - warn icon, one message
/// naming that nothing local was lost, and a single "Sign in" next step (hard
/// rule 7: never "update the app"). Extracted into its own file so SettingsView
/// stays inside the lint budget; the two cards differ only in copy and
/// identifiers.
struct AccountSignInCard: View {
    let message: String
    let cardIdentifier: String
    let buttonIdentifier: String
    /// The RV.22 chip's Settings scroll target, or nil for the auth-expired
    /// card (which sits under the account card's own `.account` target).
    let scrollTarget: SettingsScrollTarget?
    let signIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Palette.warn)
                    .padding(.top, 1)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.ink)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Button("Sign in", action: signIn)
                .buttonStyle(.plain)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.Palette.action)
                .accessibilityIdentifier(buttonIdentifier)
        }
        .padding(14)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(cardIdentifier)
        .id(scrollTarget)
    }
}

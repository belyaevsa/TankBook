import SwiftUI
import TankbookCore

/// The non-dismissible `.required` notice (P6.18b, docs/CONFIG.md -> "App
/// version and the update notice"). Rendered on the **server-backed surfaces
/// only** - sync, cloud extract, import parse - and never anywhere else: under
/// `.required` the user can still log, edit, view, compute and export every
/// entry, offline and indefinitely (hard rule 1). This notice is a pause
/// notice, not a lock.
///
/// It names its next step (hard rule 7): the copy is local and constant, and
/// the destination is the App Store page built from a compiled-in app id. With
/// no app id - the situation today - the button is simply absent: no dead
/// affordance, no placeholder URL, mirroring the marketing site's
/// `apple-itunes-app` gate.
struct UpdateRequiredNotice: View {
    @Environment(AppConfigService.self) private var config

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.down.app")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Palette.warn)
                    .padding(.top, 1)
                Text(L10n.updateRequiredMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.ink)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if let url = config.appStoreURL {
                Link(destination: url) {
                    Text("Update in the App Store")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.Palette.action)
                }
                .accessibilityIdentifier("updateRequiredButton")
            }
        }
        .padding(14)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("updateRequiredNotice")
    }
}

/// The dismissible `.recommended` row in Settings -> About (P6.18b): quiet
/// information, never an interruption. Dismissing hides it for the session
/// (it is information, not a gate - the requirement withholds nothing). The
/// App Store button renders only when an app id exists.
struct UpdateRecommendedRow: View {
    @Environment(AppConfigService.self) private var config
    @State private var isDismissed = false

    var body: some View {
        if !isDismissed {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.down.app")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Palette.action)
                        .padding(.top, 1)
                    Text("A newer version of Tankbook is available.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button {
                        isDismissed = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Palette.inkSoft)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Theme.Palette.dash))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("updateRecommendedDismiss")
                }
                if let url = config.appStoreURL {
                    Link(destination: url) {
                        Text("Update in the App Store")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.Palette.action)
                    }
                    .accessibilityIdentifier("updateRecommendedButton")
                }
            }
            .padding(14)
            .formCard()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("updateRecommendedRow")
        }
    }
}

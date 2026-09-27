import SwiftUI
import TankbookCore

/// The user's theme choice (Settings -> Appearance). `system` follows iOS's
/// own light/dark setting and is the default; `dark` and `light` pin the
/// app's theme whatever the system says. Per device, like the language.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    /// The `UserDefaults` key the choice lives under (`@AppStorage`). A launch
    /// argument `-tankbook.appearance light` overrides it for a UI test or a
    /// screenshot.
    static let storageKey = "tankbook.appearance"

    var id: String { rawValue }

    /// The scheme the window is pinned to; nil follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .system: "Match the system"
        case .dark: "Dark"
        case .light: "Light"
        }
    }
}

/// Pins the window to the user's theme choice. Applied inside `AppRootView`,
/// never on the `App`: a stored value read there re-evaluates the scene on
/// every change and constructs the root view again, whose `init` does one-time
/// setup.
struct AppearanceScheme: ViewModifier {
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system

    func body(content: Content) -> some View {
        content.preferredColorScheme(appearance.colorScheme)
    }
}

/// The Settings row: the current choice, and a menu of the three.
struct AppearanceRow: View {
    @Binding var selection: AppearancePreference

    var body: some View {
        Menu {
            Picker("Appearance", selection: $selection) {
                ForEach(AppearancePreference.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Appearance")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer(minLength: 8)
                Text(selection.label)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("settingsAppearanceValue")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("settingsAppearanceRow")
    }
}

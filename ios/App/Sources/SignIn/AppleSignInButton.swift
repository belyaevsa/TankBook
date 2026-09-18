import AuthenticationServices
import SwiftUI

/// Apple's own Sign in with Apple control, wrapped so `SignInView` can keep
/// its one `startSignIn(provider:)` path (the flow, not the button, runs the
/// `ASAuthorizationController`). The system control is what the Sign in with
/// Apple HIG requires and it draws the legible pairing in both schemes: black
/// on light, white on dark. Its title is Apple's, localised by the system, so
/// it is not a catalog string (hard rule 10 covers our copy, not Apple's).
struct AppleSignInButton: UIViewRepresentable {
    static let cornerRadius: CGFloat = 14
    static let height: CGFloat = 50

    var action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    /// The control's style is fixed at init, so the view carries the scheme
    /// in its identity and SwiftUI rebuilds it on a switch.
    static func style(for scheme: ColorScheme) -> ASAuthorizationAppleIDButton.Style {
        scheme == .dark ? .white : .black
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: .signIn,
            authorizationButtonStyle: Self.style(for: colorScheme))
        button.cornerRadius = Self.cornerRadius
        button.accessibilityIdentifier = "signInAppleButton"
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = isEnabled
        button.alpha = isEnabled ? 1 : 0.5
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

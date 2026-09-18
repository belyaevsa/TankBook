import AuthenticationServices
import SwiftUI
import XCTest
@testable import Tankbook

/// The Sign in with Apple control must contrast with the sheet in BOTH
/// schemes: the light sheet takes Apple's black button, the dark sheet the
/// white one. The named mutation - either arm returning the other style, or a
/// single style for both - fails here, which is the white-on-white light
/// button App Review saw.
final class AppleSignInButtonStyleTests: XCTestCase {

    func testLightSchemeTakesTheBlackButton() {
        XCTAssertEqual(AppleSignInButton.style(for: .light), .black)
    }

    func testDarkSchemeTakesTheWhiteButton() {
        XCTAssertEqual(AppleSignInButton.style(for: .dark), .white)
    }

    @MainActor
    func testTheControlCarriesTheIdentifierTheUISuitesTap() {
        // A representable is only materialised once its host is in a window.
        let host = UIHostingController(rootView: AppleSignInButton(action: {}))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 60))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let control = firstAppleButton(in: host.view)
        XCTAssertNotNil(control, "the system control is not in the hierarchy")
        XCTAssertEqual(control?.accessibilityIdentifier, "signInAppleButton")
    }

    private func firstAppleButton(in view: UIView) -> ASAuthorizationAppleIDButton? {
        if let button = view as? ASAuthorizationAppleIDButton { return button }
        for child in view.subviews {
            if let found = firstAppleButton(in: child) { return found }
        }
        return nil
    }
}

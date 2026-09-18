import XCTest

/// PR.20 - the silent sync nudge's registration (docs/NOTIFICATIONS.md). The
/// simulator has no APNs, so `-seedPushToken` hands the app the token APNs
/// would have; the sign-in stub transport acknowledges the PUT. What is
/// asserted: a guest launch sends nothing, and the PUT lands right after a
/// seeded sign-in - the row is per account-device, so the sign-in is what
/// triggers it.
@MainActor
final class PushTokenUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testThePushTokenIsSentAfterSignInAndNotBefore() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-clearSessionAtLaunch",
                               "-presentScreen", "settings", "-seedSettingsLocalLog",
                               "-signInStubAuth", "-signInSyncStub",
                               "-seedPushToken", "0a1b2c3d4e5f"]
        app.launch()

        let signIn = app.buttons["settingsSignInButton"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10), "the guest Settings card is on screen")
        XCTAssertFalse(app.descendants(matching: .any)["pushTokenRegistered"].exists,
                       "a guest has no account row, so no token goes up")

        signIn.tap()
        let apple = app.buttons["signInAppleButton"]
        XCTAssertTrue(apple.waitForExistence(timeout: 10))
        apple.tap()

        XCTAssertTrue(app.descendants(matching: .any)["pushTokenRegistered"].waitForExistence(timeout: 20),
                      "the push-token PUT must be acknowledged right after the seeded sign-in")
    }
}

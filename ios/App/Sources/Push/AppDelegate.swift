import TankbookCore
import UIKit

/// PR.20: the APNs seam (docs/NOTIFICATIONS.md "silent sync nudge"). Three
/// callbacks and nothing else: the device token (handed to `AppPush`, which
/// decides whether the server needs it), a registration failure (a warning -
/// the device keeps polling, hard rule 1), and a silent push (one
/// opportunistic sync cycle, then the system's completion). No payload field
/// is read beyond `content-available` - the nudge says only "pull".
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = PushTokenRegistration.hex(deviceToken)
        Task { @MainActor in AppPush.shared.tokenReceived(hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Reason code only (a missing aps-environment, no network): the
        // device falls back to foreground polling and nothing is shown.
        AppLog.warning(operation: "push.register", category: .sync, reason: "registration_failed")
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await AppPush.shared.handleSilentPush()
    }
}

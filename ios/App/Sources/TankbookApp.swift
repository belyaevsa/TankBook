import SwiftUI

@main
struct TankbookApp: App {
    /// PR.20: the UIKit delegate the APNs callbacks land on - SwiftUI's `App`
    /// has no seam for the device token or a silent push.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

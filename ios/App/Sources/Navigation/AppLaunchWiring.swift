import Foundation

/// The launch-time wiring of the app's network-facing services, kept out of
/// `AppRootView` (which sits at the linter's type-body ceiling): the path
/// monitor reaches the prefetch and the upload gate, and the push seam gets
/// its nudge and its registration.
@MainActor
enum AppLaunchWiring {
    static func attach(pathMonitor: AppPathMonitor, sync: AppSync) {
        BlobPrefetchService.shared.attach(pathMonitor)
        SyncService.attach(pathMonitor)
        // PR.20: a silent nudge runs the same opportunistic cycle the
        // foreground runs; the token goes up when a session exists.
        AppPush.shared.onNudge = { await sync.runOpportunisticSync() }
        AppPush.shared.registerIfSignedIn()
    }
}

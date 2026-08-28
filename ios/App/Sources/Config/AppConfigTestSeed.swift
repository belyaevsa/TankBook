import Foundation
import TankbookCore

/// DEBUG/test seeding for the update-requirement surface (P6.18b). Launch
/// arguments:
///
///     -configAppUpdate <minSupportedVersion> <latestVersion>
///
/// applies the thresholds through the core store's DEBUG-only debug layer, so
/// the requirement is DERIVED exactly as a real signed document would derive
/// it - thresholds + the injected running version - never a forced `.required`
/// that could bypass the derivation. Combined with the running-version and
/// app-store-id overrides in `AppConfigService.make`, a UI test or screenshot
/// can pin any of the three requirements:
///
///   `.none`:        no `-configAppUpdate` argument
///   `.recommended`: `-configAppUpdate 1.2.0 1.4.0 -configRunningVersion 1.3.0`
///   `.required`:    `-configAppUpdate 1.2.0 1.4.0 -configRunningVersion 1.0.0`
///
/// Compiled out of release builds: this cannot ship.
#if DEBUG
enum AppConfigTestSeed {
    static func seedIfRequested(store: ConfigStore,
                                arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let index = arguments.firstIndex(of: "-configAppUpdate"),
              arguments.indices.contains(index + 2),
              let minSupported = AppVersion(arguments[index + 1]),
              let latest = AppVersion(arguments[index + 2]) else { return }
        var override = DebugConfigOverride()
        override.appUpdate = ConfigDocument.AppUpdateNotice(
            minSupportedVersion: minSupported,
            latestVersion: latest
        )
        store.setDebugOverride(override)
    }
}
#endif

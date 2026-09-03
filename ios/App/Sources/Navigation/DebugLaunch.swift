import Foundation

/// DEBUG-only launch-argument navigation for screenshotting and UI tests:
/// `-presentScreen <route>` presents a screen directly at launch, so a
/// sheet-based screen can be screenshotted without a UI test driving a tap
/// (`simctl` cannot tap, so ConfirmManual needed a UI test just to open).
///
/// Folds in the old `-openManualForm` flag - exactly `-presentScreen
/// confirmManual` - which stays working for anything that depends on it.
/// Compiled out of release builds: this cannot ship.
#if DEBUG
enum DebugLaunch {
    struct Request {
        var sheet: SheetRoute?
        var route: Route?
        var modal: ModalRoute?
    }

    static func resolve(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Request {
        if arguments.contains("-openManualForm") {
            return Request(sheet: .confirmManual, route: nil, modal: nil)
        }
        guard let index = arguments.firstIndex(of: "-presentScreen"),
              arguments.indices.contains(index + 1) else {
            return Request(sheet: nil, route: nil, modal: nil)
        }
        let name = arguments[index + 1]
        if let sheet = SheetRoute(rawValue: name) {
            return Request(sheet: sheet, route: nil, modal: nil)
        }
        if let modal = ModalRoute(rawValue: name) {
            return Request(sheet: nil, route: nil, modal: modal)
        }
        return Request(sheet: nil, route: routes[name], modal: nil)
    }

    /// `-presentScreen` names for pushed routes (SheetRoutes match their own
    /// raw values directly). The map keeps the lookup linear instead of a long
    /// switch.
    private static let routes: [String: Route] = [
        "settings": .settings,
        "about": .about,
        "reminders": .reminders,
        "reminderForm": .reminderForm(nil),
        "recentlyDeleted": .recentlyDeleted,
        "editEntry": .editEntry(nil),
        "vehicleDetail": .vehicleDetail(nil),
        "tireSets": .tireSets,
        "tireSetForm": .tireSetForm(nil),
        "addVehicle": .addVehicle,
        "accountDevices": .accountDevices,
        "paywall": .paywall,
        "importWizard": .importWizard,
        "flaggedEntries": .flaggedEntries,
        "inbox": .inbox
    ]
}
#endif

import Foundation
import TankbookCore

/// The app's one logging facade (docs/LOGGING.md §4-§5). Every view logs
/// through this instance, built from `TankbookLog.makeDefault`, so every line
/// rides the `live.belyaev.tankbook` subsystem that the diagnostics export
/// reads. A raw `os.Logger` is invisible to that export (docs/LOGGING.md §5),
/// which is why constructing one outside Logging/ is a SwiftLint error.
///
/// `deviceId` comes from the Keychain session (docs/SECURITY.md) when a session
/// exists, else it stays nil - Safe either way, and the facade still emits.
enum AppLog {
    static let shared = TankbookLog.makeDefault(deviceId: Self.deviceId())

    /// Emits a typed app error. `operation` is a stable code (e.g. `home.load`);
    /// the error's rendered message is classified Sensitive and never reaches a
    /// release log (hard rule 12).
    static func error(operation: String, category: LogCategory, error: any Error) {
        shared.emit(AppError(operation: operation, category: category, error: error))
    }

    /// Emits a typed handled-degradation warning (docs/LOGGING.md §3).
    static func warning(operation: String, category: LogCategory, reason: String) {
        shared.emit(AppWarning(operation: operation, category: category, reason: reason))
    }

    private static func deviceId() -> String? {
        (try? KeychainSessionStore().load())?.deviceId
    }
}

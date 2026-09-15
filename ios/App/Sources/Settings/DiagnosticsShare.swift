import Foundation
import TankbookCore
import UIKit

/// The diagnostics share's file payload (RV.181). The preview text is written
/// to a `.txt` and handed to the share sheet as a **file URL**, never as the raw
/// `String`.
///
/// The bundle is 12-15 KB of text. A destination that accepts only short
/// messages (Telegram caps at 4096 characters) drops or refuses that much text
/// while AirDrop, Notes and Mail accept it - the destination-specific "picked
/// Telegram and nothing arrived" the device report describes. Every destination
/// accepts a file, and the export door already shares files, so the fix does not
/// depend on confirming the exact mechanism.
///
/// The on-screen preview is unchanged: the file IS the preview text, byte for
/// byte. It carries the same `completeUntilFirstUserAuthentication` protection
/// as every other file the app writes (docs/SECURITY.md). It is removed once the
/// share's outcome arrives, cancel included; a share the user never finishes
/// leaves at most one behind because each write sweeps the directory first.
@MainActor
enum DiagnosticsShare {

    /// The production presenter: the one share seam. A parameter so a unit test
    /// can drive the outcome without a live key window.
    static let presenter: ([Any], @escaping (ShareOutcome) -> Void) -> UIActivityViewController? = {
        items, completion in
        SharePresenter.present(items: items, completion: completion)
    }

    /// Writes the preview text to a file and presents that file, logging the
    /// outcome as the `diagnostics.share` event with `kind: "file"` (shape only,
    /// docs/LOGGING.md -> Shares; never the text or a destination app - hard
    /// rule 12).
    @discardableResult
    static func present(
        text: String,
        now: Date = Date(),
        directory: URL = defaultDirectory,
        presenter: ([Any], @escaping (ShareOutcome) -> Void) -> UIActivityViewController? = DiagnosticsShare.presenter
    ) -> UIActivityViewController? {
        guard let url = try? write(text, now: now, directory: directory) else { return nil }
        return presenter([url]) { outcome in
            AppLog.share(operation: "diagnostics.share", kind: "file", outcome: outcome)
            remove(url)
        }
    }

    /// Writes `text` UTF-8 to `tankbook-diagnostics-<yyyyMMdd-HHmm>.txt`,
    /// sweeping any bundle a previous, unfinished share left behind.
    @discardableResult
    static func write(_ text: String,
                      now: Date = Date(),
                      directory: URL = defaultDirectory) throws -> URL {
        sweep(directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName(for: now))
        try Data(text.utf8).write(to: url, options: [.atomic])
        FileProtection.protect(url)
        return url
    }

    /// Removes the bundle once the share settles.
    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// `tankbook-diagnostics-<yyyyMMdd-HHmm>.txt`. Minute precision: two shares
    /// in the same minute reuse the name, which the sweep already makes safe.
    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "tankbook-diagnostics-\(formatter.string(from: date)).txt"
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    /// At most one diagnostics bundle exists at a time: a share the user never
    /// finished has no completion to remove it.
    private static func sweep(_ directory: URL) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in contents
        where url.lastPathComponent.hasPrefix("tankbook-diagnostics-")
            && url.pathExtension == "txt" {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

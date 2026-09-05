import Foundation
import TankbookCore
import UIKit

/// Builds the app's feedback wiring (PJ.20, docs/ERRORS.md -> About & feedback):
/// the core `FeedbackOutbox` over the app's transport, the consent store, and
/// the queue file. DEBUG/test seams mirror the ImportService pattern - a stub
/// transport for the offline/429 states and a consent seed, so UI tests and
/// screenshots never touch a server or a real preference.
@MainActor
enum FeedbackService {

    /// Builds the About composer's model over the one outbox, so the toggle
    /// writes through to the same consent store the queue reads.
    static func makeModel(arguments: [String] = ProcessInfo.processInfo.arguments) -> FeedbackModel {
        let consentStore = FeedbackConsentStore()
        #if DEBUG
        if arguments.contains("-feedbackConsentOn") {
            consentStore.setConsented(true)
        }
        #endif
        let outbox = makeOutbox(consentStore: consentStore, arguments: arguments)
        return FeedbackModel(outbox: outbox, consentStore: consentStore,
                             appVersion: appVersion(), deviceModel: deviceModel())
    }

    /// Builds the one outbox the About screen submits through.
    static func makeOutbox(consentStore: FeedbackConsentStore,
                           arguments: [String] = ProcessInfo.processInfo.arguments) -> FeedbackOutbox {
        let transport: any TankbookHTTPTransport
        #if DEBUG
        if arguments.contains("-feedbackTransportOffline") {
            transport = FailingFeedbackTransport()
        } else if arguments.contains("-feedbackRateLimit") {
            transport = RateLimitedFeedbackTransport()
        } else {
            transport = appTransport(SeededLaunch.transport(arguments))
        }
        #else
        transport = appTransport(URLSessionTransport())
        #endif
        let sessionStore = KeychainSessionStore()
        let client = FeedbackClient(
            httpClient: TankbookHTTPClient(transport: transport,
                                           tokenProvider: KeychainTokenProvider(sessionStore: sessionStore)),
            director: AppConfigStore.shared.director,
            deviceID: Self.deviceID(sessionStore: sessionStore))
        let queue = FeedbackQueue(consentStore: consentStore, store: Self.queueStore())
        return FeedbackOutbox(client: client, queue: queue, log: AppLog.shared)
    }

    /// The injected version string, read from the bundle (never hardcoded).
    static func appVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// The device's hardware model identifier (e.g. `iPhone17,2`), never the
    /// user's device name - that can be personal ("Marina's iPhone") and must
    /// not ride a feedback case without a separate, obvious opt-in.
    static func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = Mirror(reflecting: systemInfo.machine).children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    // MARK: - Plumbing

    /// The queue's persistence: one JSON file beside the database, so a queued
    /// case survives a relaunch (hard rule 8, docs/SECURITY.md -> at-rest
    /// protection).
    private static func queueStore() -> any FeedbackQueueStore {
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let container = directory.appendingPathComponent("Tankbook", isDirectory: true)
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        return FileFeedbackQueueStore(fileURL: container.appendingPathComponent("feedback-queue.json"))
    }

    /// The `X-Device-Id` for feedback attribution (docs/API.md): the signed-in
    /// session's device id, else a persistent per-install identifier. Feedback
    /// works signed out, so a signed-out case is still attributable.
    private static func deviceID(sessionStore: KeychainSessionStore) -> String? {
        if let session = try? sessionStore.load() {
            return session.deviceId
        }
        let key = "tankbook.feedback.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}

/// Forces the offline state for the "saved, sends when online" UI test and
/// screenshot.
#if DEBUG
struct FailingFeedbackTransport: TankbookHTTPTransport {
    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        throw URLError(.notConnectedToInternet)
    }
}

/// Forces the `429` state for the "queued for tomorrow" UI test and screenshot.
struct RateLimitedFeedbackTransport: TankbookHTTPTransport {
    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        TankbookHTTPResponse(status: 429, headers: ["Retry-After": "3600"])
    }
}
#endif

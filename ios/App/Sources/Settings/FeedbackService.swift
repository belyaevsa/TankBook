import Foundation
import TankbookCore
import UIKit

/// Builds the app's feedback wiring (PJ.20, docs/ERRORS.md -> About & feedback):
/// the core `FeedbackOutbox` over the app's transport, the consent store, and
/// the queue file. DEBUG/test seams mirror the ImportService pattern - a stub
/// transport for the offline/429 states and a consent seed, so UI tests and
/// screenshots never touch a server or a real preference.
///
/// One outbox serves the whole app (RV.127). `outbox` is the single instance:
/// the launch/foreground automatic pass (`AppRootView.runAutomaticPass`) drains
/// it, and the About composer submits through the SAME instance. A second
/// outbox over the same queue file would each load their own copy of the queue
/// and double-POST on a flush racing a submit.
@MainActor
enum FeedbackService {

    /// Builds the About composer's model over the app's one outbox, so the
    /// toggle writes through to the same consent store the queue reads.
    static func makeModel(arguments: [String] = ProcessInfo.processInfo.arguments) -> FeedbackModel {
        let consentStore = FeedbackConsentStore()
        #if DEBUG
        // `-feedbackConsentReset` REMOVES the key rather than writing false,
        // exactly like `-diagnosticsConsentReset`: a UI test pinning the
        // default-off must reproduce a fresh install, never mask a default-on
        // mutation behind an explicit false written by an earlier launch.
        if arguments.contains("-feedbackConsentReset") {
            consentStore.reset()
        }
        if arguments.contains("-feedbackConsentOn") {
            consentStore.setConsented(true)
        }
        #endif
        return FeedbackModel(outbox: outbox, consentStore: consentStore,
                             appVersion: appVersion(), deviceModel: deviceModel())
    }

    /// The app's ONE feedback outbox, built once per process and returned for
    /// every caller. The transport and consent seams are launch arguments, so
    /// building at first use honours them unchanged. Memoized so the automatic
    /// pass and the About composer can never hold two outboxes over one file.
    static var outbox: FeedbackOutbox {
        if let cachedOutbox { return cachedOutbox }
        #if DEBUG
        feedbackQueueResetIfRequested()
        #endif
        let built = makeOutbox(consentStore: FeedbackConsentStore())
        cachedOutbox = built
        return built
    }

    private static var cachedOutbox: FeedbackOutbox?

    /// Clears the persisted queue BEFORE the outbox loads it, so a test run
    /// starts with an empty queue. The queue file outlives `-homeResetDatabase`
    /// (which wipes only the database), so a queued "Test feedback" row from an
    /// earlier queued-offline UI test would otherwise ride every later launch -
    /// and RV.127's foreground flush would POST it to the real endpoint from an
    /// unseeded run (an app-hosted unit test), which is exactly how seeded-launch
    /// hygiene is supposed to stop: no test ever writes to production.
    ///
    /// Two triggers: `-feedbackQueueReset` (UI tests and screenshots) and the
    /// XCTest unit-test host, which `xcodebuild test` launches unseeded and with
    /// `XCTestConfigurationFilePath` set. Harmless when the queue is already
    /// empty, which is the state production launches are in.
    #if DEBUG
    static func feedbackQueueResetIfRequested(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        let unitTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        guard arguments.contains("-feedbackQueueReset") || unitTestHost else { return }
        try? FileManager.default.removeItem(at: queueFileURL())
    }
    #endif

    /// Builds the concrete outbox wiring (transport, client, queue) that
    /// `outbox` memoizes.
    static func makeOutbox(consentStore: FeedbackConsentStore,
                           arguments: [String] = ProcessInfo.processInfo.arguments) -> FeedbackOutbox {
        let transport: any TankbookHTTPTransport
        #if DEBUG
        if arguments.contains("-feedbackTransportOffline") {
            transport = FailingFeedbackTransport()
        } else if arguments.contains("-feedbackRateLimit") {
            transport = RateLimitedFeedbackTransport()
        } else if arguments.contains("-feedbackTransportServerError") {
            transport = ServerErrorFeedbackTransport()
        } else if arguments.contains("-feedbackTransportSuccess") {
            transport = SucceedingFeedbackTransport()
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
        FileFeedbackQueueStore(fileURL: queueFileURL())
    }

    /// The queue file's URL, under the same Application Support container the
    /// database lives in. Also the reset seam's target (`-feedbackQueueReset`).
    private static func queueFileURL() -> URL {
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let container = directory.appendingPathComponent("Tankbook", isDirectory: true)
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        return container.appendingPathComponent("feedback-queue.json")
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

/// RV.160: forces the `202` success state for the "sent" UI test and
/// screenshot - the one outcome no seeded launch can reach, because every other
/// seeded transport answers offline.
struct SucceedingFeedbackTransport: TankbookHTTPTransport {
    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        TankbookHTTPResponse(status: 202)
    }
}

/// RV.160: forces a transient server error (the "saved, will retry" queued
/// state) for its UI test.
struct ServerErrorFeedbackTransport: TankbookHTTPTransport {
    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        TankbookHTTPResponse(status: 500)
    }
}
#endif

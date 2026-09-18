import Foundation
import Observation
import TankbookCore
import UIKit

/// PR.20: the device's side of the silent sync nudge (docs/NOTIFICATIONS.md,
/// docs/API.md `PUT /account/devices/{id}/push-token`). Registration asks for
/// no permission - a silent push needs none - and runs only when signed in,
/// because the token row is per account-device. The token goes up once per
/// (token, account) pair (`PushTokenRegistration.shouldSend`), so a relaunch
/// sends nothing and a rotation or a new sign-in sends again; the pair is
/// remembered only after the server acknowledged it. A nudge runs the same
/// opportunistic cycle the foreground runs - nudges are an optimisation,
/// never a dependency, and every failure here is a warning the user never sees.
@MainActor
@Observable
final class AppPush {
    static let shared = AppPush()

    /// The last token APNs handed over (in memory; APNs hands it over again on
    /// every registration, so nothing needs to survive a relaunch).
    private(set) var token: String?
    /// The pair the server last acknowledged. Persisted so a relaunch with the
    /// same token and account sends nothing.
    private var acknowledged: PushTokenRegistration.Acknowledged? {
        get {
            guard let data = defaults.data(forKey: Self.acknowledgedKey) else { return nil }
            return try? JSONDecoder().decode(PushTokenRegistration.Acknowledged.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.acknowledgedKey)
            } else {
                defaults.removeObject(forKey: Self.acknowledgedKey)
            }
        }
    }
    /// True once a PUT was acknowledged in this process - the DEBUG marker's
    /// signal.
    private(set) var didRegisterThisLaunch = false

    /// Installed by the app root: the opportunistic cycle a nudge runs.
    var onNudge: (@MainActor () async -> Void)?

    private let defaults: UserDefaults
    private let sessionStore: any SessionStore
    private let makeClient: @MainActor () -> AccountClient
    private var sending = false

    static let acknowledgedKey = "push.acknowledged"

    init(defaults: UserDefaults = .standard,
         sessionStore: any SessionStore = KeychainSessionStore(),
         makeClient: (@MainActor () -> AccountClient)? = nil) {
        self.defaults = defaults
        self.sessionStore = sessionStore
        self.makeClient = makeClient ?? {
            AccountClient(
                httpClient: TankbookHTTPClient(
                    transport: makeAppTransport(),
                    tokenProvider: KeychainTokenProvider(sessionStore: sessionStore)),
                director: AppConfigStore.shared.director)
        }
    }

    /// Launch and foreground: ask APNs for the token when a session exists.
    /// A guest is never registered (no account, no row). The DEBUG seed hands
    /// over a token the simulator cannot produce.
    func registerIfSignedIn() {
        #if DEBUG
        if let seeded = Self.seededToken() {
            tokenReceived(seeded)
            return
        }
        #endif
        guard (try? sessionStore.load()) != nil else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Sign-in just completed: the stored token, if APNs already handed one
    /// over, goes up for the new account; else registration is requested.
    func signedIn() {
        if token != nil {
            sendIfNeeded()
        } else {
            registerIfSignedIn()
        }
    }

    /// Sign-out forgets the acknowledgement: the next sign-in re-sends, even
    /// with the same token, because the row is per account-device.
    func signedOut() {
        acknowledged = nil
    }

    func tokenReceived(_ hex: String) {
        token = hex
        sendIfNeeded()
    }

    private func sendIfNeeded() {
        let accountId = (try? sessionStore.load())?.accountId
        guard !sending,
              PushTokenRegistration.shouldSend(token: token, accountId: accountId, acknowledged: acknowledged),
              let token, let accountId,
              let deviceId = ((try? sessionStore.load())?.deviceId).flatMap(UUID.init(uuidString:)) else { return }
        sending = true
        let client = makeClient()
        Task { [weak self] in
            defer { self?.sending = false }
            do {
                try await client.setPushToken(deviceID: deviceId, apnsToken: token)
                self?.acknowledged = PushTokenRegistration.Acknowledged(token: token, accountId: accountId)
                self?.didRegisterThisLaunch = true
                AppLog.shared.emit(PushTokenRegistered())
            } catch {
                // The device keeps polling; the next launch tries again.
                AppLog.warning(operation: "push.token", category: .sync, reason: "put_failed")
            }
        }
    }

    /// A silent push: one opportunistic cycle, reported as new data when it
    /// ran and as no data when nothing was installed to run.
    func handleSilentPush() async -> UIBackgroundFetchResult {
        AppLog.shared.emit(PushNudgeReceived())
        guard let onNudge else { return .noData }
        await onNudge()
        return .newData
    }

    #if DEBUG
    /// `-seedPushToken <hex>`: the token APNs would have handed over, so a UI
    /// test can observe the PUT on the stub transport.
    private static func seededToken() -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-seedPushToken"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
    #endif
}

#if DEBUG
import SwiftUI

/// The UI-test marker for "the push-token PUT was acknowledged"
/// (`-seedPushToken`): a 1 pt element the L4 waits on after a seeded sign-in.
struct PushTokenRegisteredMarker: View {
    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("-seedPushToken"),
           AppPush.shared.didRegisterThisLaunch {
            Text(verbatim: "·")
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityIdentifier("pushTokenRegistered")
        }
    }
}
#endif

/// `push.token` - the server acknowledged this device's token. Shape only:
/// no token, no account (hard rule 12).
struct PushTokenRegistered: LogEvent {
    let eventName = "push.token"
    let category = LogCategory.sync
    let level = LogLevel.info
    let fields: [LogField] = [.safe("outcome", "acknowledged")]
}

/// `push.nudge` - a silent push woke the app for one sync cycle.
struct PushNudgeReceived: LogEvent {
    let eventName = "push.nudge"
    let category = LogCategory.sync
    let level = LogLevel.info
    let fields: [LogField] = []
}

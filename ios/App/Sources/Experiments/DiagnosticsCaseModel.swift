#if EXPERIMENTS
import Foundation
import Observation
import TankbookCore
import UIKit

/// iOS's background grace time around a piece of work. `begin` returns a token
/// for `end`; `onExpire` runs on the main actor when the grace runs out first.
@MainActor
protocol BackgroundGrace {
    func begin(name: String, onExpire: @escaping @MainActor () -> Void) -> Int
    func end(_ token: Int)
}

/// The production grace: `UIApplication.beginBackgroundTask`, with the expiry
/// logged as `background.task.expired` (docs/LOGGING.md §4).
@MainActor
struct UIKitBackgroundGrace: BackgroundGrace {
    func begin(name: String, onExpire: @escaping @MainActor () -> Void) -> Int {
        let logging = BackgroundTaskLogging(log: AppLog.shared, kind: "debugCase")
        var identifier: UIBackgroundTaskIdentifier = .invalid
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            let remaining = UIApplication.shared.backgroundTimeRemaining
            MainActor.assumeIsolated {
                logging.note(grantedSeconds: remaining.isFinite ? max(0, Int(remaining)) : 0)
                logging.expired()
                onExpire()
                UIApplication.shared.endBackgroundTask(identifier)
            }
        }
        return identifier.rawValue
    }

    func end(_ token: Int) {
        let identifier = UIBackgroundTaskIdentifier(rawValue: token)
        if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier) }
    }
}

/// "Send diagnostics" (About -> Experiments): the app's log and the kept scans,
/// sent as one debug case on the tester's tap, answered with the id the owner
/// reads it by (hard rule 9's debug-cases amendment). Nothing is sent without
/// the tap; the log is the same redacted text the diagnostics preview shows.
@MainActor
@Observable
final class DiagnosticsCaseModel {
    enum State: Equatable {
        case loading
        case ready
        /// Parts fully uploaded, of the parts in the case.
        case sending(uploaded: Int, total: Int)
        case sent(DebugCaseReceipt)
        case failed(DebugCaseError)
    }

    private(set) var state: State = .loading
    private(set) var logText = ""
    private(set) var scans: [ScanHistory.Entry] = []
    var includeScans = true

    typealias Progress = @Sendable (Int, Int) -> Void
    private let send: @Sendable ([DebugCasePart], @escaping Progress) async throws -> DebugCaseReceipt
    private let background: any BackgroundGrace

    init(background: any BackgroundGrace = UIKitBackgroundGrace(),
         send: @escaping @Sendable ([DebugCasePart], @escaping Progress) async throws -> DebugCaseReceipt) {
        self.background = background
        self.send = send
    }

    var logLineCount: Int {
        logText.split(separator: "\n").count
    }

    func load() async {
        logText = await DiagnosticsService.makePreviewText()
        scans = ScanRecorder.history?.recent() ?? []
        if state == .loading { state = .ready }
    }

    var isSending: Bool {
        if case .sending = state { return true }
        return false
    }

    func submit() async {
        guard !isSending else { return }
        let parts = DebugCase.parts(log: logText, scans: includeScans ? scans : [],
                                    app: LogContext.currentAppVersion(),
                                    build: Bundle.main.object(forInfoDictionaryKey: "TankbookBuildCommit") as? String)
        state = .sending(uploaded: 0, total: parts.count)
        let send = self.send
        let upload = Task {
            try await send(parts) { uploaded, total in
                Task { @MainActor [weak self] in
                    guard let self, case .sending(let shown, _) = self.state, uploaded > shown else { return }
                    self.state = .sending(uploaded: uploaded, total: total)
                }
            }
        }
        // A 7-13 MB case takes 15-30 s on a phone network: long enough for the
        // tester to switch apps. The upload runs on iOS's background grace
        // time, and if that runs out the send is cancelled and says so, rather
        // than dying with the suspended process.
        let grace = background.begin(name: "tankbook.case") { upload.cancel() }
        defer { background.end(grace) }
        do {
            state = .sent(try await upload.value)
        } catch _ where upload.isCancelled {
            state = .failed(.interrupted)
        } catch let error as DebugCaseError {
            state = .failed(error)
        } catch {
            state = .failed(.failed(status: nil))
        }
    }

    /// The production model: the case client over the app's transport, the
    /// device identity the import path already keeps for signed-out uploads.
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> DiagnosticsCaseModel {
        #if DEBUG
        if let stubbed = stub(arguments: arguments) { return stubbed }
        #endif
        let sessionStore = KeychainSessionStore()
        let client = DebugCaseClient(
            httpClient: TankbookHTTPClient(transport: appTransport(URLSessionTransport()),
                                           tokenProvider: KeychainTokenProvider(sessionStore: sessionStore)),
            director: AppConfigStore.shared.director,
            deviceID: ImportService.deviceID(sessionStore: sessionStore))
        return DiagnosticsCaseModel { parts, progress in try await client.send(parts, progress: progress) }
    }

    #if DEBUG
    /// Test and screenshot seam: `-diagnosticsCaseStub sent|offline|tooLarge|interrupted`
    /// answers the send without a network.
    private static func stub(arguments: [String]) -> DiagnosticsCaseModel? {
        guard let index = arguments.firstIndex(of: "-diagnosticsCaseStub"), index + 1 < arguments.count else {
            return nil
        }
        let outcome = arguments[index + 1]
        return DiagnosticsCaseModel { parts, progress in
            // About 1.8 s in all, however many parts: long enough to see the
            // progress, short enough for a UI test's wait.
            let step = max(60, 1_800 / max(parts.count, 1))
            for uploaded in 1...max(parts.count, 1) {
                try await Task.sleep(for: .milliseconds(step))
                progress(uploaded, parts.count)
            }
            switch outcome {
            case "offline": throw DebugCaseError.offline
            case "tooLarge": throw DebugCaseError.tooLarge
            case "interrupted": throw DebugCaseError.interrupted
            default:
                return DebugCaseReceipt(caseId: "K7Q2M-9XDRA",
                                        expiresAt: Date().addingTimeInterval(30 * 24 * 3600))
            }
        }
    }
    #endif
}
#endif

#if EXPERIMENTS
import Foundation
import Observation
import TankbookCore

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
        case sending
        case sent(DebugCaseReceipt)
        case failed(DebugCaseError)
    }

    private(set) var state: State = .loading
    private(set) var logText = ""
    private(set) var scans: [ScanHistory.Entry] = []
    var includeScans = true

    private let send: @Sendable ([DebugCasePart]) async throws -> DebugCaseReceipt

    init(send: @escaping @Sendable ([DebugCasePart]) async throws -> DebugCaseReceipt) {
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

    func submit() async {
        guard state != .sending else { return }
        state = .sending
        let parts = DebugCase.parts(log: logText, scans: includeScans ? scans : [],
                                    app: LogContext.currentAppVersion(),
                                    build: Bundle.main.object(forInfoDictionaryKey: "TankbookBuildCommit") as? String)
        do {
            state = .sent(try await send(parts))
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
        return DiagnosticsCaseModel { parts in try await client.send(parts) }
    }

    #if DEBUG
    /// Test and screenshot seam: `-diagnosticsCaseStub sent|offline|tooLarge`
    /// answers the send without a network.
    private static func stub(arguments: [String]) -> DiagnosticsCaseModel? {
        guard let index = arguments.firstIndex(of: "-diagnosticsCaseStub"), index + 1 < arguments.count else {
            return nil
        }
        let outcome = arguments[index + 1]
        return DiagnosticsCaseModel { _ in
            try await Task.sleep(for: .milliseconds(300))
            switch outcome {
            case "offline": throw DebugCaseError.offline
            case "tooLarge": throw DebugCaseError.tooLarge
            default:
                return DebugCaseReceipt(caseId: "K7Q2M-9XDRA",
                                        expiresAt: Date().addingTimeInterval(30 * 24 * 3600))
            }
        }
    }
    #endif
}
#endif

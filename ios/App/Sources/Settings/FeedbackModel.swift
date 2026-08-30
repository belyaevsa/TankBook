import Foundation
import Observation
import TankbookCore

/// The About feedback composer's state (PJ.20, docs/ERRORS.md -> About &
/// feedback). Owns the draft, the consent mirror, and the submission outcome.
/// The consent store is the source of truth for persistence; the model caches
/// the value for the toggle and writes through on change (hard rule 13: a value
/// the user set is theirs, changeable afterwards).
@MainActor
@Observable
final class FeedbackModel {

    enum State: Equatable {
        case idle
        case sending
        case sent
        case consentRequired
        case queuedOffline
        case queuedRateLimited
        case queuedRetry
    }

    private let outbox: FeedbackOutbox
    private let consentStore: FeedbackConsentStore
    private let appVersion: String
    private let deviceModel: String

    var category: FeedbackCategory = .feature
    var text: String = ""
    var attachDeviceModel = false
    var replyTo: String = ""
    private(set) var state: State = .idle

    /// The once-asked opt-in, mirrored for the toggle. Default OFF; written
    /// through to the persisted store on every change.
    var hasConsented: Bool {
        didSet { consentStore.setConsented(hasConsented) }
    }

    init(outbox: FeedbackOutbox, consentStore: FeedbackConsentStore,
         appVersion: String, deviceModel: String) {
        self.outbox = outbox
        self.consentStore = consentStore
        self.appVersion = appVersion
        self.deviceModel = deviceModel
        self.hasConsented = consentStore.hasConsented
    }

    var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Submits the draft. The consent gate is the load-bearing rule: without it
    /// nothing is queued and the composer surfaces the opt-in (hard rule 7 -
    /// the next step is named). The `deviceModel` rides only with its toggle.
    func send() async {
        guard canSend else { return }
        guard hasConsented else {
            state = .consentRequired
            return
        }
        let payload = FeedbackPayload(
            category: category,
            text: text,
            appVersion: appVersion,
            deviceModel: attachDeviceModel ? deviceModel : nil,
            replyTo: trimmedReplyTo
        )
        state = .sending
        switch await outbox.submit(payload) {
        case .consentRequired:
            state = .consentRequired
        case .sent:
            state = .sent
            text = ""
            replyTo = ""
        case .queued(let reason):
            switch reason {
            case .offline: state = .queuedOffline
            case .rateLimited: state = .queuedRateLimited
            case .serverError: state = .queuedRetry
            }
        }
    }

    private var trimmedReplyTo: String? {
        let trimmed = replyTo.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// PJ.20 DEBUG seed (`-feedbackAutoSend`): pre-fills a draft and submits it
    /// on appear, so the L4 offline/429 states render through the real outbox
    /// without a UI test driving a keyboard and a scroll. Production never
    /// passes the argument.
    func autoSendIfRequested() async {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-feedbackAutoSend") else { return }
        if text.isEmpty { text = "Test feedback" }
        await send()
        #endif
    }
}

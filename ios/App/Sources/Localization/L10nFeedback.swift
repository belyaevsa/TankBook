import Foundation
import TankbookCore

/// About & feedback strings (PJ.20, docs/ERRORS.md -> About & feedback) and the
/// import "send us the file" consent. In its own file so the main `L10n` enum
/// stays within the lint file-length budget - the same shape as the existing
/// `lowPowerDeferredMessage` extension.
extension L10n {

    // MARK: - About & feedback

    /// The category chip label ("Ask for a feature" / "Something's wrong" /
    /// "Other").
    static func feedbackCategory(_ category: FeedbackCategory) -> String {
        switch category {
        case .feature: localize("Ask for a feature")
        case .problem: localize("Something's wrong")
        case .other: localize("Other")
        }
    }

    /// The text editor's placeholder.
    static var feedbackPlaceholder: String {
        localize("What's on your mind?")
    }

    /// "Attach device model" - the toggle that controls whether `deviceModel`
    /// rides the payload (docs/API.md -> Feedback). Default off.
    static var feedbackAttachDeviceModel: String { localize("Attach device model") }

    /// "Reply to (optional)" - the contact-address field.
    static var feedbackReplyTo: String { localize("Reply to (optional)") }

    /// The once-asked opt-in (docs/ERRORS.md -> About & feedback). Default OFF,
    /// persisted, changeable afterwards (hard rule 13).
    static var feedbackConsent: String {
        localize("Help improve scanning – attach this case")
    }

    /// The consent's explanation: what "attach this case" sends and never sends.
    static var feedbackConsentDetail: String {
        let key = "Sends your message with the app version and any details you attach. "
            + "Never log data, and never your name or address unless you add them."
        return localize(key)
    }

    /// "Send feedback" - the primary action.
    static var feedbackSend: String { localize("Send feedback") }

    /// "Thanks – your feedback is on its way." - the sent confirmation.
    static var feedbackSent: String {
        localize("Thanks – your feedback is on its way.")
    }

    /// "Saved – sends automatically when you're online." (docs/ERRORS.md).
    static var feedbackQueuedOffline: String {
        localize("Saved – sends automatically when you're online.")
    }

    /// "That's a lot of feedback today – this one's queued for tomorrow."
    /// (docs/ERRORS.md, the 429 state).
    static var feedbackRateLimited: String {
        localize("That's a lot of feedback today – this one's queued for tomorrow.")
    }

    /// A transient server error: still saved, still sends (hard rule 8).
    static var feedbackQueuedRetry: String {
        localize("Saved – we'll try again when the service is back.")
    }

    /// The consent gate's next step (hard rule 7): names the toggle to enable.
    static var feedbackConsentRequired: String {
        localize("Turn on “Help improve scanning – attach this case” to send.")
    }

    /// The composer's footnote (design/screens/About.dc.html).
    static var feedbackFootnote: String {
        let key = "Every message is read by a human. Feature requests shape the roadmap "
            + "– the importers exist because people asked."
        return localize(key)
    }

    // MARK: - Import "send us the file"

    /// The send-file sheet's title.
    static var sendFileTitle: String { localize("Send us the file") }

    /// The explicit consent line: states what is sent, plainly (hard rule 7 -
    /// the user knows exactly what they are sharing before they share it).
    static var sendFileConsent: String {
        let key = "Tankbook receives your export file so we can add support for your fuel app. "
            + "It may contain your fuel history, amounts and notes."
        return localize(key)
    }

    /// The share-file primary action (the affirmative consent).
    static var sendFileShare: String { localize("Share file") }

    /// The share sheet's body: the sentence that accompanies the file.
    static var sendFileMessage: String {
        localize("I'd like Tankbook to import from my fuel app – here's my export file.")
    }
}

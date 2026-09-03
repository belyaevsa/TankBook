import Foundation
import TankbookCore

/// The inbox's labels (RV.38, docs/JOURNEYS.md F4). In its own file so
/// `L10n.swift` stays under its lint budget. Every key has an EN + RU entry -
/// the three action labels are the RU overflow test (docs/TASKS.md RV.38):
/// "Update from the receipt" / "Leave it as it is" / "Replace the receipt"
/// expand hard in Russian and sit in a crowded header.
extension L10n {
    /// The bell's spoken name and the Inbox screen's title.
    static var inboxTitle: String {
        localize("Inbox")
    }

    /// "1 item in inbox" - the bell's spoken count, real plural rules per
    /// language (RU has three forms). The bell announces the count, so a
    /// VoiceOver reader knows there is work without hunting for the badge.
    static func inboxItemCount(_ count: Int) -> String {
        String(localized: "\(count) items in inbox")
    }

    /// The item title and the entry badge's spoken label: a reading finished
    /// after the user saved, so it is an offer, never a rewrite (hard rule 13).
    static var inboxReceiptReady: String {
        localize("Receipt reading ready")
    }

    /// The item's subtitle: honest about WHEN the reading arrived, so the user
    /// knows it was not part of their save.
    static var inboxFinishedAfterSave: String {
        localize("Finished after you saved.")
    }

    /// The accepted update: fills blank fields only, never a typed value.
    static var inboxUpdateFromReceipt: String {
        localize("Update from the receipt")
    }

    /// The default answer - nothing changes.
    static var inboxLeaveAsIs: String {
        localize("Leave it as it is")
    }

    /// The third action: routes to the entry, where the receipt lives.
    static var inboxReplaceReceipt: String {
        localize("Replace the receipt")
    }

    /// The reassuring empty state (Recently deleted's "nothing here" sibling).
    static var inboxEmpty: String {
        localize("Nothing needs your attention")
    }
}

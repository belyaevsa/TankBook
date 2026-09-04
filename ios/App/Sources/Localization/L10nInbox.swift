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

    /// The comparison table's "yours" column header: the value the user saved.
    static var inboxYouEntered: String {
        localize("You entered")
    }

    /// The comparison table's receipt column header.
    static var inboxReceiptColumn: String {
        localize("Receipt")
    }

    /// The per-field verb for a field the receipt reads DIFFERENTLY: taking it
    /// REPLACES what the user typed. Deliberately distinct from `inboxFills`
    /// (RV.45 honesty rule 3) - the two acts must not read as one word.
    static var inboxReplaces: String {
        localize("Replaces what you entered")
    }

    /// The per-field verb for a field the user left BLANK: taking the receipt's
    /// value FILLS it. Not "replacing" anything, and it must not read that way.
    static var inboxFills: String {
        localize("Fills the empty field")
    }

    /// The no-op card (RV.45 honesty rule 2): an item whose reading agrees with
    /// what is now saved. States the truth and offers no action that changes
    /// nothing.
    static var inboxNothingToChange: String {
        localize("Nothing to change – the receipt matches what you saved.")
    }

    /// The entry the item routes to no longer exists (docs/ERRORS.md -> Inbox).
    static var inboxEntryGone: String {
        localize("The entry this reading was about no longer exists.")
    }
}

import Foundation
import TankbookCore

/// The Settings account card's caption for a **persisted** last sync failure
/// (OB.3): the copy a cycle's outcome would have shown live, rendered on a
/// relaunch before any cycle has run to re-derive it. It is a **statement of
/// the last outcome, not an alarm**: the colour follows the same split as the
/// live surface (`SyncServerNotice.isAttention` / `SyncStatus.isAttention`) -
/// amber only for the classes that need the user to act, `inkSoft` for the
/// ones the app resolves by itself - and every class names its next step
/// (hard rule 7) in the vocabulary docs/ERRORS.md -> Settings already uses.
struct SyncFailureCaption {
    let text: String
    let isAttention: Bool

    /// Resolves the caption to render, or nil when there is nothing to show:
    /// no persisted failure, a live cycle has already run (its own outcome now
    /// drives the surface, and the coordinator's persisted record is the same
    /// cycle anyway), or the failure is `.offline` - offline is never an error
    /// surface, and an offline record with nothing pending is the ordinary
    /// synced reassurance, not a caption.
    static func resolve(record: SyncFailureRecord?, hasLiveOutcome: Bool) -> SyncFailureCaption? {
        guard let record, !hasLiveOutcome else { return nil }
        let attention: Bool
        let text: String
        switch record.kind {
        case .offline:
            return nil
        case .serverUnavailable:
            text = L10n.syncServiceUnreachableMessage
            attention = false
        case .authExpired:
            text = L10n.authExpiredMessage
            attention = true
        case .deviceRevoked:
            text = L10n.deviceRevokedMessage
            attention = true
        case .upgradeRequired:
            text = L10n.syncNoticeUpgradeRequired
            attention = true
        case .tierRefused:
            text = L10n.syncNoticeTierRefused
            attention = true
        case .refused:
            text = L10n.syncNoticeRefused
            attention = true
        case .rateLimited:
            // The server's Retry-After is not persisted (only the code and
            // trace id are), so the caption reads as the generic wait.
            text = L10n.syncNoticeRateLimited(nil)
            attention = false
        case .invalidResponse:
            text = L10n.syncServiceUnreachableMessage
            attention = false
        }
        return SyncFailureCaption(text: text, isAttention: attention)
    }
}

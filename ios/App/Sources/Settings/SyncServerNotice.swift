import Foundation
import TankbookCore

/// P6.11: the passive Settings surface for a server that has moved ahead of
/// this client. `SyncEngine` classifies these responses (docs/SYNC.md) -
/// `upgradeRequired` (426), `tierRefused` (402), an unknown-4xx `refused`, and
/// `rateLimited` (429) - and nothing in `App/` read any of them until this
/// task, so a server running a newer version than the app produced silence.
///
/// The copy is **version-first, never an upsell** (hard rule 7): there is no
/// Pro tier, so the honest reading of every refusal is "update the app", and a
/// tier-shaped message would be both a hard-rule violation and a lie.
/// `.rateLimited` is deliberately a different KIND - a wait the app resolves by
/// itself - so it is reassurance (`inkSoft`), never amber, and carries no
/// update prompt (docs/SYNC.md -> "The Settings sync surface": the split
/// between reassurance and attention is the load-bearing property).
enum SyncServerNotice: Equatable {
    /// 426: this client's `schemaVersion` is below the server's minimum. The
    /// push is refused, the **pull still works**.
    case upgradeRequired
    /// 402: the server gated something this client cannot do. No Pro tier
    /// exists, so the only honest reading is an out-of-date client.
    case tierRefused
    /// Any other 4xx gate from a server newer than this client. Do not invent
    /// a reason.
    case refused(status: Int)
    /// 429: a wait, not a failure. The app retries by itself; the payload is
    /// the server's own `Retry-After` hint when it sent one.
    case rateLimited(retryAfterSeconds: Int?)
    /// Nothing to surface.
    case none

    /// Maps a sync outcome to the notice it must surface. Only the server-ahead
    /// responses land here; a transport outage stays in the existing
    /// `offline`/`serverUnavailable` path untouched (S7) - `.rateLimited` must
    /// never read like `.serverUnavailable` (docs/SYNC.md: "a wait, not a
    /// failure").
    static func classify(_ outcome: SyncOutcome) -> SyncServerNotice {
        if outcome.upgradeRequired { return .upgradeRequired }
        switch outcome.refusedByServer {
        case .tierRefused:
            return .tierRefused
        case .rateLimited(let retryAfter):
            return .rateLimited(retryAfterSeconds: outcome.retryAfterSeconds ?? retryAfter)
        case .refused(let status):
            return .refused(status: status)
        default:
            return .none
        }
    }

    /// The rendered message: version-first with the next step named (hard rule
    /// 7). `.rateLimited` reads as a wait, never a failure.
    var text: String {
        switch self {
        case .upgradeRequired:
            return L10n.syncNoticeUpgradeRequired
        case .tierRefused:
            return L10n.syncNoticeTierRefused
        case .refused:
            return L10n.syncNoticeRefused
        case .rateLimited(let retryAfterSeconds):
            return L10n.syncNoticeRateLimited(retryAfterSeconds)
        case .none:
            return ""
        }
    }

    /// Attention (amber) vs reassurance (`inkSoft`): the three update cases
    /// need the user to act, so they are attention; `.rateLimited` resolves
    /// itself, so it stays in the ordinary status colour and must never carry
    /// error styling - that distinction is the whole point of the core half.
    var isAttention: Bool {
        switch self {
        case .upgradeRequired, .tierRefused, .refused: return true
        case .rateLimited, .none: return false
        }
    }

    /// The accessibility identifier, split by class so a UI test can assert
    /// the styling split without colour introspection (XCUITest reads no
    /// colours): the quiet `settingsSyncNotice` vs the attention
    /// `settingsSyncNoticeAttention`.
    var accessibilityIdentifier: String {
        isAttention ? "settingsSyncNoticeAttention" : "settingsSyncNotice"
    }
}

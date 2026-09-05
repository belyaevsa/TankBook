import Foundation
import TankbookCore

/// The Settings storage-quota card's copy (the blob-quota 429 state,
/// docs/ERRORS.md -> Settings). In its own file so `L10n.swift` stays under its
/// 700-line lint budget (the `L10nSyncChip` precedent).
extension L10n {
    /// "Photo storage 95% full – older photos stay on this phone only."
    /// (docs/ERRORS.md -> Settings). One full localised phrase; the percent is
    /// runtime data.
    static func quotaFull(percent: Int) -> String {
        String(format: localize("Photo storage %lld%% full – older photos stay on this phone only."), percent)
    }

    /// The quota card's next step (RV.70, docs/ERRORS.md -> Settings): after the
    /// dead "Tankbook Pro" link was removed, the card names what the user can
    /// actually do - keep using the app on this phone (hard rule 1), nothing is
    /// lost, and new photo uploads resume when the account's space frees. No
    /// tier exists in v1 (P6.16), so no control replaces the link - a button to
    /// a screen that does not exist is the bug this sentence fixes (hard rule 7).
    static var quotaNextStep: String {
        localize("Everything on this phone keeps working – new photos upload when space frees up.")
    }
}

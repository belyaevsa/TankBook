import Foundation

/// The Confirm sheet's gateway copy (docs/ERRORS.md -> Confirm, the RV.65
/// row). In its own file so `L10n.swift` stays within its lint budget. Every
/// phrase here is a WHOLE localised phrase per language - never concatenation.
extension L10n {
    /// The dead-session notice on a cloud-extract capture (RV.65,
    /// docs/ERRORS.md -> Confirm): `/extract` was refused with a 401 the
    /// refresh could not fix (rejected, or it handed back the same bearer).
    /// The capture names its next step - sign in - and reassures that the
    /// entry still saves (hard rule 7: the message survives being ignored; hard
    /// rules 1 and 15: the local parse stands and typing is a peer door). The
    /// Settings account card (RV.26) is where the actual Sign in action lives.
    static var gatewayAuthExpiredNotice: String {
        localize("Your session has expired – sign in again to use cloud reading. This entry still saves.")
    }
}

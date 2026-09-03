import Foundation
import TankbookCore

/// The sync state chip's labels (RV.22, docs/SYNC.md -> "The sync state chip").
/// In its own file so `L10n.swift` stays under its 700-line lint budget. The
/// labels are the chip's accessibility names as well as its visible text - the
/// chip's state is asserted by WHICH label it shows, so the copy here is
/// load-bearing (the RU pass on P1.4 proved composed strings need a full
/// localised phrase per language, never concatenation).
extension L10n {
    /// State 1 - the label for a signed-out device. Deliberately colourless
    /// copy: staying local is legitimate, so the label names the state without
    /// a fault-word.
    static var chipNotSignedIn: String {
        localize("Not signed in")
    }

    /// State 2's three labels - the only amber the chip can show (hard rule 5).
    static var chipDeviceSignedOut: String {
        localize("Device signed out")
    }
    static var chipSignInAgain: String {
        localize("Sign in again")
    }
    static var chipStorageFull: String {
        localize("Storage full")
    }

    /// State 3: a cycle is in flight.
    static var chipSyncing: String {
        localize("Syncing…")
    }

    /// State 5: the reassurance default.
    static var chipSynced: String {
        localize("Synced")
    }
}

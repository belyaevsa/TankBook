#if DEBUG
import Foundation
import TankbookCore

/// DEBUG/test seeding for the sync chip (RV.22): forces the chip's presentation
/// state directly, so a screenshot or UI test can show each of the five states
/// without reproducing the transport outcome that produces it. The mapping the
/// chip renders is L1-tested (`SyncChipTests`); this seed only drives the
/// presentation.
///
/// The chip state is forced at LAUNCH, not at Settings appear - the chip lives
/// on the three tab roots, which render before Settings' own `.task` seed runs -
/// so this is a separate hook from `SettingsTestSeed.seedIfRequested`.
enum SyncChipTestSeed {
    /// Forces `sync.forcedChipState` (and the label counts) from the launch
    /// arguments, then leaves the rest to the real surface. A `-seedSyncChip*`
    /// argument with no match forces nothing (the chip derives its state).
    @MainActor
    static func seedIfRequested(sync: AppSync) {
        let arguments = ProcessInfo.processInfo.arguments

        let states: [(String, SyncChipState)] = [
            ("-seedSyncChipSignedOut", .signedOut),
            ("-seedSyncChipRevoked", .deviceRevoked),
            ("-seedSyncChipAuthExpired", .authExpired),
            ("-seedSyncChipQuota", .quotaFull),
            ("-seedSyncChipSyncing", .syncing),
            ("-seedSyncChipWaiting", .waiting),
            ("-seedSyncChipSynced", .synced),
        ]
        for (argument, state) in states where arguments.contains(argument) {
            sync.forcedChipState = state
            if state == .waiting {
                sync.forcedChipDirtyCount = 5
            }
        }

        // The warn dot is independent of the state it rides over (never a sixth
        // state), so it has its own seed. Combine with a state seed to show the
        // dot over "Synced", or alone to show it over whatever the real surface
        // derives.
        if arguments.contains("-seedSyncChipFlagged") {
            sync.forcedChipFlaggedCount = 2
        }
    }
}
#endif

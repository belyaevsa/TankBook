import Foundation
import TankbookCore
import UIKit

/// Builds the About "Attach diagnostics" wiring (docs/LOGGING.md §5): the
/// consent store, the persisted sync state (OB.3), the per-table row counts and
/// the preview text the user reads before anything leaves the device.
///
/// The bundle is assembled OFF the main actor: the only repository touch - the
/// row counts - is done here on the caller's actor, then the ring snapshot, the
/// sync summary and the counts are handed to `DiagnosticsExport.assemble`, which
/// runs the OSLog read on a detached task. Nothing domain-shaped is read: the
/// summary is the persisted `lastSuccessAt`/`lastFailure` (kind + code +
/// traceId), the counts are `fetchDirtyRows`/`flaggedEntryCount` tallies, the
/// row counts are `COUNT(*)` numbers (hard rule 12).
@MainActor
enum DiagnosticsService {

    /// The physical tables whose row counts ride the bundle (docs/LOGGING.md
    /// §5). Every table `TankbookCore` owns, in a stable order.
    static let rowCountTables: [String] = [
        TankbookSchema.vehicle,
        TankbookSchema.fillUp,
        TankbookSchema.chargeSession,
        TankbookSchema.serviceRecord,
        TankbookSchema.serviceItem,
        TankbookSchema.expense,
        TankbookSchema.reminder,
        TankbookSchema.station,
        TankbookSchema.tariff,
        TankbookSchema.tireSet,
        TankbookSchema.attachment,
        TankbookSchema.preferences,
        TankbookSchema.exchangeRate,
        TankbookSchema.duplicateResolution,
        TankbookSchema.syncOverwrite,
        TankbookSchema.syncPayloadMemory
    ]
    /// Builds the About model over the one consent store, applying the DEBUG
    /// test/screenshot seams (`-diagnosticsConsentOn` /
    /// `-diagnosticsConsentReset`) exactly as FeedbackService seeds its consent.
    /// Production never passes the arguments, so a fresh install reads the
    /// store's default-off. `-diagnosticsConsentReset` REMOVES the key rather
    /// than writing false: it reproduces a fresh install, so a test can pin the
    /// default itself (a default-on mutation fails it - the L4 consent test).
    static func makeModel(arguments: [String] = ProcessInfo.processInfo.arguments) -> DiagnosticsModel {
        let consentStore = DiagnosticsConsentStore()
        #if DEBUG
        if arguments.contains("-diagnosticsConsentReset") {
            consentStore.reset()
        }
        if arguments.contains("-diagnosticsConsentOn") {
            consentStore.setConsented(true)
        }
        #endif
        return DiagnosticsModel(consentStore: consentStore)
    }

    /// The preview text: exactly what the share sheet sends
    /// (`DiagnosticsBundle.rendered()`), built fresh on every preview open.
    static func makePreviewText() async -> String {
        let context = LogContext(deviceId: deviceId(),
                                 appVersion: LogContext.currentAppVersion(),
                                 platform: "ios")
        let crumbLines = (AppLog.shared.breadcrumbs?.snapshot() ?? []).map(\.rendered)
        let counts = rowCounts()
        let sync = syncSummary()
        let bundle = await Task.detached(priority: .userInitiated) {
            DiagnosticsExport.assemble(breadcrumbLines: crumbLines,
                                       context: context,
                                       osLog: OSLogStoreEntryReader(),
                                       sync: sync,
                                       rowCounts: counts)
        }.value
        return bundle.rendered()
    }

    /// The bundle's sync section source: the SAME persisted store the sync
    /// coordinator restores from (OB.3) plus the repository's derived counts -
    /// never a live coordinator, so a relaunch and a fresh read agree and the
    /// export never depends on which cycles happened to have run.
    private static func syncSummary() -> DiagnosticsSyncSummary {
        // RV.256: the store is keyed by account id. A guest has no sync state,
        // so the sync section reports none rather than a previous account's.
        let state: PersistedSyncState
        if let accountId = (try? KeychainSessionStore().load())?.accountId {
            state = UserDefaultsSyncStateStore(accountId: accountId).load()
        } else {
            state = PersistedSyncState(lastSuccessAt: nil, lastFailure: nil)
        }
        var dirty = 0
        var flagged = 0
        if let repository = try? AppStore.repository() {
            dirty = (try? repository.fetchDirtyRows())?.count ?? 0
            flagged = (try? repository.flaggedEntryCount()) ?? 0
        }
        return DiagnosticsSyncSummary(lastSuccessAt: state.lastSuccessAt,
                                      dirtyCount: dirty,
                                      flaggedCount: flagged,
                                      lastFailure: state.lastFailure)
    }

    /// Per-table physical row counts, `COUNT(*)` only (hard rule 12: counts
    /// ride, values never). A table that cannot be read contributes no row
    /// rather than failing the bundle.
    private static func rowCounts() -> [String: Int] {
        guard let repository = try? AppStore.repository() else { return [:] }
        var counts: [String: Int] = [:]
        for table in rowCountTables {
            if let count = try? repository.rowCount(in: table) {
                counts[table] = count
            }
        }
        return counts
    }

    /// The device id for the bundle's metadata line - the same Keychain read
    /// AppLog uses, so the export's own id matches the id on every log line.
    private static func deviceId() -> String? {
        (try? KeychainSessionStore().load())?.deviceId
    }
}

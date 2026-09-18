import Foundation
import Observation
import TankbookCore

/// The background photo prefetch (docs/SYNC.md -> Delivery: "blobs trickle in
/// background by recency"): after a restore or a pull that brought records,
/// the full renditions still missing on this device download newest-first
/// through the same lazy fetcher an opened entry uses. One run at a time; a
/// run that is asked for while one is in flight is dropped - the running one
/// already covers what is missing, and the next pull asks again.
///
/// It is gated where the policy says (docs/SYNC.md -> Low Power Mode) and on
/// a constrained path, and it never blocks anything: text records are usable
/// the moment they land, and an entry opened before its photo arrives
/// fetches on its own.
@MainActor
@Observable
final class BlobPrefetchService {
    static let shared = BlobPrefetchService()

    /// The last run's outcome, for the DEBUG marker a UI test waits on.
    private(set) var lastOutcome: BlobPrefetchOutcome?

    /// The path monitor's constrained flag, wired by the app root; defaults to
    /// "not constrained" so a missing wire never silences the prefetch.
    var isNetworkConstrained: @Sendable () -> Bool = { false }
    var powerState: any PowerStateProvider = ProcessInfoPowerState()

    private var task: Task<Void, Never>?

    /// Wires the Low Data Mode signal from the app's path monitor. In DEBUG
    /// this is also where `-runBlobPrefetch` starts its run.
    func attach(_ pathMonitor: AppPathMonitor) {
        isNetworkConstrained = { pathMonitor.isConstrained }
        #if DEBUG
        Self.runAtLaunchIfRequested()
        #endif
    }

    /// Starts a run. `progress`, when given, is the Restoring screen's bar.
    func start(trigger: PowerWorkTrigger, progress: RestoreProgress? = nil) {
        guard task == nil else { return }
        guard let fetcher = SyncService.makeBlobFetcher(sessionStore: KeychainSessionStore()) else { return }
        let prefetcher = BlobPrefetcher(fetcher: fetcher, powerState: powerState,
                                        isNetworkConstrained: isNetworkConstrained)
        let plan = Self.plan()
        task = Task { [weak self] in
            defer { self?.task = nil }
            let outcome = await prefetcher.run(plan: plan, trigger: trigger) { completed, total in
                Task { @MainActor in progress?.report(completed: completed, total: total) }
            }
            AppLog.shared.emit(BlobPrefetchFinished(trigger: trigger.name, outcome: outcome, planned: plan.count))
            self?.lastOutcome = outcome
        }
    }

    /// The plan: every live attachment against every live entry, availability
    /// read from the blob store and the original file - the same reads Home
    /// does on every render, cheap at this app's history sizes.
    private static func plan() -> [BlobPrefetchPlan.Item] {
        guard let repository = try? AppStore.repository(),
              let attachments = try? repository.liveAttachments(),
              let vehicles = try? repository.liveVehicles() else { return [] }
        let entries = vehicles.flatMap { (try? repository.liveEntries(forVehicle: $0.id)) ?? [] }
        return BlobPrefetchPlan.newestFirst(attachments: attachments, entries: entries,
                                            isAvailable: BlobService.isBlobAvailable)
    }
}

import SwiftUI

extension View {
    /// Overlays the DEBUG prefetch marker (`BlobPrefetchLandedMarker`); a
    /// no-op in release.
    func blobPrefetchLandedMarker() -> some View {
        #if DEBUG
        return overlay(alignment: .topLeading) { BlobPrefetchLandedMarker() }
            .overlay(alignment: .topTrailing) { PushTokenRegisteredMarker() }
        #else
        return self
        #endif
    }
}

#if DEBUG
extension BlobPrefetchService {
    /// `-runBlobPrefetch`: a UI test's stand-in for "a pull just landed" - the
    /// seeded remote photo is planted at launch and the prefetch runs on it.
    static func runAtLaunchIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-runBlobPrefetch") else { return }
        PhotoSyncingTestSeed.seedIfRequested()
        shared.start(trigger: .background)
    }
}

/// The UI-test marker for "the prefetch run finished" (`-runBlobPrefetch`): a
/// 1 pt element the AttachmentSync suite waits on before opening the entry,
/// so it proves the prefetch - not the entry's own on-open fetch - cleared the
/// shimmer.
struct BlobPrefetchLandedMarker: View {
    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("-runBlobPrefetch"),
           case .completed? = BlobPrefetchService.shared.lastOutcome {
            Text(verbatim: "·")
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityIdentifier("blobPrefetchLanded")
        }
    }
}
#endif

/// `blob.prefetch` - one line per run: the trigger, the outcome code and the
/// counts. Shape only (hard rule 12).
struct BlobPrefetchFinished: LogEvent {
    let eventName = "blob.prefetch"
    let category = LogCategory.sync
    let level = LogLevel.info
    let fields: [LogField]

    init(trigger: String, outcome: BlobPrefetchOutcome, planned: Int) {
        var fields: [LogField] = [.safe("trigger", trigger), .safe("planned", planned)]
        switch outcome {
        case .nothingToFetch:
            fields.append(.safe("outcome", "nothing_to_fetch"))
        case .deferredLowPower:
            fields.append(.safe("outcome", "deferred_low_power"))
        case .deferredConstrainedNetwork:
            fields.append(.safe("outcome", "deferred_constrained_network"))
        case .completed(let fetched, let failed):
            fields.append(.safe("outcome", "completed"))
            fields.append(.safe("fetched", fetched))
            fields.append(.safe("failed", failed))
        case .cancelled(let fetched):
            fields.append(.safe("outcome", "cancelled"))
            fields.append(.safe("fetched", fetched))
        }
        self.fields = fields
    }
}

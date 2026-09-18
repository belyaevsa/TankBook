import Foundation

// MARK: - Background photo prefetch (docs/SYNC.md -> Delivery: "blobs trickle
// in background by recency"; docs/JOURNEYS.md J11)

/// The prefetch plan: which blobs are missing on this device, newest first.
/// Recency is the owning entry's date - the photo the user is likeliest to
/// open next is the most recent one - and an attachment no entry references
/// falls back to its own creation date.
public enum BlobPrefetchPlan {
    public struct Item: Equatable, Sendable {
        public let sha256: String
        public let date: Date

        public init(sha256: String, date: Date) {
            self.sha256 = sha256
            self.date = date
        }
    }

    /// `isAvailable` answers whether the full rendition is already on the
    /// device (the cache or the original file); an available blob is never
    /// planned. Duplicate shas (one receipt shared by a grouped save) are
    /// planned once, at their newest date.
    public static func newestFirst(attachments: [Attachment], entries: [any Entry],
                                   isAvailable: (Attachment) -> Bool) -> [Item] {
        var newestEntryDate: [AttachmentID: Date] = [:]
        for entry in entries {
            for id in entry.attachments {
                newestEntryDate[id] = max(newestEntryDate[id] ?? .distantPast, entry.date)
            }
        }
        var newestBySha: [String: Date] = [:]
        for attachment in attachments where attachment.deletedAt == nil && !isAvailable(attachment) {
            let date = newestEntryDate[attachment.id] ?? attachment.createdAt
            newestBySha[attachment.file.sha256] = max(newestBySha[attachment.file.sha256] ?? .distantPast, date)
        }
        return newestBySha
            .map { Item(sha256: $0.key, date: $0.value) }
            .sorted { $0.date > $1.date }
    }
}

/// Why a prefetch run ended the way it did. Loggable as shape: counts and a
/// reason code, never a sha or a path (hard rule 12).
public enum BlobPrefetchOutcome: Equatable, Sendable {
    case nothingToFetch
    /// Deferred whole: Low Power Mode is on (docs/SYNC.md -> Low Power Mode:
    /// the heaviest work defers even inside a user-asked restore).
    case deferredLowPower
    /// Deferred whole: the path is constrained (Low Data Mode) - a prefetch
    /// the user did not ask for must not spend a metered allowance.
    case deferredConstrainedNetwork
    /// Ran to the end of the plan; `failed` blobs stay pending and the next
    /// run (or opening the entry) retries them.
    case completed(fetched: Int, failed: Int)
    case cancelled(fetched: Int)
}

/// Runs a plan through the lazy fetcher, one blob at a time, reporting
/// monotonic progress. The two gates are checked once, up front: a run that
/// starts is allowed to finish, so a bar never stalls halfway because the
/// mode flipped - the next trigger re-asks.
public struct BlobPrefetcher: Sendable {
    public let fetcher: LazyBlobFetcher
    public let powerState: any PowerStateProvider
    public let isNetworkConstrained: @Sendable () -> Bool

    public init(fetcher: LazyBlobFetcher, powerState: any PowerStateProvider,
                isNetworkConstrained: @escaping @Sendable () -> Bool) {
        self.fetcher = fetcher
        self.powerState = powerState
        self.isNetworkConstrained = isNetworkConstrained
    }

    /// `progress(completed, total)` fires after each blob, completed never
    /// decreasing. Cancellation between blobs ends the run with what it has.
    public func run(plan: [BlobPrefetchPlan.Item], trigger: PowerWorkTrigger,
                    progress: @Sendable (Int, Int) -> Void) async -> BlobPrefetchOutcome {
        guard !plan.isEmpty else { return .nothingToFetch }
        if LowPowerPolicy.defers(work: .blobPrefetch, trigger: trigger,
                                 lowPowerMode: powerState.isLowPowerModeEnabled) {
            return .deferredLowPower
        }
        if isNetworkConstrained() { return .deferredConstrainedNetwork }

        var fetched = 0
        var failed = 0
        progress(0, plan.count)
        for (index, item) in plan.enumerated() {
            if Task.isCancelled { return .cancelled(fetched: fetched) }
            if (try? await fetcher.fetch(sha256: item.sha256)) != nil {
                fetched += 1
            } else {
                failed += 1
            }
            progress(index + 1, plan.count)
        }
        return .completed(fetched: fetched, failed: failed)
    }
}

import Foundation

// The feedback queue (docs/ERRORS.md -> About & feedback: queued-offline, hard
// rule 8 - nothing is lost silently). A case is enqueued only with consent
// (hard rule 13 + the load-bearing rule); without it `enqueue` refuses and the
// queue stays empty. Persistence is injected so tests build a fresh instance
// over the same store and a persistence bug is visible rather than assumed away.

/// One queued feedback case: a stable id plus its payload. The id (not the
/// payload's contents) is what the outbox uses to remove the case after a send.
public struct FeedbackItem: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let payload: FeedbackPayload

    public init(id: UUID = UUID.v7(), payload: FeedbackPayload) {
        self.id = id
        self.payload = payload
    }
}

/// Where a queued case is persisted. The queue reads it once at construction
/// and writes on every mutation, so a relaunch (or a fresh queue over the same
/// store) resumes the offline queue.
public protocol FeedbackQueueStore: Sendable {
    func load() -> [FeedbackItem]
    func save(_ items: [FeedbackItem])
}

/// The test double: session-scoped, nothing survives the process.
public final class InMemoryFeedbackQueueStore: FeedbackQueueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [FeedbackItem] = []

    public init() {}

    public func load() -> [FeedbackItem] {
        lock.lock(); defer { lock.unlock() }
        return items
    }

    public func save(_ items: [FeedbackItem]) {
        lock.lock(); defer { lock.unlock() }
        self.items = items
    }
}

/// The production store: one JSON file per install, in the app container. The
/// file holds user content (the feedback text), so it lives beside the database
/// under the same file protection (docs/SECURITY.md).
public final class FileFeedbackQueueStore: FeedbackQueueStore, @unchecked Sendable {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func load() -> [FeedbackItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([FeedbackItem].self, from: data)) ?? []
    }

    public func save(_ items: [FeedbackItem]) {
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// A consent-gated, persisted queue of feedback cases.
public actor FeedbackQueue {
    private let consentStore: FeedbackConsentStore
    private let store: any FeedbackQueueStore
    private var items: [FeedbackItem]

    public init(consentStore: FeedbackConsentStore, store: any FeedbackQueueStore) {
        self.consentStore = consentStore
        self.store = store
        self.items = store.load()
    }

    /// Enqueues a case. Returns its id, or nil when the user has not consented -
    /// the consent gate (docs/ERRORS.md -> About & feedback, hard rule 13). The
    /// default is off, so nothing is queued until the user opts in.
    @discardableResult
    public func enqueue(_ payload: FeedbackPayload) -> UUID? {
        guard consentStore.hasConsented else { return nil }
        let item = FeedbackItem(payload: payload)
        items.append(item)
        store.save(items)
        return item.id
    }

    /// The queued cases, oldest first (the order they will be retried).
    public func pending() -> [FeedbackItem] {
        items
    }

    /// Removes a case by id after it has been sent (or dropped).
    public func remove(id: UUID) {
        items.removeAll { $0.id == id }
        store.save(items)
    }
}

import Foundation
import Observation
import TankbookCore

// MARK: - RV.38 the device-local inbox (docs/JOURNEYS.md F4, amended)
//
// The app's one home for work that finished after the user moved on. The first
// producer is the cloud-reading gateway: an answer that lands AFTER the entry
// was saved no longer dies in `markSaved()`; it becomes an inbox item the user
// accepts, edits or declines - "leave it as it is" is the default (hard rule
// 13). The decision lives in core (`GatewayInboxPolicy`); this store owns the
// items, their persistence, and the resolution writes.
//
// Durability is now a backend matter (RV.44): an answer the device never
// received is queued in the per-device delivery outbox and drained here on
// launch/foreground (`drainOutbox`), through the SAME `GatewayInboxPolicy.item`
// the in-process path uses - one policy, not two. An answer that DID arrive is
// persisted here (UserDefaults, JSON) and survives relaunch; the drain is
// at-least-once and dedupes by row id, so a redelivered answer never becomes a
// second item.
@MainActor
@Observable
final class AppInbox {
    /// The pending items, newest first.
    private(set) var items: [GatewayInboxItem] = []
    /// Called after an accepted update so Home reloads its derived stats
    /// (hard rule 2) - the same `noteEntryChanged` every save uses.
    private let noteEntryChanged: () -> Void

    /// Internal (not private) so `InboxTestSeed` writes the seeded item through
    /// the same key the store reads.
    static let storageKey = "inbox.items"

    init(noteEntryChanged: @escaping () -> Void) {
        self.noteEntryChanged = noteEntryChanged
        load()
    }

    /// The badge count the bell renders. Derived, never stored (hard rule 2's
    /// spirit - the count is the items' count, not a separate counter that can
    /// drift).
    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    /// The entry ids with a pending item - the entry's OWN badge (hard rule 8:
    /// the bell is a second route, never the only place a problem is visible).
    var pendingEntryIDs: Set<UUID> { Set(items.map(\.entryId)) }

    func hasItem(for entryID: UUID) -> Bool {
        pendingEntryIDs.contains(entryID)
    }

    /// The saved entry an item is about, looked up fresh so the card renders
    /// "yours" as the entry stands NOW, not as it stood when the answer arrived.
    /// `nil` when the entry no longer exists (docs/ERRORS.md -> Inbox).
    func fillUp(for item: GatewayInboxItem) -> FillUp? {
        guard let repository = try? AppStore.repository() else { return nil }
        return try? repository.fillUp(id: item.entryId)
    }

    // MARK: - Recording

    /// A late gateway answer for a saved entry. The policy decides whether it is
    /// worth an item; an answer that agrees with what the user saved is noise,
    /// not work.
    func recordLateGatewayAnswer(_ extraction: GatewayExtraction, entryID: UUID) {
        guard let repository = try? AppStore.repository(),
              let entry = try? repository.fillUp(id: entryID),
              let item = GatewayInboxPolicy.item(extraction: extraction, entry: entry) else { return }
        insert(item)
    }

    // MARK: - The delivery outbox (RV.44)

    /// Drains the device's delivery outbox and feeds each row through the SAME
    /// inbox path the in-process late answer uses (`GatewayInboxPolicy.item` -
    /// one policy, not two). Best-effort: signed-in only, and a failure is
    /// swallowed so the next launch retries - no screen is gated on this (hard
    /// rule 1). Each drained row is acked after processing, so a row that
    /// produced no item (its entry was never saved) does not accumulate forever.
    func drainOutbox() async {
        guard let client = Self.makeOutboxClient() else { return }
        let entries: [GatewayOutboxEntry]
        do {
            entries = try await client.drain()
        } catch {
            return
        }
        for entry in entries {
            ingestOutboxEntry(entry)
        }
        for entry in entries {
            try? await client.ack(id: entry.id)
        }
    }

    /// Feeds one drained outbox entry into the inbox. The payload's captureId is
    /// the entry id; the item is the same shape the in-process path produces.
    /// The item keeps the outbox row's id, so a re-drained row (at-least-once
    /// delivery) dedupes to the same item instead of a second one.
    private func ingestOutboxEntry(_ entry: GatewayOutboxEntry) {
        guard !items.contains(where: { $0.id == entry.id }),
              let repository = try? AppStore.repository(),
              let entryID = entry.payload.captureId,
              let fillUp = try? repository.fillUp(id: entryID),
              var item = GatewayInboxPolicy.item(extraction: entry.payload.extraction, entry: fillUp) else {
            return
        }
        item.id = entry.id
        insert(item)
    }

    /// Builds the outbox client, signed-in only (the outbox requires an account,
    /// so a guest has nothing to drain). nil also when the session is
    /// auth-expired - the same arming gate the gateway capture uses (RV.26).
    /// The transport goes through `makeAppTransport`, so a seeded DEBUG launch
    /// drains against the offline transport (and finds nothing) instead of a
    /// real network call, exactly like sync.
    private static func makeOutboxClient() -> GatewayOutboxClient? {
        let store = KeychainSessionStore()
        guard GatewayArming.shouldArm(sessionStore: store) else { return nil }
        let httpClient = TankbookHTTPClient(
            transport: makeAppTransport(),
            tokenProvider: KeychainTokenProvider(sessionStore: store),
            refresher: AppSessionRefresher.shared)
        return GatewayOutboxClient(httpClient: httpClient, director: AppConfigStore.shared.director)
    }

    private func insert(_ item: GatewayInboxItem) {
        items.insert(item, at: 0)
        persist()
    }

    // MARK: - Resolution

    /// How the user answered the item's ask. `.update` takes exactly the fields
    /// the user TICKED (hard rule 13: the user decides per field, never the
    /// app); `.leaveAsIs` and `.replaceReceipt` change nothing - the latter
    /// routes the user to the entry, where the receipt lives.
    enum Resolution: Equatable {
        case update(fields: Set<FieldRef>)
        case leaveAsIs
        case replaceReceipt
    }

    /// Resolves an item: the item clears and does not return, and an accepted
    /// update applies the per-field merge to the entry the item routed to
    /// (never silently - the user just tapped it).
    func resolve(_ item: GatewayInboxItem, as resolution: Resolution) {
        defer { remove(item) }
        guard case let .update(fields) = resolution else { return }
        guard let repository = try? AppStore.repository(),
              let entry = try? repository.fillUp(id: item.entryId) else { return }
        let merged = GatewayInboxPolicy.merged(entry: entry, extraction: item.extraction, taking: fields)
        try? repository.upsertFillUp(merged)
        noteEntryChanged()
    }

    private func remove(_ item: GatewayInboxItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    // MARK: - Persistence (UserDefaults, device-local, never synced)

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let rows = try? JSONDecoder().decode([GatewayInboxItem].self, from: data) else {
            return
        }
        items = rows.sorted { $0.createdAt > $1.createdAt }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// Test-only: clear the inbox so a UI test starts from the same place
    /// (UserDefaults survive `-homeResetDatabase`, which wipes only the DB).
    #if DEBUG
    static func resetForTestsIfRequested(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard arguments.contains("-inboxReset") else { return }
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
    #endif
}

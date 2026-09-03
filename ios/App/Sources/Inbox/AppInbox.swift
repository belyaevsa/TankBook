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
// BEST-EFFORT, device-local, and honest about it: the extraction lives on the
// device (rule 9 - the gateway holds no conversation), so an app killed
// mid-request loses the answer. A durable re-read would mean a read endpoint
// over RV.33's ledger, and RV.33's own amendment says the ledger is "written by
// the gateway and read by no endpoint" - adding one is a second rule-9 reversal
// that belongs to the product owner, not an agent. So an answer that DID arrive
// is persisted here (UserDefaults, JSON) and survives relaunch; an answer that
// never arrived is simply absent, and the inbox never promises otherwise.
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

    // MARK: - Recording

    /// A late gateway answer for a saved entry. The policy decides whether it is
    /// worth an item; an answer that agrees with what the user saved is noise,
    /// not work.
    func recordLateGatewayAnswer(_ extraction: GatewayExtraction, entryID: UUID) {
        guard let repository = try? AppStore.repository(),
              let entry = try? repository.fillUp(id: entryID) else { return }
        guard GatewayInboxPolicy.shouldOffer(extraction: extraction, entry: entry) else { return }
        let item = GatewayInboxItem(id: UUID.v7(), entryId: entryID,
                                    createdAt: Date(), extraction: extraction)
        items.insert(item, at: 0)
        persist()
    }

    // MARK: - Resolution

    /// How the user answered the item's ask. `.update` fills blank fields only
    /// (hard rule 13); `.leaveAsIs` and `.replaceReceipt` change nothing - the
    /// latter routes the user to the entry, where the receipt lives.
    enum Resolution: Equatable {
        case update
        case leaveAsIs
        case replaceReceipt
    }

    /// Resolves an item: the item clears and does not return, and an accepted
    /// update applies the blank-fields-only merge to the entry the item routed
    /// to (never silently - the user just tapped it).
    func resolve(_ item: GatewayInboxItem, as resolution: Resolution) {
        defer { remove(item) }
        guard resolution == .update else { return }
        guard let repository = try? AppStore.repository(),
              let entry = try? repository.fillUp(id: item.entryId) else { return }
        let merged = GatewayInboxPolicy.merged(entry: entry, extraction: item.extraction)
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

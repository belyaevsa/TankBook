import Foundation

/// The parts shelf and install linking (docs/JOURNEYS.md J7b, docs/SCHEMA.md ->
/// Expense.installedInServiceId). Pure decisions, no persistence - the view and
/// its tests share these rules, exactly as `ServiceEntryDraft` shares the
/// ServiceEntry form's.
///
/// The load-bearing invariant (docs/PHASES.md, P3 exit gate): a part's cost
/// counts ONCE, at purchase. Linking a part to a service is provenance, never a
/// price - `usedParts` and `installedInServiceId` point at each other and carry
/// no money, so linking can never change cost/km. Every function here moves the
/// link, never an amount.
public enum PartsShelf {

    // MARK: Shelf membership

    /// The shelf: `.parts` expenses not currently installed in a live service.
    /// `liveServiceIds` are the ids of the live (non-deleted) `ServiceRecord`s.
    ///
    /// A part whose `installedInServiceId` points at a deleted service is back
    /// on the shelf (J7b: deleting a service returns its parts rather than
    /// stranding them). That is DERIVED, never written - so restoring the
    /// service re-links the part for free (the id is still recorded on the
    /// expense, nothing was lost silently). Newest purchase first: the part you
    /// just bought is the one you are most likely to install next.
    public static func onShelf(expenses: [Expense], liveServiceIds: Set<UUID>) -> [Expense] {
        expenses
            .filter { isOnShelf($0, liveServiceIds: liveServiceIds) }
            .sorted { shelfOrder($0, $1) }
    }

    /// Whether a single expense is currently on the shelf. Non-`.parts` expenses
    /// are never on the shelf - the shelf is only ever parts.
    public static func isOnShelf(_ expense: Expense, liveServiceIds: Set<UUID>) -> Bool {
        guard expense.category == .parts else { return false }
        guard let installed = expense.installedInServiceId else { return true }
        return !liveServiceIds.contains(installed)
    }

    // MARK: Linking (pure: moves the link, never money)

    /// Links `expense` into `service`: sets the expense's `installedInServiceId`
    /// and appends its id to the service's `usedParts`. Both sides, one action,
    /// and neither amount is touched - the cost stays with the purchase.
    public static func link(_ expense: Expense, to service: ServiceRecord) -> (Expense, ServiceRecord) {
        var linked = expense
        var record = service
        linked.installedInServiceId = service.id
        if !record.usedParts.contains(expense.id) {
            record.usedParts.append(expense.id)
        }
        return (linked, record)
    }

    /// Unlinks `expense` from `service`: clears `installedInServiceId` and
    /// removes the id from `usedParts`. The part returns to the shelf with its
    /// purchase cost untouched.
    public static func unlink(_ expense: Expense, from service: ServiceRecord) -> (Expense, ServiceRecord) {
        var linked = expense
        var record = service
        linked.installedInServiceId = nil
        record.usedParts.removeAll { $0 == expense.id }
        return (linked, record)
    }

    // MARK: Suggestion matching (J7b: the next matching service suggests them)

    /// The keywords a service line-item category matches against a part's title.
    /// Deliberately coarse and explainable: the app only ORDERS suggestions, the
    /// user picks, nothing links automatically (hard rule 13).
    public static func keywords(for category: ServiceCategory) -> [String] {
        switch category {
        case .oil: ["oil"]
        case .brakes: ["brake", "pad", "disc", "rotor"]
        case .filters: ["filter", "air", "cabin"]
        case .tires: ["tire", "tyre"]
        case .battery: ["battery"]
        case .inspection, .repair, .parts, .wash, .other: []
        }
    }

    /// Orders shelf parts so those matching any of the service's line-item
    /// categories come first, then the rest - a service with an `.oil` item
    /// offers oil parts first. A part matches when its title contains a category
    /// keyword (case-insensitive). Newest first within each group.
    public static func suggested(_ shelf: [Expense], categories: [ServiceCategory]) -> [Expense] {
        let keywords = categories.flatMap(keywords(for:)).map { $0.lowercased() }
        guard !keywords.isEmpty else { return shelf.sorted(by: shelfOrder) }
        func matches(_ expense: Expense) -> Bool {
            let title = expense.title.lowercased()
            return keywords.contains { !$0.isEmpty && title.contains($0) }
        }
        return shelf.sorted { a, b in
            if matches(a) != matches(b) { return matches(a) }
            return shelfOrder(a, b)
        }
    }

    // MARK: Ordering

    /// Newest purchase first, ties broken by id for determinism.
    private static func shelfOrder(_ a: Expense, _ b: Expense) -> Bool {
        if a.date != b.date { return a.date > b.date }
        return a.id.uuidString < b.id.uuidString
    }
}

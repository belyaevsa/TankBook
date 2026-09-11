import Foundation

/// The post-save "remind you next time?" proposal (docs/JOURNEYS.md J7d
/// "Just did it", RV.77). After a ServiceRecord or Expense saves, the app may
/// OFFER to create the next reminder - never create it silently (hard rule 13).
///
/// Three rules shape this type, each mirroring an existing lifecycle decision
/// so the offer and the list can never disagree:
///
/// 1. **The offer is anchored at the RECORD, never at today.** The next
///    occurrence's due fields are `record.date + interval` and
///    `record.odometer + interval`, exactly as `ReminderLifecycle.complete`
///    anchors the next occurrence at the COMPLETION - the no-drift rule.
/// 2. **A category with no sensible interval offers nothing.** The default
///    interval is a curated, compiled table (tier C, docs/PRACTICES.md): a
///    suggestion the user edits in the same breath, never a fact. If the
///    record's category maps to no interval, there is nothing honest to offer.
/// 3. **The offer is suppressed when a live reminder of that category already
///    exists on that car** - the "three oil reminders" failure mode. A live
///    reminder is one `ReminderLifecycle.isActive` says is still on the books
///    (scheduled or attention); terminal rows are history and do not suppress.
///
/// Everything here is pure and L1-testable; the save paths in the app fetch the
/// car's live reminders and hand them in.
public enum ReminderOffer {

    /// The driving category of a saved record plus the default interval a
    /// category-based reminder would carry. The offer sheet edits `everyKm` /
    /// `everyMonths` in the same breath (hard rule 13); these are the starting
    /// values.
    public struct Proposal: Equatable, Sendable {
        public var vehicleId: UUID
        public var category: ReminderCategory
        /// The reminder's title default: the record's own words (the driving
        /// line item's title, or the expense's title). Never an invented
        /// phrase - the user's text is already localized.
        public var title: String
        /// The record that spawned the proposal - becomes the reminder's
        /// `sourceEntryId`, the anchor for the whole chain.
        public var sourceEntryId: UUID
        /// The record's date and odometer: the anchor. Never `Date()`.
        public var date: Date
        public var odometer: Int?
        /// The curated default interval (a suggestion, never a fact).
        public var everyKm: Int?
        public var everyMonths: Int?

        public init(vehicleId: UUID, category: ReminderCategory, title: String,
                    sourceEntryId: UUID, date: Date, odometer: Int?,
                    everyKm: Int?, everyMonths: Int?) {
            self.vehicleId = vehicleId
            self.category = category
            self.title = title
            self.sourceEntryId = sourceEntryId
            self.date = date
            self.odometer = odometer
            self.everyKm = everyKm
            self.everyMonths = everyMonths
        }
    }

    /// One titled line item that states an interval, with the interval it
    /// carries and whether that interval came from the item's own `lifetime`
    /// (explicit) or the curated category default (a fallback). The explicit
    /// one drives the offer when a category has several rows.
    private struct Driving {
        let category: ReminderCategory
        let interval: Reminder.Recurrence
        let title: String
        let explicit: Bool
    }

    // MARK: - Curated default intervals (tier C, compiled)

    /// The curated per-category default interval (docs/PRACTICES.md -> section 6:
    /// a compiled constant whose meaning is fixed and reviewed; docs/SCHEMA.md
    /// -> Reminder records the table and why each number is what it is). A
    /// category ABSENT from this table has no sensible universal interval - the
    /// offer fires nothing for it, rather than guessing a cadence and dressing
    /// it as a fact (hard rule 13). This is the FALLBACK: an item that carries
    /// its own `lifetime` states the interval itself and overrides the table
    /// (PJ.22 - the user's number, hard rule 13).
    ///
    /// Why these two and not the rest:
    /// - **oil** - 15,000 km / 12 months: the app's own documented oil-change
    ///   cadence ("Oil change in 15,000 km or 12 months" - JOURNEYS.md J7/J7c,
    ///   VISION.md, the ReminderComplete artboard) and the value the seeds use.
    /// - **insurance** - 12 months: annual policy renewal (SCHEMA.md's
    ///   "yearly insurance auto-suggests next entry + reminder"; insurance is
    ///   the one recurring *Expense* category).
    ///
    /// Everything else (brakes, filters, tires, battery, inspection, repair,
    /// parts, wash, custom, other) has no interval a service network would
    /// agree on: brakes and tires are wear/seasonal, filters vary by part, and
    /// inspection cadence is jurisdiction law, not a schedule. Offering a
    /// number there would be inventing a fact; the Reminders form remains the
    /// honest door for those.
    public static func defaultInterval(for category: ReminderCategory) -> Reminder.Recurrence? {
        switch category {
        case .oil: return Reminder.Recurrence(everyKm: 15_000, everyMonths: 12)
        case .insurance: return Reminder.Recurrence(everyKm: nil, everyMonths: 12)
        case .brakes, .tires, .battery, .filters, .inspection, .repair,
             .parts, .wash, .custom, .other: return nil
        }
    }

    /// The seasonal swap cadence a tire MOUNT anchors (docs/JOURNEYS.md J7b
    /// "the swap reminder each season", docs/NOTIFICATIONS.md -> "tire season").
    /// A set goes on for a season and comes off about half a year later, so the
    /// next swap is six months after the mount. This is deliberately NOT in the
    /// per-category table above: a `.tires` line item (a rotation, an
    /// alignment) still has no universal cadence, and only a record that
    /// actually mounts a set (`ServiceRecord.tireSetId`) carries this one. The
    /// number is a suggestion the user edits in the same breath (hard rule 13),
    /// never a fact.
    public static let seasonalSwapMonths = 6

    /// The reminder-category twin of a service line-item category
    /// (docs/SCHEMA.md -> ServiceItem.category vs Reminder.category share the
    /// fixed vocabulary). `.other(String)` free text maps to `.other` - and has
    /// no interval, so it offers nothing.
    public static func reminderCategory(for serviceCategory: ServiceCategory) -> ReminderCategory? {
        switch serviceCategory {
        case .oil: return .oil
        case .brakes: return .brakes
        case .tires: return .tires
        case .battery: return .battery
        case .filters: return .filters
        case .inspection: return .inspection
        case .repair: return .repair
        case .parts: return .parts
        case .wash: return .wash
        case .other: return nil
        }
    }

    /// The reminder category a titled SERVICE item proposes. A fixed service
    /// category maps to its twin; an `.other` free-text row maps to
    /// `.other(text)` only when the row carries an explicit lifetime - the
    /// lifetime is what makes a free-text row schedulable, and without one
    /// there is no interval to offer.
    private static func reminderCategory(for item: ServiceItem,
                                         explicitLifetime: Bool) -> ReminderCategory? {
        if let mapped = reminderCategory(for: item.category) { return mapped }
        if case .other(let text) = item.category, explicitLifetime { return .other(text) }
        return nil
    }

    /// The interval an item's own `lifetime` states, or nil when neither half is
    /// a positive number. A zero (or a negative) is treated as unset - entering
    /// "0" is a no-op, not a burst (the same rule as `ReminderDraft.recurrence`).
    private static func recurrence(from lifetime: ServiceItem.Lifetime) -> Reminder.Recurrence? {
        let km = lifetime.km.flatMap { $0 > 0 ? $0 : nil }
        let months = lifetime.months.flatMap { $0 > 0 ? $0 : nil }
        guard km != nil || months != nil else { return nil }
        return Reminder.Recurrence(everyKm: km, everyMonths: months)
    }

    /// The reminder-category twin of an Expense category. `.insurance` is the
    /// only recurring expense (docs/SCHEMA.md -> Expense.recurrence); `.parts`
    /// bought on the shelf is inventory, never a schedule, and the rest are
    /// one-off costs with no cadence at all.
    public static func reminderCategory(for expenseCategory: ExpenseCategory) -> ReminderCategory? {
        switch expenseCategory {
        case .insurance: return .insurance
        case .tax, .parking, .toll, .fine, .accessory, .parts, .other: return nil
        }
    }

    // MARK: - The pure decision

    /// Whether a proposal for the given category is suppressed by a live
    /// reminder of that category on the same car (rule 3). Terminal rows
    /// (`.done`/`.dismissed`) are history, not an existing reminder.
    public static func isSuppressed(category: ReminderCategory,
                                    vehicleId: UUID,
                                    liveReminders: [Reminder]) -> Bool {
        liveReminders.contains { reminder in
            reminder.vehicleId == vehicleId
                && reminder.category == category
                && ReminderLifecycle.isActive(reminder)
        }
    }

    /// The proposal after a ServiceRecord saves, or nil when there is nothing
    /// to offer.
    ///
    /// A record that MOUNTS a tire set (`tireSetId != nil`) is the seasonal
    /// swap: it proposes a `.tires` reminder anchored at the mount date,
    /// recurring by `seasonalSwapMonths`. This branch wins over the line-item
    /// rule because the mount is the event; `tireSetName` is the set's own name
    /// (the user's words, already localized) and the offer carries nothing when
    /// the set cannot be named.
    ///
    /// Otherwise the offer needs a SINGLE driving category, so only records
    /// whose titled line items reduce to exactly one interval-bearing category
    /// propose. A record that mixes two schedulable categories (oil AND
    /// inspection on one invoice) proposes nothing rather than silently
    /// choosing one for the user (hard rule 13); a record with an oil item plus
    /// uncategorized rows proposes oil.
    ///
    /// **An item's own lifetime wins over the category table** (PJ.22). The
    /// lifetime editor on a line item lets the user state the exact cadence for
    /// that part, so a `.brakes` row with a lifetime IS schedulable even though
    /// `.brakes` has no universal default - the interval is no longer a guess.
    /// When several rows of the one category carry intervals, the first with an
    /// explicit lifetime drives the offer; the category default is the fallback
    /// for rows that state none.
    public static func propose(afterService service: ServiceRecord,
                               tireSetName: String? = nil,
                               liveReminders: [Reminder]) -> Proposal? {
        if service.tireSetId != nil {
            let name = tireSetName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty,
                  !isSuppressed(category: .tires,
                                vehicleId: service.vehicleId,
                                liveReminders: liveReminders) else { return nil }
            return Proposal(vehicleId: service.vehicleId,
                            category: .tires,
                            title: name,
                            sourceEntryId: service.id,
                            date: service.date,
                            odometer: service.odometer,
                            everyKm: nil,
                            everyMonths: seasonalSwapMonths)
        }
        // The titled items that state an interval, each with the interval it
        // carries. Untitled rows are blanks, not a driving category.
        let driving = service.items.compactMap { item -> Driving? in
            let title = item.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            let explicitInterval = item.lifetime.flatMap(recurrence(from:))
            guard let category = reminderCategory(for: item,
                                                  explicitLifetime: explicitInterval != nil),
                  let interval = explicitInterval ?? defaultInterval(for: category)
            else { return nil }
            return Driving(category: category, interval: interval, title: title,
                           explicit: explicitInterval != nil)
        }
        let distinct = Set(driving.map { $0.category })
        guard distinct.count == 1, let category = distinct.first,
              !isSuppressed(category: category,
                            vehicleId: service.vehicleId,
                            liveReminders: liveReminders),
              let chosen = driving.first(where: { $0.explicit }) ?? driving.first
        else { return nil }

        return Proposal(vehicleId: service.vehicleId,
                        category: category,
                        title: chosen.title,
                        sourceEntryId: service.id,
                        date: service.date,
                        odometer: service.odometer,
                        everyKm: chosen.interval.everyKm,
                        everyMonths: chosen.interval.everyMonths)
    }

    /// The proposal after an Expense saves, or nil. `.insurance` is the only
    /// expense category with a cadence (annual), so it is the only expense that
    /// offers. An insurance expense is usually standalone, so its own title
    /// anchors the reminder.
    public static func propose(afterExpense expense: Expense,
                               liveReminders: [Reminder]) -> Proposal? {
        guard let category = reminderCategory(for: expense.category),
              !isSuppressed(category: category,
                            vehicleId: expense.vehicleId,
                            liveReminders: liveReminders),
              let interval = defaultInterval(for: category) else { return nil }
        return Proposal(vehicleId: expense.vehicleId,
                        category: category,
                        title: expense.title,
                        sourceEntryId: expense.id,
                        date: expense.date,
                        odometer: expense.odometer,
                        everyKm: interval.everyKm,
                        everyMonths: interval.everyMonths)
    }

    // MARK: - Acceptance

    /// Whether an accepted offer can create a reminder. A reminder needs at
    /// least one due field (docs/SCHEMA.md); the months half always anchors on
    /// the record's date, while the km half anchors only when the record has an
    /// odometer - otherwise a km-only interval would produce a reminder with
    /// neither due field. Mirrors `ReminderDraft.readiness`.
    public enum Acceptance: Equatable, Sendable {
        case ready
        case noDueField
    }

    /// Builds the accepted reminder ANCHORED at the record (rule 1) - never at
    /// today. `everyKm`/`everyMonths` are the interval the user accepted (the
    /// sheet's editable fields). Returns the `Reminder` to persist, or nil when
    /// neither due field can be computed.
    public static func acceptance(everyKm: Int?, everyMonths: Int?,
                                  odometer: Int?) -> Acceptance {
        let months = everyMonths.flatMap { $0 > 0 ? $0 : nil }
        let km = everyKm.flatMap { $0 > 0 ? $0 : nil }
        if months != nil { return .ready }
        if km != nil && odometer != nil { return .ready }
        return .noDueField
    }

    /// The reminder an accepted offer creates. Mirrors the anchor arithmetic of
    /// `ReminderLifecycle.complete`'s next occurrence: due date = record date +
    /// months, due odometer = record odometer + km (only when the record has an
    /// odometer), recurrence = the interval the user accepted, sourceEntryId =
    /// the record. `.scheduled`, never a status the user must then clear.
    public static func reminder(accepting proposal: Proposal,
                                everyKm: Int?,
                                everyMonths: Int?,
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Reminder? {
        let months = everyMonths.flatMap { $0 > 0 ? $0 : nil }
        let km = everyKm.flatMap { $0 > 0 ? $0 : nil }
        guard months != nil || (km != nil && proposal.odometer != nil) else { return nil }

        var dueDate: Date?
        if let months {
            dueDate = calendar.date(byAdding: .month, value: months, to: proposal.date)
        }
        var dueOdometer: Int?
        if let km, let odometer = proposal.odometer {
            dueOdometer = odometer + km
        }

        return Reminder(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: proposal.vehicleId,
            title: proposal.title,
            category: proposal.category,
            dueDate: dueDate,
            dueOdometer: dueOdometer,
            recurrence: Reminder.Recurrence(everyKm: km, everyMonths: months),
            sourceEntryId: proposal.sourceEntryId,
            status: .scheduled)
    }
}

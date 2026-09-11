import Foundation

/// Why an entry is out of the derived figures (docs/ERRORS.md -> Home, the
/// "N entries excluded" footnote). The two causes carry different fixes, which
/// is why any list of excluded entries must say which one each row is: a
/// timeline conflict (F9a/S3) is fixed by editing the odometer or the date; an
/// unresolved duplicate (S2) is resolved by Merge or Keep both on its combined
/// card (docs/SYNC.md S2/S3).
public enum EntryExclusionReason: Equatable, Sendable {
    /// The entry's odometer/date breaks the timeline, so its segment is out of
    /// the headline and it is excluded from the figures (docs/SYNC.md S3).
    case timelineConflict
    /// The entry's segment implies a consumption outside the vehicle's plausible
    /// band (CHECK 5, the F2 residue). The odometer and date are internally
    /// consistent, so the field to question is the litres or the odometer, not
    /// the date - a different next step from `.timelineConflict`.
    case consumptionOutlier
    /// The entry is the non-counting member of an unresolved duplicate pair
    /// (docs/SYNC.md S2: until the user decides, only one member counts).
    case unresolvedDuplicate
}

/// One entry the derived figures leave out, with the reason it is out. This is
/// the population the "N entries excluded" footnote counts, and a destination
/// the footnote opens must list exactly these: a list that shows fewer (or
/// more) rows than the count promised is the same lie one layer down (RV.141).
public struct ExcludedEntry: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let date: Date
    public let reason: EntryExclusionReason

    public init(id: UUID, date: Date, reason: EntryExclusionReason) {
        self.id = id
        self.date = date
        self.reason = reason
    }
}

/// The one derivation of the excluded population, shared by the footnote's
/// count (`HomeStats.excludedEntryCount`) and the list the count opens. A count
/// and its destination computed by two different code paths was the defect: the
/// footnote counted unresolved-duplicate members while the "Needs a look" list
/// showed conflicts only, so routing the count into that list would have shown
/// fewer rows than the count promised. Deriving ONCE in core keeps the two in
/// agreement by construction.
public enum ExcludedEntries {
    /// The excluded entries among `entries`, newest first: every conflict-
    /// flagged entry plus the non-counting member of every unresolved duplicate
    /// pair. A conflicted entry that is ALSO a duplicate's excluded member is
    /// reported as a conflict - the more severe of the two reasons - and counted
    /// once (the union, exactly what `HomeStats` excludes).
    public static func derive(in entries: [any Entry],
                              duplicatePairs: [DuplicateDetector.Pair]) -> [ExcludedEntry] {
        let duplicateExcluded = Set(duplicatePairs.map(\.excludedID))
        return entries.compactMap { entry in
            let reason: EntryExclusionReason
            if case .flagged(let kind, _) = entry.conflict {
                reason = kind == .consumption ? .consumptionOutlier : .timelineConflict
            } else if duplicateExcluded.contains(entry.id) {
                reason = .unresolvedDuplicate
            } else {
                return nil
            }
            return ExcludedEntry(id: entry.id, date: entry.date, reason: reason)
        }
        .sorted { $0.date > $1.date }
    }
}

import Foundation

/// The S2 duplicate heuristic (docs/SYNC.md, S2): two fill-ups are a possible
/// duplicate of ONE physical fill when they share a vehicle, their dates are
/// within 30 minutes, and their volumes within 5%. No extra signals (station,
/// price, odometer) and no loosened bounds - changing the heuristic is a spec
/// decision in docs/SYNC.md, not an implementation one.
///
/// Purely derived: the same entry list always yields the same pairs, so the
/// statistics can be honest while the user has not decided (only one entry of a
/// pair counts - docs/SYNC.md S2: "Until resolved, only ONE of the pair counts
/// in consumption and totals"), and every device computes identical numbers
/// (docs/SCHEMA.md, Recalculation on edit: "stats are a deterministic pure
/// function of the entry list").
public enum DuplicateDetector {

    /// A flagged duplicate pair of fill-ups. `countedID` is the entry that
    /// counts in every derived figure while the pair is unresolved; `excludedID`
    /// is the one that is set aside until the user decides.
    public struct Pair: Equatable, Sendable, Identifiable {
        public let countedID: UUID
        public let excludedID: UUID
        public let vehicleID: UUID

        public var id: UUID { countedID }

        /// Order-independent identity of the pair: `{counted, excluded}` as a
        /// canonical (low, high) key, so a "keep both" resolution recorded
        /// against one ordering still suppresses the pair if the counted /
        /// excluded roles ever change.
        public var key: PairKey {
            if countedID.uuidString < excludedID.uuidString {
                return PairKey(low: countedID, high: excludedID)
            }
            return PairKey(low: excludedID, high: countedID)
        }
    }

    /// Canonical, order-independent identity of a pair (see `Pair.key`).
    public struct PairKey: Hashable, Sendable {
        public let low: UUID
        public let high: UUID

        public init(low: UUID, high: UUID) {
            self.low = low
            self.high = high
        }
    }

    /// Flags the duplicate pairs among the given fills, skipping pairs the user
    /// has already resolved as "keep both" (`resolved`).
    ///
    /// Pairs are discovered greedily in chronological order and are disjoint: a
    /// fill belongs to at most one pair. The input order never matters - every
    /// comparison sorts first, so the same data yields the same pairs in either
    /// order.
    ///
    /// Fills that share a `purchaseGroupId` are intentionally excluded from
    /// detection: a purchase group is one physical receipt by construction
    /// (docs/SCHEMA.md CHECK 3), and the S2 duplicate is two standalone logs of
    /// the same fill, not two members of one receipt.
    public static func pairs(in fills: [FillUp],
                             resolved: Set<PairKey> = []) -> [Pair] {
        let candidates = fills.filter { $0.purchaseGroupId == nil }
        let sorted = candidates.sorted(by: fillOrder)

        var result: [Pair] = []
        var consumed = Set<UUID>()
        for (index, candidate) in sorted.enumerated() where !consumed.contains(candidate.id) {
            guard let match = sorted[(index + 1)...].first(where: { fill in
                !consumed.contains(fill.id) && isDuplicate(candidate, fill)
            }) else { continue }
            let pair = Pair(countedID: counted(candidate, match),
                            excludedID: excluded(candidate, match),
                            vehicleID: candidate.vehicleId)
            consumed.insert(candidate.id)
            consumed.insert(match.id)
            if !resolved.contains(pair.key) {
                result.append(pair)
            }
        }
        return result
    }

    /// The heuristic's predicate, exposed so its boundary cases test directly:
    /// same vehicle, `abs(date diff) <= 30 minutes`, volume within 5%
    /// (`abs(a - b) <= 0.05 * min(a, b)` - one fill at most 5% larger than the
    /// other).
    ///
    /// Ahead of that heuristic sits one proof, not a heuristic: the fiscal
    /// document identity (`fn`+`i`+`fp`, P2.4b). Two different fiscal
    /// identities are definitively two different purchases - `receipt-015` and
    /// `receipt-026` are identical to the kopeck and 34 minutes apart, and a
    /// false "duplicate" offer there is a merge the user has to notice to undo.
    /// Equal identities are the same document re-scanned (minutes or days
    /// later), so they are duplicates regardless of the window. When either
    /// fill has no identity (no decodable QR - the common case), the heuristic
    /// below decides unchanged.
    public static func isDuplicate(_ lhs: FillUp, _ rhs: FillUp) -> Bool {
        if let lhsIdentity = lhs.fiscalIdentity, let rhsIdentity = rhs.fiscalIdentity {
            return lhsIdentity == rhsIdentity
        }
        guard lhs.vehicleId == rhs.vehicleId else { return false }
        guard abs(lhs.date.timeIntervalSince(rhs.date)) <= 30 * 60 else { return false }
        let smaller = min(lhs.volumeL, rhs.volumeL)
        guard smaller > 0 else { return false }
        return abs(lhs.volumeL - rhs.volumeL) <= 0.05 * smaller
    }

    /// The deterministic choice of which entry of a pair COUNTS while it is
    /// unresolved - exactly the entry a Merge keeps.
    ///
    /// Why this choice: the S2 invariant is that an unresolved pair contributes
    /// ONCE so stats never double, and which one must be a pure function of the
    /// data so the same entries always produce the same numbers. The entry that
    /// counts is the richer record - the one with an attachment when exactly one
    /// has one, else the earlier-created fill, else the lower id. That is
    /// precisely the survivor a Merge produces ("the one with an attachment
    /// wins, fields union" - docs/SYNC.md S2), which makes consumption
    /// continuous across the resolution: nothing jumps when the user merges
    /// (the survivor was already the one counting), and "Keep both" is the only
    /// action that changes any number - deliberately, because that is the user
    /// saying there really were two purchases.
    public static func counted(_ lhs: FillUp, _ rhs: FillUp) -> UUID {
        let aHasAttachment = !lhs.attachments.isEmpty
        let bHasAttachment = !rhs.attachments.isEmpty
        if aHasAttachment != bHasAttachment {
            return aHasAttachment ? lhs.id : rhs.id
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt ? lhs.id : rhs.id
        }
        return lhs.id.uuidString < rhs.id.uuidString ? lhs.id : rhs.id
    }

    private static func excluded(_ lhs: FillUp, _ rhs: FillUp) -> UUID {
        counted(lhs, rhs) == lhs.id ? rhs.id : lhs.id
    }

    private static func fillOrder(_ lhs: FillUp, _ rhs: FillUp) -> Bool {
        if lhs.vehicleId != rhs.vehicleId { return lhs.vehicleId.uuidString < rhs.vehicleId.uuidString }
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

/// The S2 Merge operation (docs/SYNC.md: "merge keeps the richer one: the one
/// with an attachment wins, fields union"). Pure and deterministic so the
/// survivor is L1-testable without a simulator.
public enum DuplicateMerge {
    /// Merges two flagged fill-ups into the survivor.
    ///
    /// `winner` is the entry that survives - its id, createdAt and required
    /// fields (date, vehicle, volume, fuel kind, full-tank flag) stay intact;
    /// `loser` contributes every optional field the winner lacks, and its
    /// attachments are folded in. The cross-check is recomputed because the
    /// union can change `unitPrice`/`money`. The loser is never modified here -
    /// the caller tombstones it (nothing is lost silently, hard rule 8).
    public static func merge(winner: FillUp, loser: FillUp) -> FillUp {
        var merged = winner
        merged.odometer = winner.odometer ?? loser.odometer
        merged.money = winner.money ?? loser.money
        merged.note = winner.note ?? loser.note
        merged.unitPrice = winner.unitPrice ?? loser.unitPrice
        merged.fuelGrade = winner.fuelGrade ?? loser.fuelGrade
        merged.tankLevelAfterPct = winner.tankLevelAfterPct ?? loser.tankLevelAfterPct
        merged.stationId = winner.stationId ?? loser.stationId
        merged.attachments = union(winner.attachments, loser.attachments)
        merged.updatedAt = Date()
        merged.crossCheck = TimelineValidator.crossCheck(volumeL: merged.volumeL,
                                                         unitPrice: merged.unitPrice,
                                                         amount: merged.money?.amount)
        return merged
    }

    private static func union(_ lhs: [AttachmentID], _ rhs: [AttachmentID]) -> [AttachmentID] {
        var seen = Set<AttachmentID>()
        var result: [AttachmentID] = []
        for id in lhs + rhs where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }
}

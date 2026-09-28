import Foundation

// MARK: - TireReading

extension TankbookRepository {
    /// Replaces the condition reading on a live swap record - the edit door the
    /// tire set's history offers after the swap was saved (hard rule 13). The
    /// record's items and links are untouched. Returns false when no live
    /// record mounts a set under that id.
    @discardableResult
    public func setTireReading(_ reading: TireReading?, onSwap serviceID: UUID,
                               now: Date = Date()) throws -> Bool {
        guard var service = try serviceRecord(id: serviceID),
              service.deletedAt == nil, service.tireSetId != nil else { return false }
        service.tireReading = reading.flatMap { $0.isEmpty ? nil : $0.normalised }
        service.updatedAt = now
        try upsertServiceRecord(service)
        return true
    }
}

import Foundation

/// The condition of the tires a swap mounts, read at that swap
/// (docs/SCHEMA.md -> ServiceRecord.tireReading). Stored on the mounting
/// `ServiceRecord`, never on the set, so each stint of a set carries the
/// reading taken when it began.
public struct TireReading: Codable, Sendable, Equatable {
    /// Measured tread depth in millimetres.
    public var treadDepthMm: Double?
    /// Free text on wear or damage: "even wear", "sidewall cut".
    public var note: String?

    public init(treadDepthMm: Double? = nil, note: String? = nil) {
        self.treadDepthMm = treadDepthMm
        self.note = note
    }

    /// A reading with neither value says nothing and is not stored.
    public var isEmpty: Bool {
        treadDepthMm == nil && (note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

import Foundation
import TankbookCore

/// Persistence for anomaly dismissals (P6.1b, docs/JOURNEYS.md J9). Stores the
/// DISMISSAL, never the verdict (hard rule 2): the anomaly re-derives from the
/// entries on every render, and the only thing remembered is what the user said
/// - `AnomalyDismissal { cause, reason, dismissedAt }`, the exact shape the
/// engine's own docs bless. A stored verdict would go stale the moment an entry
/// is edited; a stored dismissal does not.
///
/// Keyed per vehicle, because a dismissal belongs to the car it was seen on -
/// dismissing on one car must not quiet the same month's anomaly on another.
/// Suppression is by `AnomalyCause` inside the engine (metric + evaluated
/// month), so a later month or a different metric is a fresh cause and may fire
/// on its own (docs/SCHEMA.md -> ANOMALY: "dismissal suppresses only its own
/// cause").
enum AnomalyInsightStore {
    private static func key(for vehicleID: UUID) -> String {
        "anomalyInsight.dismissals.\(vehicleID.uuidString)"
    }

    /// The recorded dismissals for a vehicle. An empty set means "nothing said"
    /// - the engine stays free to speak.
    static func dismissals(for vehicleID: UUID) -> Set<AnomalyDismissal> {
        guard let data = UserDefaults.standard.data(forKey: key(for: vehicleID)),
              let rows = try? JSONDecoder().decode([AnomalyDismissal].self, from: data) else {
            return []
        }
        return Set(rows)
    }

    /// Remembers one dismissal. Repeated dismissals of the same cause are
    /// idempotent (a `Set`, keyed by the cause's hash).
    static func record(_ dismissal: AnomalyDismissal, for vehicleID: UUID) {
        var rows = dismissals(for: vehicleID)
        rows.insert(dismissal)
        if let data = try? JSONEncoder().encode(Array(rows)) {
            UserDefaults.standard.set(data, forKey: key(for: vehicleID))
        }
    }

    /// Test-only: `-anomalyDismissalReset` clears every vehicle's dismissals so
    /// a UI test starts from the same place (UserDefaults survive
    /// `-homeResetDatabase`, which only wipes the database).
    static func resetForTestsIfRequested(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard arguments.contains("-anomalyDismissalReset") else { return }
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("anomalyInsight.dismissals.") }
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

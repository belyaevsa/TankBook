import Foundation
import UserNotifications
import TankbookCore

#if DEBUG
/// Test support for RV.78's L2 assertions (docs/TESTING.md L2), which live in
/// the app-hosted `TankbookTests` bundle. That bundle depends only on the app
/// target and cannot link TankbookCore directly (the FileProtectionTests note),
/// so every core-typed operation the L2 tests need - seeding a fired reminder,
/// completing it as the sheet does - lives here behind plain-value signatures.
/// The tests still drive the REAL `UNUserNotificationCenter`, the REAL
/// `ReminderNotificationCoordinator` and the REAL lifecycle; this type only
/// translates core values the test bundle cannot name. Compiled out of release
/// builds: this cannot ship.
@MainActor
enum ReminderNotificationActionTestSupport {
    /// Seeds one vehicle and one FIRED (stored `.attention`) date reminder due
    /// in `dueInDays` days, returning the reminder's id. Deterministic for the
    /// re-arm assertion: snoozing a due-in-11-days reminder re-arms its date
    /// notification ~6 days out, which is always in the future whatever the
    /// run's clock.
    @discardableResult
    static func seedFiredDateReminder(dueInDays: Int = 11) -> UUID {
        guard let repository = try? AppStore.repository() else {
            preconditionFailure("RV.78 test support: no repository to seed into")
        }
        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_930)
        do {
            try repository.upsertVehicle(vehicle)
            let reminder = ReminderLifecycle.makeReminder(
                vehicleId: vehicle.id, title: "Oil change", category: .oil,
                dueDate: now.addingTimeInterval(Double(dueInDays) * 86_400),
                dueOdometer: nil,
                status: .attention)
            try repository.upsertReminder(reminder)
            return reminder.id
        } catch {
            preconditionFailure("RV.78 test support: seeding failed: \(error)")
        }
    }

    /// Completes a reminder exactly as the completion sheet's Skip path does
    /// (`ReminderCompletionSession.persistCompletion`, entryId nil) - the one
    /// code path the banner's Mark done lands the user on. Used by the disarm
    /// L2 test: after it, the reminder is `.done` and its pending notification
    /// must be gone.
    static func completeAsTheSheetDoes(reminderID: UUID,
                                       coordinator: ReminderNotificationCoordinator) {
        guard let repository = try? AppStore.repository(),
              let reminder = try? repository.liveReminder(id: reminderID) else { return }
        ReminderCompletionSession.persistCompletion(
            reminder: reminder, entryId: nil,
            completionDate: Date(),
            completionOdometer: (try? repository.vehicle(id: reminder.vehicleId))?.initialOdometer,
            coordinator: coordinator)
    }
    /// Every identifier currently pending on the real notification center.
    static func allPendingIdentifiers() async -> [String] {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return requests.map(\.identifier)
    }

    /// The category identifier carried by the pending request with this
    /// identifier (nil when no such request is pending).
    static func categoryIdentifier(for requestIdentifier: String) async -> String? {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return requests.first { $0.identifier == requestIdentifier }?.content.categoryIdentifier
    }
}
#endif

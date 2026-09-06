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

    // MARK: - RV.81 archive / unarchive support

    /// Seeds a NEW vehicle (archived: false) carrying one SCHEDULED date
    /// reminder due `dueInDays` days out, returning the vehicle's and the
    /// reminder's ids. The far future due keeps the reminder `.scheduled`
    /// across reconciles, so the arming that the archive/unarchive tests assert
    /// is the plan's deterministic date notification at `due - 12 days`, armed
    /// by a plain reconcile - never a stored `.attention` transition.
    /// A second reminder for the same car can be added with `seedScheduledReminder`.
    @discardableResult
    static func seedScheduledReminder(dueInDays: Int = 120) -> (vehicleID: UUID, reminderID: UUID) {
        guard let repository = try? AppStore.repository() else {
            preconditionFailure("RV.81 test support: no repository to seed into")
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
            let reminderID = seedScheduledReminder(onVehicle: vehicle.id, dueInDays: dueInDays)
            return (vehicle.id, reminderID)
        } catch {
            preconditionFailure("RV.81 test support: seeding failed: \(error)")
        }
    }

    /// Adds one more SCHEDULED date reminder to an existing vehicle, returning
    /// its id - so a test can give the car that will be archived MORE than one
    /// armed request and assert that EVERY one of them is cancelled.
    @discardableResult
    static func seedScheduledReminder(onVehicle vehicleID: UUID,
                                      dueInDays: Int = 120) -> UUID {
        guard let repository = try? AppStore.repository() else {
            preconditionFailure("RV.81 test support: no repository to seed into")
        }
        let reminder = ReminderLifecycle.makeReminder(
            vehicleId: vehicleID, title: "Oil change", category: .oil,
            dueDate: Date().addingTimeInterval(Double(dueInDays) * 86_400),
            dueOdometer: nil,
            status: .scheduled)
        do {
            try repository.upsertReminder(reminder)
            return reminder.id
        } catch {
            preconditionFailure("RV.81 test support: seeding failed: \(error)")
        }
    }

    /// The repository half of the archive toggle, mirroring
    /// `VehicleDetailView.toggleArchive`: archive the vehicle, then reconcile
    /// it (the RV.81 strip). Kept in support because the test bundle cannot
    /// link TankbookCore to name the repository type.
    static func archive(_ vehicleID: UUID) {
        guard let repository = try? AppStore.repository() else {
            preconditionFailure("RV.81 test support: no repository to seed into")
        }
        do {
            try repository.archiveVehicle(id: vehicleID)
        } catch {
            preconditionFailure("RV.81 test support: archive failed: \(error)")
        }
    }

    /// The repository half of the unarchive toggle, mirroring
    /// `VehicleDetailView.toggleArchive`: unarchive the vehicle so the next
    /// reconcile re-arms it.
    static func unarchive(_ vehicleID: UUID) {
        guard let repository = try? AppStore.repository() else {
            preconditionFailure("RV.81 test support: no repository to seed into")
        }
        do {
            try repository.unarchiveVehicle(id: vehicleID)
        } catch {
            preconditionFailure("RV.81 test support: unarchive failed: \(error)")
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

    /// Whether the reminder row is still `.scheduled` - the RV.81 assertion
    /// that archiving never advances the lifecycle (no stored `.attention`
    /// transition while the car is put away, or an odometer reminder
    /// unarchived inside its km window could not re-arm). Returns false for an
    /// unknown or deleted id too, so a test that asks about the wrong row fails
    /// rather than passing.
    static func reminderIsStillScheduled(_ reminderID: UUID) -> Bool {
        guard let repository = try? AppStore.repository(),
              let reminder = try? repository.liveReminder(id: reminderID) else { return false }
        return reminder.status == .scheduled
    }
}

/// A recording `LocalNotificationScheduling` double for the RV.81 L2 tests. The
/// real-center tests (the `ReminderNotificationActionTests` that poll
/// `UNUserNotificationCenter`) cannot run on every host - the simulator's
/// notification daemon has been observed dropping every `add` from a
/// test-hosted process, which makes arming assertions vacuous ("never armed")
/// rather than wrong. This double records what the REAL coordinator's reconcile
/// asked the seam to do, so the archive strip / unarchive re-arm orchestration
/// is pinned on hosts where the OS cannot cooperate: the seam is the only
/// difference - same repository, same coordinator, same plan. Scheduled and
/// cancelled are asserted by identifier, mirroring what the center-based tests
/// read back.
@MainActor
final class RecordingNotificationScheduler: LocalNotificationScheduling {
    private(set) var scheduled: [ReminderNotification] = []
    private(set) var cancelledIdentifiers: [String] = []

    func schedule(_ notifications: [ReminderNotification]) async {
        scheduled.append(contentsOf: notifications)
    }

    func cancel(identifiers: [String]) async {
        cancelledIdentifiers.append(contentsOf: identifiers)
    }

    func scheduleMonthlySummary(_ notifications: [MonthlySummaryNotification]) async {}
    func cancelMonthlySummary(identifiers: [String]) async {}
    func authorization() async -> LocalNotificationAuthorization { .authorized }
    func requestAuthorization() async -> LocalNotificationAuthorization { .authorized }
}
#endif

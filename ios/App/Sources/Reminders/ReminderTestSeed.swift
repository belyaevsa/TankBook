import Foundation
import TankbookCore

#if DEBUG
/// UI-test + screenshot seeding for the Reminders screen (P3.4), the same
/// idempotent hook pattern as `HomeTestSeed` / `RecentlyDeletedTestSeed`.
/// `-seedReminders` writes the artboard's list - an attention "Insurance
/// renewal" due in 12 days (so the amber chip renders the literal "12 days" on
/// any run date) plus three scheduled rows - and `-homeResetDatabase` wipes
/// the app database first so the states are isolated from each other within a
/// test run. The empty state needs no seed: `-homeResetDatabase` alone leaves
/// nothing to list.
enum ReminderTestSeed {
    /// PJ.5: the attention reminder's FIXED id, so a UI test or screenshot can
    /// address the seeded "Insurance renewal" through the replay identifier
    /// `reminder.<id>.date` without reading a runtime UUID.
    static let deepLinkReminderID = UUID(uuidString: "0D4B0F2A-3E1C-4B6A-9C5D-8E7F1A2B3C4D")!

    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-seedReminders")
            || arguments.contains("-seedReminderComplete")
            || arguments.contains("-homeResetDatabase") else { return }

        if arguments.contains("-homeResetDatabase") {
            AppStore.resetForTestsOncePerLaunch()
        }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        if arguments.contains("-seedReminderComplete") {
            seedCompletionReminder(repository)
            return
        }
        guard arguments.contains("-seedReminders") else { return }

        seed(repository)
    }

    /// The P3.5 completion-sheet state: a single recurring oil change so the
    /// sheet's "Completed today at 119 486 km" and "Next cycle scheduled: in
    /// 15 000 km or <next year>" render deterministically (design/screens/
    /// ReminderComplete.dc.html). The current odometer is the vehicle's initial
    /// odometer - no entries - so the km half anchors at exactly 119 486.
    private static func seedCompletionReminder(_ repository: TankbookRepository) {
        let now = Date()
        let calendar = Calendar.current
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 119_486)
        try? repository.upsertVehicle(vehicle)

        let oilChange = ReminderLifecycle.makeReminder(
            vehicleId: vehicle.id, title: "Oil change", category: .oil,
            dueDate: calendar.date(byAdding: .month, value: 18, to: now),
            dueOdometer: 119_486 + 15_000,
            recurrence: Reminder.Recurrence(everyKm: 15_000, everyMonths: 12))
        try? repository.upsertReminder(oilChange)
    }

    // MARK: - Seed

    /// The artboard's four rows (design/screens/Reminders.dc.html): one
    /// attention card (insurance due in 12 days, amber chip "12 days") and
    /// three scheduled cards (oil change with both due fields + recurrence,
    /// inspection in ~7 months, winter tires in ~6 weeks).
    private static func seed(_ repository: TankbookRepository) {
        let now = Date()
        let calendar = Calendar.current
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_930)
        try? repository.upsertVehicle(vehicle)

        let insurance = ReminderLifecycle.makeReminder(
            vehicleId: vehicle.id, title: "Insurance renewal", category: .insurance,
            dueDate: now.addingTimeInterval(12 * 86_400), dueOdometer: nil,
            recurrence: Reminder.Recurrence(everyKm: nil, everyMonths: 12),
            createdAt: now.addingTimeInterval(-330 * 86_400),
            id: Self.deepLinkReminderID)
        try? repository.upsertReminder(insurance)

        let oilChange = ReminderLifecycle.makeReminder(
            vehicleId: vehicle.id, title: "Oil change", category: .oil,
            dueDate: calendar.date(byAdding: .month, value: 18, to: now),
            dueOdometer: 127_330,
            recurrence: Reminder.Recurrence(everyKm: 15_000, everyMonths: 12))
        try? repository.upsertReminder(oilChange)

        let inspection = ReminderLifecycle.makeReminder(
            vehicleId: vehicle.id, title: "Inspection (TÜV)", category: .inspection,
            dueDate: calendar.date(byAdding: .month, value: 7, to: now),
            dueOdometer: nil, recurrence: nil)
        try? repository.upsertReminder(inspection)

        let tires = ReminderLifecycle.makeReminder(
            vehicleId: vehicle.id, title: "Winter tires", category: .tires,
            dueDate: now.addingTimeInterval(45 * 86_400),
            dueOdometer: nil, recurrence: nil)
        try? repository.upsertReminder(tires)
    }
}
#endif

// MARK: - Form pre-fill (screenshots)

/// The Reminder form's screenshot pre-fill, the same test-hook pattern as
/// `ServiceEntryPrefillSeed`: `-seedReminderForm` populates a CREATE form so a
/// simctl-driven capture (which cannot tap) shows a filled reminder without
/// driving a single tap. The pre-fill is default input the user edits (hard
/// rule 13), never a separate screen.
struct ReminderFormPrefill {
    var title = ""
    var category: ReminderCategory = .oil
    var hasDueDate = false
    var dueDate = Date()
    var dueOdometer = ""
    var recurrenceEveryMonths = ""
    var recurrenceEveryKm = ""
}

#if DEBUG
enum ReminderFormPrefillSeed {
    static func from(arguments: [String]) -> ReminderFormPrefill? {
        guard arguments.contains("-seedReminderForm") else { return nil }
        return ReminderFormPrefill(
            title: "Oil change", category: .oil,
            hasDueDate: true,
            dueDate: Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date(),
            dueOdometer: OdometerFormat.grouped(127_330),
            recurrenceEveryMonths: "12",
            recurrenceEveryKm: OdometerFormat.grouped(15_000))
    }
}
#endif

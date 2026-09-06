import Foundation
import TankbookCore

#if DEBUG
/// UI-test + screenshot seeding for the Reminders screen (P3.4), the same
/// idempotent hook pattern as `HomeTestSeed` / `RecentlyDeletedTestSeed`.
/// `-seedReminders` writes the artboard's list - an attention "Insurance
/// renewal" due in 12 days (so the amber chip renders the literal "12 days" on
/// any run date) plus three scheduled rows - `-seedRemindersAll` writes the
/// merged list's two-car garage (RV.75, design/screens/RemindersAll.dc.html),
/// `-seedRemindersDeepLink` writes the RV.74 deep-link state (two cars, car A
/// the default selection, car B carrying the deep-link reminder plus a
/// tombstoned one; `-seedRemindersDeepLinkArchived` is that same state with
/// car B archived after its reminder was armed - since RV.81 a racing /
/// already-delivered residue, the case the resolve stays live for) - and
/// `-homeResetDatabase` wipes the app database first so
/// the states are isolated from each other within a test run. The empty state
/// needs no seed: `-homeResetDatabase` alone leaves nothing to list.
enum ReminderTestSeed {
    /// PJ.5: the attention reminder's FIXED id, so a UI test or screenshot can
    /// address the seeded "Insurance renewal" through the replay identifier
    /// `reminder.<id>.date` without reading a runtime UUID.
    static let deepLinkReminderID = UUID(uuidString: "0D4B0F2A-3E1C-4B6A-9C5D-8E7F1A2B3C4D")!
    /// RV.74: the two-car deep-link seed's car-B reminder (the Skoda "Oil
    /// change", due +10 days - LATER than car A's attention row, so a test can
    /// prove the surfaced sheet belongs to the id the tap named, not to
    /// whichever row is first).
    static let deepLinkCarBReminderID = UUID(uuidString: "5C1A2B3C-4D5E-4F60-8A7B-6C5D4E3F2A1B")!
    /// RV.74: the two-car deep-link seed's DELETED reminder (a Skoda row
    /// tombstoned at seed time), so the stale-tap test replays an identifier
    /// for a reminder that no longer exists and must land on the plain list.
    static let deepLinkDeletedReminderID = UUID(uuidString: "7A9B8C7D-6E5F-4A3B-8C2D-1E0F9A8B7C6D")!

    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-seedReminders")
            || arguments.contains("-seedReminderComplete")
            || arguments.contains("-seedRemindersAll")
            || arguments.contains("-seedRemindersDeepLink")
            || arguments.contains("-seedRemindersDeepLinkArchived")
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
        if arguments.contains("-seedRemindersAll") {
            seedAll(repository)
            return
        }
        if arguments.contains("-seedRemindersDeepLinkArchived") {
            seedDeepLink(repository, archiveCarB: true)
            return
        }
        if arguments.contains("-seedRemindersDeepLink") {
            seedDeepLink(repository)
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

    /// The RV.75 merged-list state (design/screens/RemindersAll.dc.html): two
    /// ACTIVE cars, each carrying one attention row and one scheduled row, so
    /// the "all cars" list renders both groups with every row naming its car.
    /// Volvo is upserted FIRST so it is the default selection when a per-car
    /// test reuses this seed (VehicleSelection falls back to the first live
    /// car). The attention rows are non-recurring and date-only: completing one
    /// removes exactly it, leaving the other car's attention row - and its car
    /// chip - untouched, deterministically.
    private static func seedAll(_ repository: TankbookRepository) {
        let now = Date()
        let calendar = Calendar.current
        let volvo = makeVehicle("Volvo V60", make: "Volvo", at: now, initialOdometer: 118_930)
        let skoda = makeVehicle("Skoda Octavia", make: "Skoda", at: now, initialOdometer: 82_000)
        try? repository.upsertVehicle(volvo)
        try? repository.upsertVehicle(skoda)

        let insurance = ReminderLifecycle.makeReminder(
            vehicleId: volvo.id, title: "Insurance renewal", category: .insurance,
            dueDate: now.addingTimeInterval(12 * 86_400), dueOdometer: nil,
            recurrence: nil)
        try? repository.upsertReminder(insurance)

        let tires = ReminderLifecycle.makeReminder(
            vehicleId: volvo.id, title: "Winter tires", category: .tires,
            dueDate: now.addingTimeInterval(45 * 86_400),
            dueOdometer: nil, recurrence: nil)
        try? repository.upsertReminder(tires)

        let oilChange = ReminderLifecycle.makeReminder(
            vehicleId: skoda.id, title: "Oil change", category: .oil,
            dueDate: now.addingTimeInterval(3 * 86_400), dueOdometer: nil,
            recurrence: nil)
        try? repository.upsertReminder(oilChange)

        let inspection = ReminderLifecycle.makeReminder(
            vehicleId: skoda.id, title: "Inspection (TÜV)", category: .inspection,
            dueDate: calendar.date(byAdding: .month, value: 7, to: now),
            dueOdometer: nil, recurrence: nil)
        try? repository.upsertReminder(inspection)
    }

    /// The RV.74 deep-link state
    /// (design/screens/RemindersAll.dc.html, the two-car landing): car A
    /// (Volvo, upserted FIRST so it is the default selection) carries the
    /// EARLIEST attention row, while the deep-linked reminder lives on car B
    /// (Skoda) and is due LATER - so a test can prove the surfaced completion
    /// sheet belongs to the id the tap named, not to whichever row renders
    /// first. A third, tombstoned Skoda reminder carries the stale-tap
    /// identifier: deleted at seed time, it must never surface, and the app
    /// must not switch to its car.
    ///
    /// With `archiveCarB` the reminder is seeded on a car that is then
    /// ARCHIVED. Since RV.81 archiving CANCELS a car's pending notifications,
    /// this is no longer a state the app's own archive action leaves behind -
    /// it is the racing/already-delivered residue that CAN still exist (a
    /// notification handed to the system a moment before the archive, or one
    /// already delivered), which is exactly why the resolve stays live for
    /// archived cars. The deep link must reach the reminder (its completion
    /// flow surfaces) without making the sold car current again.
    private static func seedDeepLink(_ repository: TankbookRepository,
                                     archiveCarB: Bool = false) {
        let now = Date()
        let volvo = makeVehicle("Volvo V60", make: "Volvo", at: now, initialOdometer: 118_930)
        let skoda = makeVehicle("Skoda Octavia", make: "Skoda", at: now, initialOdometer: 82_000,
                                archived: archiveCarB)
        try? repository.upsertVehicle(volvo)
        try? repository.upsertVehicle(skoda)

        let volvoInsurance = ReminderLifecycle.makeReminder(
            vehicleId: volvo.id, title: "Insurance renewal", category: .insurance,
            dueDate: now.addingTimeInterval(2 * 86_400), dueOdometer: nil,
            recurrence: nil)
        try? repository.upsertReminder(volvoInsurance)

        let skodaOil = ReminderLifecycle.makeReminder(
            vehicleId: skoda.id, title: "Oil change", category: .oil,
            dueDate: now.addingTimeInterval(10 * 86_400), dueOdometer: nil,
            recurrence: nil,
            createdAt: now.addingTimeInterval(-90 * 86_400),
            id: Self.deepLinkCarBReminderID)
        try? repository.upsertReminder(skodaOil)

        let deleted = ReminderLifecycle.makeReminder(
            vehicleId: skoda.id, title: "Brake check", category: .brakes,
            dueDate: now.addingTimeInterval(3 * 86_400), dueOdometer: nil,
            recurrence: nil,
            createdAt: now.addingTimeInterval(-200 * 86_400),
            id: Self.deepLinkDeletedReminderID)
        try? repository.upsertReminder(deleted)
        try? repository.softDeleteReminder(id: deleted.id)
    }

    private static func makeVehicle(_ name: String, make: String,
                                    at now: Date,
                                    initialOdometer: Int,
                                    archived: Bool = false) -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: name, make: make, model: name, year: 2020,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 60, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: archived, paceLimitKmPerDay: 1500,
            initialOdometer: initialOdometer)
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

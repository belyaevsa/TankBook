#if DEBUG
import Foundation
import TankbookCore

/// RV.76's Home reminder-row seeds, kept in their own file so `HomeTestSeed`
/// stays under the lint body-length budget (one seed file per Home state
/// group, the same split as `RV66TwoCarTestSeed`). Both write a SECOND active
/// car, which is why the Volvo - built with the EARLIEST createdAt - stays the
/// default selection whose banner the RV.76 tests assert on: VehicleSelection
/// falls back to the first live vehicle ordered by createdAt.
enum RemindersEntryTestSeed {

    /// The two-car DUE state (design/screens/RemindersEntry.dc.html): two
    /// ACTIVE cars, each carrying one attention reminder. The Volvo is due
    /// sooner, so Home's banner - the selected car's earliest attention
    /// reminder - is also the most urgent ACROSS the two, and the Home row's
    /// count reads 2: the "when two things are due the second is invisible"
    /// window the count exists to open.
    static func seedDue(_ repository: TankbookRepository) {
        let now = Date()
        let volvo = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(volvo)
        let skoda = makeSkodaOctavia(at: now.addingTimeInterval(1))
        try? repository.upsertVehicle(skoda)

        let insurance = ReminderLifecycle.makeReminder(
            vehicleId: volvo.id, title: "Insurance renewal", category: .insurance,
            dueDate: now.addingTimeInterval(3 * 86_400), dueOdometer: nil,
            recurrence: nil)
        try? repository.upsertReminder(insurance)

        let oilChange = ReminderLifecycle.makeReminder(
            vehicleId: skoda.id, title: "Oil change", category: .oil,
            dueDate: now.addingTimeInterval(10 * 86_400), dueOdometer: nil,
            recurrence: nil)
        try? repository.upsertReminder(oilChange)
    }

    /// The calm state: reminders EXIST across two cars but none is inside the
    /// attention window - the "nothing due" case that used to have no path at
    /// all. The Home row is present with no count chip and still reaches the
    /// merged list, which shows the scheduled rows.
    static func seedNothingDue(_ repository: TankbookRepository) {
        let now = Date()
        let volvo = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(volvo)
        let skoda = makeSkodaOctavia(at: now.addingTimeInterval(1))
        try? repository.upsertVehicle(skoda)

        let insurance = ReminderLifecycle.makeReminder(
            vehicleId: volvo.id, title: "Insurance renewal", category: .insurance,
            dueDate: now.addingTimeInterval(45 * 86_400), dueOdometer: nil,
            recurrence: nil)
        try? repository.upsertReminder(insurance)

        let oilChange = ReminderLifecycle.makeReminder(
            vehicleId: skoda.id, title: "Oil change", category: .oil,
            dueDate: now.addingTimeInterval(60 * 86_400), dueOdometer: nil,
            recurrence: nil)
        try? repository.upsertReminder(oilChange)
    }

    /// The RV.79 two-car badge state (design/screens/GarageReminderCounts.dc.html):
    /// the artboard garage (`CarSwitcherTestSeed.seedGarage`: Volvo petrol +
    /// ID.4 EV live, BMW archived) with Volvo carrying TWO attention reminders
    /// plus one scheduled, so its Garage / Car switcher card must badge "2" -
    /// and the scheduled row proves the badge counts attention only. ID.4
    /// carries a scheduled reminder ONLY, so its card must stay quiet: a badge
    /// that is always lit stops meaning anything. Volvo is the default
    /// selection (seeded first, VehicleSelection falls back to the first live
    /// car).
    static func seedGarageCounts(_ repository: TankbookRepository) {
        CarSwitcherTestSeed.seedGarage(repository)
        let vehicles = (try? repository.liveVehicles()) ?? []
        let now = Date()

        if let volvo = vehicles.first(where: { $0.name == "Volvo V60" }) {
            try? repository.upsertReminder(ReminderLifecycle.makeReminder(
                vehicleId: volvo.id, title: "Insurance renewal", category: .insurance,
                dueDate: now.addingTimeInterval(3 * 86_400), dueOdometer: nil,
                recurrence: nil))
            try? repository.upsertReminder(ReminderLifecycle.makeReminder(
                vehicleId: volvo.id, title: "Brake check", category: .brakes,
                dueDate: now.addingTimeInterval(8 * 86_400), dueOdometer: nil,
                recurrence: nil))
            try? repository.upsertReminder(ReminderLifecycle.makeReminder(
                vehicleId: volvo.id, title: "Winter tires", category: .tires,
                dueDate: now.addingTimeInterval(40 * 86_400), dueOdometer: nil,
                recurrence: nil))
        }
        if let id4 = vehicles.first(where: { $0.name == "ID.4" }) {
            try? repository.upsertReminder(ReminderLifecycle.makeReminder(
                vehicleId: id4.id, title: "Inspection (TÜV)", category: .inspection,
                dueDate: now.addingTimeInterval(60 * 86_400), dueOdometer: nil,
                recurrence: nil))
        }
    }

    private static func makeSkodaOctavia(at now: Date) -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Skoda Octavia", make: "Skoda", model: "Octavia", year: 2020,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 60, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 82_000)
    }
}
#endif

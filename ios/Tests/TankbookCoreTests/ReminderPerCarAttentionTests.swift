import Foundation
import Testing
@testable import TankbookCore

/// RV.79 - the per-car attention count that badges a Garage / Car switcher row.
/// docs/SCREENMAP.md -> "Reminders across cars" (a count marks a car only when
/// something needs attention). The gate is the two things a car badge must do
/// that a cross-car count never had to: count ONE vehicle's work - so a car
/// whose reminders are merely scheduled stays quiet - and change when one of
/// its reminders is completed (hard rule 2: the count is derived at read time,
/// never stored, never cached on the row).
@Suite struct ReminderPerCarAttentionTests {

    private let now = Date(timeIntervalSince1970: 1_752_000_000)

    private func makeVehicle(_ name: String, id: UUID = UUID.v7()) -> Vehicle {
        let stamp = now
        return Vehicle(
            id: id, createdAt: stamp, updatedAt: stamp, deletedAt: nil,
            name: name, make: "Maker", model: name, year: 2020,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 60, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 100_000)
    }

    private func makeReminder(vehicleId: UUID,
                              title: String,
                              dueInDays: Int,
                              createdAt: Date? = nil) -> Reminder {
        ReminderLifecycle.makeReminder(
            vehicleId: vehicleId, title: title, category: .oil,
            dueDate: now.addingTimeInterval(TimeInterval(dueInDays) * 86_400),
            dueOdometer: nil,
            createdAt: createdAt ?? now.addingTimeInterval(TimeInterval(dueInDays)))
    }

    // MARK: - The count equals the vehicle's attention rows

    /// The badge's definition: one vehicle's count IS the merged list's
    /// "Needs attention" group for that vehicle - derived over the SAME live
    /// rows, so the badge and the list can never disagree. Volvo carries two
    /// reminders inside the 12-day window; Skoda's are all scheduled beyond it.
    /// The count must be 2 and 0 - never a per-car query's guess, never a total
    /// across both cars.
    @Test func perCarCountEqualsTheVehiclesAttentionRows() throws {
        let volvo = makeVehicle("Volvo V60")
        let skoda = makeVehicle("Skoda Octavia")
        let reminders = [
            makeReminder(vehicleId: volvo.id, title: "Insurance renewal", dueInDays: 3),
            makeReminder(vehicleId: volvo.id, title: "Brake check", dueInDays: 8),
            makeReminder(vehicleId: volvo.id, title: "Winter tires", dueInDays: 45),
            makeReminder(vehicleId: skoda.id, title: "Inspection", dueInDays: 60)
        ]

        // The merged list's own derivation for each car: group the live rows
        // and count the attention half - what the badge must equal.
        let volvoRows = reminders
            .filter { $0.vehicleId == volvo.id }
            .map { ReminderListRow(reminder: $0, currentOdometer: nil) }
        let skodaRows = reminders
            .filter { $0.vehicleId == skoda.id }
            .map { ReminderListRow(reminder: $0, currentOdometer: nil) }

        let volvoAttention = ReminderListGroups.attentionCount(forVehicle: volvo.id,
                                                               among: reminders,
                                                               currentOdometer: nil,
                                                               now: now)
        let skodaAttention = ReminderListGroups.attentionCount(forVehicle: skoda.id,
                                                               among: reminders,
                                                               currentOdometer: nil,
                                                               now: now)

        #expect(volvoAttention == ReminderListGroups.attentionCount(volvoRows, now: now),
                "the badge must equal the merged list's attention group for the car")
        #expect(skodaAttention == ReminderListGroups.attentionCount(skodaRows, now: now),
                "the badge must equal the merged list's attention group for the car")
        #expect(volvoAttention == 2,
                "both in-window reminders demand attention; got \(volvoAttention)")
        #expect(skodaAttention == 0,
                "a car whose reminders are merely scheduled stays quiet; got \(skodaAttention)")
    }

    // MARK: - Completing one drops the count

    /// The badge is derived at read time (hard rule 2), so completing an
    /// attention reminder must change the count on the next derivation -
    /// without storing a count anywhere. Caching the count at first render is
    /// the mutation this test exists to catch: complete a reminder, re-derive,
    /// and the count must have fallen.
    @Test func countChangesWhenAnAttentionReminderIsCompleted() throws {
        let vehicle = makeVehicle("Volvo V60")
        let insurance = makeReminder(vehicleId: vehicle.id,
                                     title: "Insurance renewal", dueInDays: 3)
        let tires = makeReminder(vehicleId: vehicle.id,
                                 title: "Winter tires", dueInDays: 45)

        #expect(ReminderListGroups.attentionCount(forVehicle: vehicle.id,
                                                  among: [insurance, tires],
                                                  currentOdometer: nil,
                                                  now: now) == 1)

        let completion = ReminderLifecycle.complete(insurance,
                                                    entryId: nil,
                                                    completionDate: now,
                                                    completionOdometer: nil,
                                                    now: now)
        if case .done = completion.completed.status {} else {
            Issue.record("the completed reminder must be terminal history")
        }

        let after = ReminderListGroups.attentionCount(forVehicle: vehicle.id,
                                                      among: [completion.completed, tires],
                                                      currentOdometer: nil,
                                                      now: now)
        #expect(after == 0,
                "completing the only attention reminder must drop the count; got \(after)")
    }

    // MARK: - Only attention counts (a scheduled badge would be noise)

    /// Counting ACTIVE reminders instead of attention-only is the other named
    /// mutation: a car with work merely scheduled must render no badge at all,
    /// and one with BOTH states must count only the attention rows.
    @Test func scheduledRemindersNeverCountTowardsTheBadge() throws {
        let vehicle = makeVehicle("Volvo V60")
        let scheduledFar = makeReminder(vehicleId: vehicle.id,
                                        title: "Winter tires", dueInDays: 45)
        let scheduledFarer = makeReminder(vehicleId: vehicle.id,
                                          title: "Inspection", dueInDays: 90)

        let quiet = ReminderListGroups.attentionCount(forVehicle: vehicle.id,
                                                      among: [scheduledFar, scheduledFarer],
                                                      currentOdometer: nil,
                                                      now: now)
        #expect(quiet == 0,
                "two scheduled reminders must not light a badge; got \(quiet)")

        let attention = makeReminder(vehicleId: vehicle.id,
                                     title: "Insurance renewal", dueInDays: 3)
        let mixed = ReminderListGroups.attentionCount(forVehicle: vehicle.id,
                                                      among: [attention, scheduledFar],
                                                      currentOdometer: nil,
                                                      now: now)
        #expect(mixed == 1,
                "among mixed rows only the attention one counts; got \(mixed)")
    }

    // MARK: - The km half is judged against the car's own odometer

    /// The badge must judge an odometer reminder against ITS OWN car's reading
    /// (the merged list's per-row rule, RV.75) - never one shared odometer, and
    /// never the reminder's due value alone. Two reminders 400 km out (inside
    /// the 500 km window) and 900 km out must count 1 and 0 for their cars.
    @Test func odometerRemindersAreJudgedAgainstTheCarsOwnReading() {
        let volvo = makeVehicle("Volvo V60")
        let skoda = makeVehicle("Skoda Octavia")
        let volvoService = ReminderLifecycle.makeReminder(
            vehicleId: volvo.id, title: "Volvo service", category: .oil,
            dueDate: nil, dueOdometer: 100_400)
        let skodaService = ReminderLifecycle.makeReminder(
            vehicleId: skoda.id, title: "Skoda service", category: .oil,
            dueDate: nil, dueOdometer: 100_900)

        let volvoCount = ReminderListGroups.attentionCount(forVehicle: volvo.id,
                                                           among: [volvoService, skodaService],
                                                           currentOdometer: 100_000,
                                                           now: now)
        let skodaCount = ReminderListGroups.attentionCount(forVehicle: skoda.id,
                                                           among: [volvoService, skodaService],
                                                           currentOdometer: 100_000,
                                                           now: now)
        #expect(volvoCount == 1, "400 km to due is inside the window; got \(volvoCount)")
        #expect(skodaCount == 0, "900 km to due is outside it; got \(skodaCount)")
    }
}

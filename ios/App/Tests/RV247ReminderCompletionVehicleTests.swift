import TankbookCore
import XCTest
@testable import Tankbook

/// RV.247 - "Type amount" from the merged all-cars reminder list must log the
/// entry to the REMINDER's car, never the selected one. The merged list
/// (`RemindersAllRows`) shows every active car's reminders; completing a
/// non-selected car's reminder opens the completion sheet, and the entry screens
/// resolved their vehicle from `carSelection.selectedVehicle`, so the entry
/// landed on whichever car happened to be selected. The notification deep link
/// was right only because it selected the reminder's car first; the list path
/// never did. Two screens, each correct, and the car dropped between them.
///
/// The fix carries the reminder's `vehicleId` through
/// `ReminderCompletionSession.Pending` and resolves the entry's vehicle from it.
/// This test drives BOTH entry kinds through the same `entryVehicle` seam the
/// views call in `load()`, then builds the entry through the real save seam
/// (`ServiceEntryDraft.build` / `ExpenseEntryView.storedExpense`), so "fixed the
/// service path and not the expense path" fails here - the named vacuous trap.
///
/// The oracle is the stored entry's `vehicleId`, not the resolved vehicle's
/// name or the sheet's car label: the sheet may name the right car while the
/// entry still writes to the wrong one.
@MainActor
final class RV247ReminderCompletionVehicleTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeVehicle(_ name: String, initialOdometer: Int) -> Vehicle {
        let now = Date()
        return Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: name, make: name, model: name, year: 2020,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 60, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: initialOdometer)
    }

    /// The hand-off the completion sheet writes before opening the entry: the
    /// reminder's own car rides it explicitly.
    private func handoff(_ reminder: Reminder, odometer: Int?) -> ReminderCompletionSession.Pending {
        ReminderCompletionSession.Pending(
            reminder: reminder, vehicleId: reminder.vehicleId,
            completionDate: Date(), completionOdometer: odometer)
    }

    /// L1, fails before this row: a service reminder and an expense reminder
    /// both live on the NON-selected car. Completing either must produce an
    /// entry whose `vehicleId` is the reminder's, on both entry kinds.
    func testTypeAmountLogsToTheRemindersCarForBothEntryKinds() throws {
        let selected = makeVehicle("Volvo V60", initialOdometer: 118_930)
        let other = makeVehicle("Skoda Octavia", initialOdometer: 82_000)
        let vehicles = [selected, other]

        let oil = ReminderLifecycle.makeReminder(
            vehicleId: other.id, title: "Oil change", category: .oil,
            dueDate: Date(), dueOdometer: nil)
        let insurance = ReminderLifecycle.makeReminder(
            vehicleId: other.id, title: "Insurance renewal", category: .insurance,
            dueDate: Date(), dueOdometer: nil)

        // Service path: the seam `ServiceEntryView.load()` calls.
        let serviceVehicle = try XCTUnwrap(
            ServiceEntryView.entryVehicle(vehicles: vehicles,
                                          completion: handoff(oil, odometer: 82_000),
                                          selected: selected))
        var serviceForm = ServiceEntryFormState()
        serviceForm.items = [ServiceEntryItemDraft(title: "Oil change", category: .oil,
                                                   cost: "89.00")]
        let service = serviceForm.draft(vehicle: serviceVehicle)
            .build(vehicleId: serviceVehicle.id, homeCurrency: serviceVehicle.homeCurrency)
        XCTAssertEqual(service.vehicleId, other.id,
                       "the service entry must be written to the reminder's car, not the selected one")

        // Expense path: the same seam, the other entry kind.
        let expenseVehicle = try XCTUnwrap(
            ExpenseEntryView.entryVehicle(vehicles: vehicles,
                                          completion: handoff(insurance, odometer: nil),
                                          selected: selected))
        var expenseForm = ExpenseEntryFormState()
        expenseForm.category = .insurance
        expenseForm.amount = "420.00"
        let amount = try XCTUnwrap(expenseForm.amountDecimal)
        let expense = ExpenseEntryView.storedExpense(
            form: expenseForm, vehicle: expenseVehicle, amount: amount,
            attachments: [], provenance: .manual)
        XCTAssertEqual(expense.vehicleId, other.id,
                       "the expense entry must be written to the reminder's car, not the selected one")

        // The "not the other's" half: neither entry may land on the selection.
        XCTAssertNotEqual(service.vehicleId, selected.id)
        XCTAssertNotEqual(expense.vehicleId, selected.id)
    }

    /// The fallback is preserved: an entry opened with NO completion hand-off
    /// still writes to the selected car, so the fix cannot have replaced the
    /// ordinary manual path's car with something else.
    func testAnEntryWithoutAHandoffStillUsesTheSelectedCar() throws {
        let selected = makeVehicle("Volvo V60", initialOdometer: 118_930)
        let other = makeVehicle("Skoda Octavia", initialOdometer: 82_000)
        let vehicles = [selected, other]

        let serviceVehicle = try XCTUnwrap(
            ServiceEntryView.entryVehicle(vehicles: vehicles,
                                          completion: nil, selected: selected))
        XCTAssertEqual(serviceVehicle.id, selected.id)

        let expenseVehicle = try XCTUnwrap(
            ExpenseEntryView.entryVehicle(vehicles: vehicles,
                                          completion: nil, selected: selected))
        XCTAssertEqual(expenseVehicle.id, selected.id)
    }
}

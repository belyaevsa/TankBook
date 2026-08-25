import Foundation
import TankbookCore

/// UI-test and screenshot seeding for the parts shelf and the install link
/// (P3.2). `-seedPartsShelf` seeds a vehicle plus three on-shelf parts so the
/// shelf screenshot shows the "on shelf" state; `-seedServiceEntryLink` does the
/// same so the ServiceEntry sheet's Link row can offer a matching part.
/// Idempotent: once the parts exist it does nothing (the capture script's
/// `-homeResetDatabase` clears them first).
enum PartsShelfTestSeed {
    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-seedPartsShelf") || arguments.contains("-seedServiceEntryLink") else {
            return
        }
        guard let repository = try? AppStore.repository() else { return }

        let vehicle: Vehicle
        if let existing = (try? repository.liveVehicles())?.first {
            vehicle = existing
        } else {
            let now = Date()
            vehicle = Vehicle(
                id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
                name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
                plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
                tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
                units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                     energy: .kWhPer100),
                photo: nil, archived: false, paceLimitKmPerDay: 1500,
                initialOdometer: 118_930)
            try? repository.upsertVehicle(vehicle)
        }

        // Idempotent: only seed into an empty expense log.
        guard (try? repository.liveExpenses(forVehicle: vehicle.id))?.isEmpty != false else { return }

        let parts: [(title: String, date: String, amount: String)] = [
            ("Oil filter", "03.03.2026", "12.40"),
            ("Brake pads front", "20.02.2026", "59.00"),
            ("Wiper blades", "11.01.2026", "8.99"),
        ]
        for part in parts {
            let date = ConfirmDate.parse(part.date) ?? Date()
            let expense = Expense(
                id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
                vehicleId: vehicle.id, date: date, odometer: nil,
                money: Money(amount: Decimal(string: part.amount)!,
                             currency: .eur, homeCurrency: .eur),
                note: nil, attachments: [], provenance: .manual, conflict: .none,
                purchaseGroupId: nil, category: .parts, title: part.title,
                recurrence: nil, installedInServiceId: nil)
            try? repository.upsertExpense(expense)
        }
    }
}

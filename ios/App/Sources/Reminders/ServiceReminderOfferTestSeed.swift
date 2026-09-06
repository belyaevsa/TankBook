#if DEBUG
import Foundation
import TankbookCore

/// UI-test + screenshot seeding for the RV.77 service-reminder offer
/// (design/screens/ServiceReminderOffer.dc.html, docs/JOURNEYS.md J7d "Just did
/// it"). `-seedServiceReminderOffer` writes the state the offer sheet appears
/// over: a car plus a just-saved oil service record (so the log shows it and
/// the offer's anchor is real), with NO live oil reminder - suppression must
/// not hide the seeded offer. `-homeResetDatabase` wipes first, isolating the
/// state within a run.
///
/// The seed only writes DATA. The sheet itself is presented by the tab root's
/// offer host once the seed has run (the L4 tests drive a real save; the
/// screenshot hook presents the offer over the seeded log).
enum ServiceReminderOfferTestSeed {
    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-seedServiceReminderOffer") else { return }
        AppStore.resetForTestsOncePerLaunch()
        guard let repository = try? AppStore.repository() else { return }

        let now = Date()
        let calendar = Calendar.current
        // "Sep 5" - a fixed date a couple of days in the past so the log row is
        // unambiguous and the anchor date renders as a day, not a year.
        let recordDate = calendar.date(byAdding: .day, value: -3, to: now) ?? now
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 123_600)
        try? repository.upsertVehicle(vehicle)

        let service = ServiceRecord(
            id: UUID.v7(), createdAt: recordDate, updatedAt: recordDate, deletedAt: nil,
            vehicleId: vehicle.id, date: recordDate, odometer: 123_600,
            money: Money(amount: Decimal(string: "148.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: "Bosch Service",
            items: [ServiceItem.make(title: "Oil change", category: .oil,
                                     cost: Money(amount: Decimal(string: "148.00")!,
                                                 currency: .eur, homeCurrency: .eur))],
            usedParts: [], tireSetId: nil, proposedReminderId: nil)
        try? repository.upsertServiceRecord(service)
    }

    /// The target the DEBUG presentation hook presents. Computed from the
    /// seeded car's just-saved oil service through the SAME core decision the
    /// save path uses, so the screenshot is the real offer, not a stand-in.
    @MainActor
    static func makeTarget() -> ServiceReminderOfferTarget? {
        guard let repository = try? AppStore.repository(),
              let vehicle = try? repository.liveVehicles().first else { return nil }
        let services = (try? repository.liveEntries(forVehicle: vehicle.id))?
            .compactMap { $0 as? ServiceRecord } ?? []
        // The most recent service first (the seed writes one).
        guard let service = services.sorted(by: { $0.date > $1.date }).first,
              let proposal = ReminderOffer.propose(afterService: service, liveReminders: []) else { return nil }
        return ServiceReminderOfferTarget(proposal: proposal)
    }
}
#endif

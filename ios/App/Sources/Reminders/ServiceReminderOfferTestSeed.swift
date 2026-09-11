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
        guard arguments.contains("-seedServiceReminderOffer")
            || arguments.contains("-seedSwapReminderOffer")
            || arguments.contains("-seedServiceLifetimeOffer") else { return }
        AppStore.resetForTestsOncePerLaunch()
        guard let repository = try? AppStore.repository() else { return }

        if arguments.contains("-seedSwapReminderOffer") {
            seedSwapReminder(repository)
        } else if arguments.contains("-seedServiceLifetimeOffer") {
            seedLifetimeService(repository)
        } else {
            seedOilService(repository)
        }
    }

    /// The PJ.22 pose: a just-saved service whose line item states its OWN
    /// lifetime (brakes, 30 000 km / 24 months) - a category with no curated
    /// interval. The offer sheet then shows an interval the user supplied, not
    /// a category guess.
    private static func seedLifetimeService(_ repository: TankbookRepository) {
        let now = Date()
        let recordDate = Calendar.current.date(byAdding: .day, value: -3, to: now) ?? now
        let vehicle = makeVehicle(initialOdometer: 123_600)
        try? repository.upsertVehicle(vehicle)

        let service = ServiceRecord(
            id: UUID.v7(), createdAt: recordDate, updatedAt: recordDate, deletedAt: nil,
            vehicleId: vehicle.id, date: recordDate, odometer: 123_600,
            money: Money(amount: Decimal(string: "210.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: "Bosch Service",
            items: [ServiceItem(title: "Brake pads front", category: .brakes,
                                cost: Money(amount: Decimal(string: "210.00")!,
                                            currency: .eur, homeCurrency: .eur),
                                partNumber: nil,
                                lifetime: ServiceItem.Lifetime(km: 30_000, months: 24))],
            usedParts: [], tireSetId: nil)
        try? repository.upsertServiceRecord(service)
    }

    /// The RV.77 oil state: a car plus a just-saved oil service record (so the
    /// log shows it and the offer's anchor is real), with NO live oil reminder -
    /// suppression must not hide the seeded offer.
    private static func seedOilService(_ repository: TankbookRepository) {
        let now = Date()
        let calendar = Calendar.current
        // "Sep 5" - a fixed date a couple of days in the past so the log row is
        // unambiguous and the anchor date renders as a day, not a year.
        let recordDate = calendar.date(byAdding: .day, value: -3, to: now) ?? now
        let vehicle = makeVehicle(initialOdometer: 123_600)
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
            usedParts: [], tireSetId: nil)
        try? repository.upsertServiceRecord(service)
    }

    /// The PJ.27 state: a car, a seasonal set, and the swap that mounted it, so
    /// the offer sheet shows the mount's own proposal (anchored at the mount,
    /// six months out) rather than an oil one.
    private static func seedSwapReminder(_ repository: TankbookRepository) {
        let now = Date()
        let calendar = Calendar.current
        let mountDate = calendar.date(byAdding: .day, value: -3, to: now) ?? now
        let vehicle = makeVehicle(initialOdometer: 123_600)
        try? repository.upsertVehicle(vehicle)

        let set = TireSetDraft(name: "Winter Nokian").build(vehicleId: vehicle.id, now: now)
        try? repository.upsertTireSet(set)

        let mount = ServiceRecord(
            id: UUID.v7(), createdAt: mountDate, updatedAt: mountDate, deletedAt: nil,
            vehicleId: vehicle.id, date: mountDate, odometer: 123_600,
            money: nil, note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: nil, items: [], usedParts: [],
            tireSetId: set.id)
        try? repository.upsertServiceRecord(mount)
    }

    private static func makeVehicle(initialOdometer: Int) -> Vehicle {
        let now = Date()
        return Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: initialOdometer)
    }

    /// The target the DEBUG presentation hook presents. Computed from the
    /// seeded car's just-saved record through the SAME core decision the save
    /// path uses (including the mounted set's name for a swap), so the
    /// screenshot is the real offer, not a stand-in.
    @MainActor
    static func makeTarget() -> ServiceReminderOfferTarget? {
        guard let repository = try? AppStore.repository(),
              let vehicle = try? repository.liveVehicles().first else { return nil }
        let services = (try? repository.liveEntries(forVehicle: vehicle.id))?
            .compactMap { $0 as? ServiceRecord } ?? []
        // The most recent service first (each seed writes one).
        guard let service = services.sorted(by: { $0.date > $1.date }).first else { return nil }
        let tireSetName = service.tireSetId.flatMap { id in
            (try? repository.liveTireSets(forVehicle: vehicle.id))?
                .first { $0.id == id }?.name
        }
        guard let proposal = ReminderOffer.propose(afterService: service,
                                                   tireSetName: tireSetName,
                                                   liveReminders: []) else { return nil }
        return ServiceReminderOfferTarget(proposal: proposal)
    }
}
#endif

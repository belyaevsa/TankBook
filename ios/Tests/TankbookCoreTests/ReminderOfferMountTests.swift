import Foundation
import Testing
@testable import TankbookCore

/// The seasonal swap reminder a tire MOUNT proposes (docs/JOURNEYS.md J7b "the
/// swap reminder each season", docs/NOTIFICATIONS.md -> "tire season"). A mount
/// is a `ServiceRecord` carrying `tireSetId`; it has no line items, which is
/// why the line-item offer rule could never see it. The proposal is anchored at
/// the mount date and recurring by months, and it is inert until the user
/// accepts it (hard rule 13).
@Suite struct ReminderOfferMountTests {

    private func makeVehicle() -> Vehicle {
        let timestamp = Date(timeIntervalSince1970: 1_752_000_000)
        return Vehicle(
            id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_930)
    }

    private func makeMount(vehicleId: UUID, date: Date,
                           odometer: Int? = 123_600) -> ServiceRecord {
        ServiceRecord(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: vehicleId, date: date, odometer: odometer,
            money: nil, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil, vendor: nil,
            items: [], usedParts: [], tireSetId: UUID.v7())
    }

    private func liveReminder(vehicleId: UUID, category: ReminderCategory) -> Reminder {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        return Reminder(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicleId, title: "Existing", category: category,
            dueDate: now.addingTimeInterval(30 * 86_400), dueOdometer: nil,
            recurrence: nil, sourceEntryId: nil, status: .scheduled)
    }

    // MARK: - The proposal

    @Test func aMountProposesASeasonalSwapReminderAnchoredAtTheMount() {
        let vehicle = makeVehicle()
        let calendar = Calendar(identifier: .gregorian)
        let mountDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15))!
        let mount = makeMount(vehicleId: vehicle.id, date: mountDate)

        let proposal = ReminderOffer.propose(afterService: mount,
                                             tireSetName: "Winter Nokian",
                                             liveReminders: [])

        #expect(proposal != nil)
        let offer = proposal!
        #expect(offer.category == .tires)
        #expect(offer.title == "Winter Nokian")
        #expect(offer.sourceEntryId == mount.id)
        #expect(offer.date == mountDate, "the anchor is the mount, never today")
        #expect(offer.everyKm == nil)
        #expect(offer.everyMonths == ReminderOffer.seasonalSwapMonths)

        // Accepting anchors the due date at the mount + the seasonal interval.
        let accepted = ReminderOffer.reminder(accepting: offer, everyKm: nil,
                                              everyMonths: ReminderOffer.seasonalSwapMonths,
                                              calendar: calendar)
        #expect(accepted?.dueDate == calendar.date(from: DateComponents(year: 2027, month: 4, day: 15)))
        #expect(accepted?.dueOdometer == nil)
        #expect(accepted?.recurrence == Reminder.Recurrence(everyKm: nil, everyMonths: 6))
        #expect(accepted?.sourceEntryId == mount.id)
        #expect(accepted?.status == .scheduled)
    }

    /// The set's name is what the reminder is called; a mount whose set cannot
    /// be named offers nothing rather than a nameless row.
    @Test func aMountWithNoSetNameOffersNothing() {
        let vehicle = makeVehicle()
        let mount = makeMount(vehicleId: vehicle.id, date: Date())
        #expect(ReminderOffer.propose(afterService: mount, liveReminders: []) == nil)
    }

    /// A `.tires` LINE ITEM still has no universal interval - the seasonal
    /// cadence belongs to the mount, not the category table.
    @Test func aTireLineItemStillOffersNothing() {
        let vehicle = makeVehicle()
        let date = Date()
        let service = ServiceRecord(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: vehicle.id, date: date, odometer: 123_600,
            money: nil, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil, vendor: nil,
            items: [ServiceItem.make(title: "Tire rotation", category: .tires, cost: nil)],
            usedParts: [], tireSetId: nil)
        #expect(ReminderOffer.propose(afterService: service, liveReminders: []) == nil)
    }

    @Test func aLiveTiresReminderSuppressesTheMountOffer() {
        let vehicle = makeVehicle()
        let mount = makeMount(vehicleId: vehicle.id, date: Date())
        let live = liveReminder(vehicleId: vehicle.id, category: .tires)
        #expect(ReminderOffer.propose(afterService: mount, tireSetName: "Winter Nokian",
                                      liveReminders: [live]) == nil,
                "a live tires reminder suppresses a second swap offer")
    }

    // MARK: - Declinable

    /// A proposal is inert: it is pure data, and nothing is persisted until the
    /// user accepts. Declining leaves no reminder (hard rule 13).
    @Test func decliningTheMountProposalLeavesNoReminder() throws {
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        let vehicle = makeVehicle()
        try repository.upsertVehicle(vehicle)
        let mount = makeMount(vehicleId: vehicle.id, date: Date())
        try repository.upsertServiceRecord(mount)

        let live = try repository.liveReminders(forVehicle: vehicle.id)
        let proposal = ReminderOffer.propose(afterService: mount,
                                             tireSetName: "Winter Nokian",
                                             liveReminders: live)
        #expect(proposal != nil, "the mount must propose")

        // Declining is simply not accepting: no row is written.
        #expect(try repository.liveReminders(forVehicle: vehicle.id).isEmpty,
                "a proposal is inert until the user accepts it")
    }

    @Test func acceptingTheMountProposalWritesOneReminder() throws {
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        let vehicle = makeVehicle()
        try repository.upsertVehicle(vehicle)
        let mount = makeMount(vehicleId: vehicle.id, date: Date())
        try repository.upsertServiceRecord(mount)

        let proposal = ReminderOffer.propose(afterService: mount,
                                             tireSetName: "Winter Nokian",
                                             liveReminders: [])!
        let accepted = ReminderOffer.reminder(accepting: proposal, everyKm: nil,
                                              everyMonths: ReminderOffer.seasonalSwapMonths)!
        try repository.upsertReminder(accepted)

        let readBack = try repository.liveReminders(forVehicle: vehicle.id)
        #expect(readBack == [accepted])
    }
}

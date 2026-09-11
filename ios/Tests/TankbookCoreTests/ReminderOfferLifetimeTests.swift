import Foundation
import Testing
@testable import TankbookCore

/// PJ.22 - an item's own `lifetime` drives the post-save reminder offer
/// (docs/JOURNEYS.md J7 "app proposes the next reminder from item lifetimes").
/// The interval the user typed on the line item overrides the curated category
/// table, makes a category with no universal cadence schedulable, and anchors at
/// the record's own date/odometer - never at today. Kept in its own suite so
/// `ReminderOfferTests` stays under the linter's type-body ceiling; the fixtures
/// mirror that suite's.
@Suite struct ReminderOfferLifetimeTests {

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

    private func makeService(vehicleId: UUID, date: Date = Date(timeIntervalSince1970: 1_752_000_000),
                             odometer: Int? = 123_600,
                             items: [ServiceItem] = []) -> ServiceRecord {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        return ServiceRecord(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicleId, date: date, odometer: odometer,
            money: nil, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil, vendor: nil,
            items: items, usedParts: [], tireSetId: nil)
    }

    /// An item's own lifetime IS the interval the offer carries: it overrides
    /// the curated table, and it makes a category with no universal cadence
    /// schedulable, because the user stated the number (hard rule 13). Oracle:
    /// J7's "app proposes the next reminder from item lifetimes".
    @Test func itemLifetimeMakesANonSchedulableCategoryProposable() {
        let vehicle = makeVehicle()
        let service = makeService(
            vehicleId: vehicle.id,
            items: [ServiceItem(title: "Brake pads front", category: .brakes, cost: nil,
                                partNumber: nil,
                                lifetime: ServiceItem.Lifetime(km: 30_000, months: 24))])
        let proposal = ReminderOffer.propose(afterService: service, liveReminders: [])
        #expect(proposal != nil, "a lifetime makes the row schedulable")
        #expect(proposal?.category == .brakes)
        #expect(proposal?.everyKm == 30_000)
        #expect(proposal?.everyMonths == 24)
    }

    /// The same lifetime on an oil item beats the curated oil default - the
    /// user's number is theirs, and the table is only a fallback.
    @Test func itemLifetimeOverridesTheOilCuratedDefault() {
        let vehicle = makeVehicle()
        let service = makeService(
            vehicleId: vehicle.id,
            items: [ServiceItem(title: "Oil service", category: .oil, cost: nil,
                                partNumber: nil,
                                lifetime: ServiceItem.Lifetime(km: 20_000, months: 18))])
        let proposal = ReminderOffer.propose(afterService: service, liveReminders: [])
        #expect(proposal?.everyKm == 20_000)
        #expect(proposal?.everyMonths == 18)
    }

    /// A free-text `.other` row is schedulable only when it carries a lifetime,
    /// because that is what supplies the interval; its own text is the title.
    @Test func freeTextItemWithALifetimeIsSchedulable() {
        let vehicle = makeVehicle()
        let service = makeService(
            vehicleId: vehicle.id,
            items: [ServiceItem(title: "Замена ремня", category: .other("ремень"), cost: nil,
                                partNumber: nil,
                                lifetime: ServiceItem.Lifetime(km: 60_000, months: nil))])
        let proposal = ReminderOffer.propose(afterService: service, liveReminders: [])
        #expect(proposal?.category == .other("ремень"))
        #expect(proposal?.everyKm == 60_000)
        #expect(proposal?.everyMonths == nil)
    }

    /// An item lifetime produces ONE reminder linked by `sourceEntryId` and
    /// anchored at the record's own date and odometer - never at today. Oracle:
    /// J7's sentence and the record's own values.
    @Test func itemLifetimeProposalIsAnchoredAtTheRecord() {
        let vehicle = makeVehicle()
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let service = makeService(
            vehicleId: vehicle.id, date: date, odometer: 123_600,
            items: [ServiceItem(title: "Brake pads front", category: .brakes, cost: nil,
                                partNumber: nil,
                                lifetime: ServiceItem.Lifetime(km: 30_000, months: 24))])
        let proposal = ReminderOffer.propose(afterService: service, liveReminders: [])!
        let accepted = ReminderOffer.reminder(accepting: proposal, everyKm: proposal.everyKm,
                                              everyMonths: proposal.everyMonths,
                                              calendar: calendar)!
        #expect(accepted.sourceEntryId == service.id)
        #expect(accepted.dueDate
                == calendar.date(from: DateComponents(year: 2028, month: 3, day: 10))!,
                "anchored at the record's date + 24 months, never at today")
        #expect(accepted.dueOdometer == 123_600 + 30_000)
        #expect(accepted.recurrence == Reminder.Recurrence(everyKm: 30_000, everyMonths: 24))
    }

    /// Declining leaves no reminder at all (hard rule 13): the proposal is inert
    /// data until the user accepts it.
    @Test func decliningAnItemLifetimeProposalLeavesNoReminder() throws {
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        let vehicle = makeVehicle()
        try repository.upsertVehicle(vehicle)
        let service = makeService(
            vehicleId: vehicle.id,
            items: [ServiceItem(title: "Brake pads front", category: .brakes, cost: nil,
                                partNumber: nil,
                                lifetime: ServiceItem.Lifetime(km: 30_000, months: 24))])
        try repository.upsertServiceRecord(service)
        let live = try repository.liveReminders(forVehicle: vehicle.id)
        #expect(ReminderOffer.propose(afterService: service, liveReminders: live) != nil)
        #expect(try repository.liveReminders(forVehicle: vehicle.id).isEmpty,
                "a proposal writes nothing until accepted")
    }

    /// Exactly one reminder per accepted proposal: once accepted, the live
    /// reminder suppresses a second offer, so saving the record again cannot
    /// mint a twin.
    @Test func acceptingAnItemLifetimeProposalMintsOneAndSuppressesASecond() throws {
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        let vehicle = makeVehicle()
        try repository.upsertVehicle(vehicle)
        let service = makeService(
            vehicleId: vehicle.id,
            items: [ServiceItem(title: "Brake pads front", category: .brakes, cost: nil,
                                partNumber: nil,
                                lifetime: ServiceItem.Lifetime(km: 30_000, months: 24))])
        try repository.upsertServiceRecord(service)
        let proposal = ReminderOffer.propose(afterService: service, liveReminders: [])!
        let accepted = ReminderOffer.reminder(accepting: proposal, everyKm: 30_000,
                                              everyMonths: 24)!
        try repository.upsertReminder(accepted)
        #expect(try repository.liveReminders(forVehicle: vehicle.id).count == 1)
        let live = try repository.liveReminders(forVehicle: vehicle.id)
        #expect(ReminderOffer.propose(afterService: service, liveReminders: live) == nil,
                "the live reminder suppresses a second mint")
    }

    /// The interval is editable before accepting, and an edit AFTERWARDS is not
    /// overwritten by a later default: the accepted reminder's own recurrence is
    /// the user's, and a re-proposal is suppressed while it is live (hard rule
    /// 13 - once changed it is theirs).
    @Test func editedIntervalAfterAcceptingIsNotOverwrittenByALaterDefault() throws {
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        let vehicle = makeVehicle()
        try repository.upsertVehicle(vehicle)
        let service = makeService(
            vehicleId: vehicle.id,
            items: [ServiceItem(title: "Oil service", category: .oil, cost: nil)])
        try repository.upsertServiceRecord(service)
        let proposal = ReminderOffer.propose(afterService: service, liveReminders: [])!
        // The user edits the suggestion in the same breath.
        let accepted = ReminderOffer.reminder(accepting: proposal, everyKm: 20_000,
                                              everyMonths: 18)!
        try repository.upsertReminder(accepted)
        // ... and edits it again afterwards through the reminder form.
        var edited = accepted
        edited.recurrence = Reminder.Recurrence(everyKm: 25_000, everyMonths: 30)
        edited.updatedAt = Date()
        try repository.upsertReminder(edited)

        let live = try repository.liveReminders(forVehicle: vehicle.id)
        #expect(ReminderOffer.propose(afterService: service, liveReminders: live) == nil,
                "a later save must not overwrite the user's edited interval")
        #expect(try repository.liveReminders(forVehicle: vehicle.id).first?.recurrence
                == Reminder.Recurrence(everyKm: 25_000, everyMonths: 30))
    }

    /// PJ.62 decided `Reminder.sourceEntryId` is the SINGLE link, so
    /// `ServiceRecord.proposedReminderId` is dropped - from the Swift type, the
    /// migration, the generated payload schema and `docs/SCHEMA.md`. A second
    /// pointer for one relationship would be two sources of truth.
    @Test func proposedReminderIdIsGoneEverywhere() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TankbookCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // ios
            .deletingLastPathComponent()  // repo root
        let files = [
            "ios/Sources/TankbookCore/Domain/Entities.swift",
            "ios/Sources/TankbookCore/Persistence/Migrations.swift",
            "ios/Sources/TankbookCore/Persistence/Records.swift",
            "ios/Sources/TankbookCore/Schemas/v1/serviceRecord.schema.json",
            "docs/schemas/v1/serviceRecord.schema.json",
            "docs/fixtures/payloads/v1/serviceRecord.json",
            "docs/SCHEMA.md"
        ]
        for path in files {
            let text = try String(contentsOf: repoRoot.appendingPathComponent(path),
                                  encoding: .utf8)
            #expect(!text.contains("proposedReminderId"),
                    "\(path) still references the dropped field")
        }
    }
}

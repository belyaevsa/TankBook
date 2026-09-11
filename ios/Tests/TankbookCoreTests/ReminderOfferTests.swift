import Foundation
import Testing
@testable import TankbookCore

/// RV.77 - the post-save "remind you next time?" offer (docs/JOURNEYS.md J7d
/// "Just did it"). The pure decision layer in `ReminderOffer`: which saved
/// record proposes a next reminder, which category drives it, when a live
/// reminder of that category suppresses the offer, and how an accepted offer
/// builds the anchored reminder. Every rule here tests without a simulator -
/// the save paths in the app fetch the car's live reminders and hand them in.
@Suite struct ReminderOfferTests {

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

    private func makeExpense(vehicleId: UUID, category: ExpenseCategory,
                             title: String, date: Date = Date(timeIntervalSince1970: 1_752_000_000))
        -> Expense {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        return Expense(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicleId, date: date, odometer: nil,
            money: Money(amount: Decimal(120), currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, category: category, title: title,
            recurrence: nil, installedInServiceId: nil)
    }

    private func liveReminder(vehicleId: UUID, category: ReminderCategory,
                              status: ReminderStatus = .scheduled) -> Reminder {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        return Reminder(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicleId, title: "Existing", category: category,
            dueDate: now.addingTimeInterval(30 * 86_400), dueOdometer: nil,
            recurrence: nil, sourceEntryId: nil, status: status)
    }

    // MARK: - The curated interval table

    @Test func oilAndInsuranceHaveCuratedIntervals() {
        #expect(ReminderOffer.defaultInterval(for: .oil) == Reminder.Recurrence(everyKm: 15_000, everyMonths: 12))
        #expect(ReminderOffer.defaultInterval(for: .insurance) == Reminder.Recurrence(everyKm: nil, everyMonths: 12))
    }

    @Test func categoriesWithoutASensibleIntervalOfferNothing() {
        for category: ReminderCategory in [.brakes, .tires, .battery, .filters, .inspection,
                                           .repair, .parts, .wash, .custom, .other("")] {
            #expect(ReminderOffer.defaultInterval(for: category) == nil,
                    "\(category) has no universal interval - offering one would invent a fact")
        }
    }

    // MARK: - Service proposal

    @Test func oilServiceProposesAnOfferAnchoredAtTheRecord() {
        let vehicle = makeVehicle()
        let date = Date(timeIntervalSince1970: 1_752_000_000)
        let service = makeService(
            vehicleId: vehicle.id, date: date, odometer: 123_600,
            items: [ServiceItem.make(title: "Oil service", category: .oil, cost: nil)])
        let proposal = ReminderOffer.propose(afterService: service, liveReminders: [])

        #expect(proposal != nil)
        let offer = proposal!
        #expect(offer.vehicleId == vehicle.id)
        #expect(offer.category == .oil)
        #expect(offer.title == "Oil service")
        #expect(offer.sourceEntryId == service.id)
        #expect(offer.date == date)
        #expect(offer.odometer == 123_600)
        #expect(offer.everyKm == 15_000)
        #expect(offer.everyMonths == 12)
    }

    @Test func categoryWithoutAnIntervalOffersNothingForAService() {
        let vehicle = makeVehicle()
        let service = makeService(
            vehicleId: vehicle.id,
            items: [ServiceItem.make(title: "Brake pads", category: .brakes, cost: nil)])
        #expect(ReminderOffer.propose(afterService: service, liveReminders: []) == nil)
    }

    @Test func uncategorizedLumpSumOffersNothing() {
        let vehicle = makeVehicle()
        let service = makeService(
            vehicleId: vehicle.id,
            items: [ServiceItem.make(title: "Annual service", category: .other(""), cost: nil)])
        #expect(ReminderOffer.propose(afterService: service, liveReminders: []) == nil,
                "an uncategorized record cannot claim an interval category")
    }

    @Test func severalTitledItemsSharingOneSchedulableCategoryOfferIt() {
        let vehicle = makeVehicle()
        // An oil change often logs as more than one titled row (oil + oil
        // filter) but stays ONE schedulable category - the offer is keyed on
        // the DISTINCT interval-bearing categories, not the item count.
        let service = makeService(
            vehicleId: vehicle.id,
            items: [
                ServiceItem.make(title: "Oil service", category: .oil, cost: nil),
                ServiceItem.make(title: "Oil filter", category: .oil, cost: nil)
            ])
        let proposal = ReminderOffer.propose(afterService: service, liveReminders: [])
        #expect(proposal != nil)
        #expect(proposal!.category == .oil)
    }

    @Test func recordMixingASchedulableAndANonSchedulableCategoryOffersTheSchedulableOne() {
        let vehicle = makeVehicle()
        // Oil + wash: wash has no curated interval, so the record still
        // reduces to exactly one schedulable category and proposes oil.
        let service = makeService(
            vehicleId: vehicle.id,
            items: [
                ServiceItem.make(title: "Oil service", category: .oil, cost: nil),
                ServiceItem.make(title: "Car wash", category: .wash, cost: nil)
            ])
        let proposal = ReminderOffer.propose(afterService: service, liveReminders: [])
        #expect(proposal != nil)
        #expect(proposal!.category == .oil)
    }

    // MARK: - Expense proposal

    @Test func insuranceExpenseProposesAnAnnualReminder() {
        let vehicle = makeVehicle()
        let expense = makeExpense(vehicleId: vehicle.id, category: .insurance, title: "ОСАГО")
        let proposal = ReminderOffer.propose(afterExpense: expense, liveReminders: [])

        #expect(proposal != nil)
        let offer = proposal!
        #expect(offer.category == .insurance)
        #expect(offer.title == "ОСАГО")
        #expect(offer.everyMonths == 12)
        #expect(offer.everyKm == nil)
        #expect(offer.sourceEntryId == expense.id)
    }

    @Test func nonRecurringExpenseOffersNothing() {
        let vehicle = makeVehicle()
        for category: ExpenseCategory in [.tax, .parking, .toll, .fine, .accessory, .parts, .other("")] {
            let expense = makeExpense(vehicleId: vehicle.id, category: category, title: "Cost")
            #expect(ReminderOffer.propose(afterExpense: expense, liveReminders: []) == nil,
                    "\(category) has no cadence - nothing to offer")
        }
    }

    // MARK: - Suppression (the "three oil reminders" failure mode)

    @Test func liveReminderOfTheCategorySuppressesTheOffer() {
        let vehicle = makeVehicle()
        let service = makeService(
            vehicleId: vehicle.id,
            items: [ServiceItem.make(title: "Oil service", category: .oil, cost: nil)])
        let live = liveReminder(vehicleId: vehicle.id, category: .oil)
        #expect(ReminderOffer.propose(afterService: service, liveReminders: [live]) == nil,
                "an existing scheduled oil reminder must suppress a second offer")
    }

    @Test func attentionReminderOfTheCategorySuppressesTheOffer() {
        let vehicle = makeVehicle()
        let expense = makeExpense(vehicleId: vehicle.id, category: .insurance, title: "ОСАГО")
        let live = liveReminder(vehicleId: vehicle.id, category: .insurance, status: .attention)
        #expect(ReminderOffer.propose(afterExpense: expense, liveReminders: [live]) == nil)
    }

    @Test func liveReminderOfAnotherCategoryDoesNotSuppress() {
        let vehicle = makeVehicle()
        let service = makeService(
            vehicleId: vehicle.id,
            items: [ServiceItem.make(title: "Oil service", category: .oil, cost: nil)])
        let otherCarLive = liveReminder(vehicleId: vehicle.id, category: .brakes)
        #expect(ReminderOffer.propose(afterService: service, liveReminders: [otherCarLive]) != nil)
    }

    @Test func liveReminderOnAnotherCarDoesNotSuppress() {
        let vehicle = makeVehicle()
        let otherVehicle = makeVehicle()
        let service = makeService(
            vehicleId: vehicle.id,
            items: [ServiceItem.make(title: "Oil service", category: .oil, cost: nil)])
        let otherCarLive = liveReminder(vehicleId: otherVehicle.id, category: .oil)
        #expect(ReminderOffer.propose(afterService: service, liveReminders: [otherCarLive]) != nil,
                "suppression is per vehicle - a reminder on another car cannot block this one")
    }

    @Test func terminalReminderDoesNotSuppress() {
        let vehicle = makeVehicle()
        let service = makeService(
            vehicleId: vehicle.id,
            items: [ServiceItem.make(title: "Oil service", category: .oil, cost: nil)])
        let done = liveReminder(vehicleId: vehicle.id, category: .oil, status: .done(entryId: nil))
        #expect(ReminderOffer.propose(afterService: service, liveReminders: [done]) != nil,
                "history is not an existing reminder - only live rows suppress")
    }

    // MARK: - Acceptance

    @Test func acceptanceNeedsAtLeastOneDueField() {
        #expect(ReminderOffer.acceptance(everyKm: 15_000, everyMonths: nil, odometer: 123_600) == .ready)
        #expect(ReminderOffer.acceptance(everyKm: nil, everyMonths: 12, odometer: nil) == .ready)
        #expect(ReminderOffer.acceptance(everyKm: 15_000, everyMonths: nil, odometer: nil) == .noDueField,
                "km-only cannot anchor without a record odometer")
        #expect(ReminderOffer.acceptance(everyKm: nil, everyMonths: nil, odometer: 123_600) == .noDueField)
    }

    @Test func acceptedReminderIsAnchoredAtTheRecordAndCarriesTheChain() {
        let vehicle = makeVehicle()
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let service = makeService(vehicleId: vehicle.id, date: date, odometer: 123_600,
                                  items: [ServiceItem.make(title: "Oil service", category: .oil, cost: nil)])
        let proposal = ReminderOffer.propose(afterService: service, liveReminders: [])!
        let accepted = ReminderOffer.reminder(accepting: proposal, everyKm: 15_000, everyMonths: 12,
                                              calendar: calendar)

        #expect(accepted != nil)
        let reminder = accepted!
        #expect(reminder.vehicleId == vehicle.id)
        #expect(reminder.category == .oil)
        #expect(reminder.title == "Oil service")
        // Anchored at the RECORD, never at today (the no-drift rule):
        // dueDate = record date + 12 months = 2027-03-10.
        let expectedDate = calendar.date(from: DateComponents(year: 2027, month: 3, day: 10))!
        #expect(reminder.dueDate == expectedDate)
        #expect(reminder.dueOdometer == 123_600 + 15_000)
        #expect(reminder.recurrence == Reminder.Recurrence(everyKm: 15_000, everyMonths: 12))
        #expect(reminder.sourceEntryId == service.id)
        #expect(reminder.status == .scheduled)
    }

    @Test func editedIntervalIsRespected() {
        let vehicle = makeVehicle()
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let service = makeService(vehicleId: vehicle.id, date: date, odometer: 100_000,
                                  items: [ServiceItem.make(title: "Oil service", category: .oil, cost: nil)])
        let proposal = ReminderOffer.propose(afterService: service, liveReminders: [])!
        // The user edits the suggestion in the same breath (hard rule 13).
        let accepted = ReminderOffer.reminder(accepting: proposal, everyKm: 20_000, everyMonths: 24,
                                              calendar: calendar)!
        let expectedDate = calendar.date(from: DateComponents(year: 2028, month: 3, day: 10))!
        #expect(accepted.dueDate == expectedDate)
        #expect(accepted.dueOdometer == 120_000)
        #expect(accepted.recurrence == Reminder.Recurrence(everyKm: 20_000, everyMonths: 24))
    }

    @Test func noKmHalfWhenTheRecordHasNoOdometer() {
        let vehicle = makeVehicle()
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let service = makeService(vehicleId: vehicle.id, date: date, odometer: nil,
                                  items: [ServiceItem.make(title: "Oil service", category: .oil, cost: nil)])
        let proposal = ReminderOffer.propose(afterService: service, liveReminders: [])!
        // The months half anchors; the km half cannot without an odometer - the
        // accepted reminder is date-only, mirroring ReminderLifecycle.complete.
        let accepted = ReminderOffer.reminder(accepting: proposal, everyKm: 15_000, everyMonths: 12,
                                              calendar: calendar)!
        #expect(accepted.dueDate != nil)
        #expect(accepted.dueOdometer == nil)
    }

    @Test func acceptedReminderRoundTripsThroughPersistence() throws {
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        let vehicle = makeVehicle()
        try repository.upsertVehicle(vehicle)
        let service = makeService(vehicleId: vehicle.id,
                                  items: [ServiceItem.make(title: "Oil service", category: .oil, cost: nil)])
        try repository.upsertServiceRecord(service)
        let live = (try? repository.liveReminders(forVehicle: vehicle.id)) ?? []
        let proposal = ReminderOffer.propose(afterService: service, liveReminders: live)!
        let accepted = ReminderOffer.reminder(accepting: proposal, everyKm: 15_000, everyMonths: 12)!
        try repository.upsertReminder(accepted)

        let readBack = try repository.liveReminders(forVehicle: vehicle.id)
        #expect(readBack.count == 1)
        #expect(readBack[0] == accepted)
    }
}

import Foundation
import Testing
@testable import TankbookCore

/// P6.2 monthly-summary notification tests (docs/NOTIFICATIONS.md, J8). The
/// plan is the whole decision layer, so these assert its OUTPUT - fire dates,
/// identifiers, amounts, the empty-month silence - never a
/// `UNUserNotificationCenter` call. The rules the tests pin:
/// 1. one notification PER CAR that spent the month, each in the car's own
///    home currency (the multi-vehicle decision, written into the doc);
/// 2. a month with nothing to say produces NO notification - no entries, only
///    rate-pending entries, or a zero total are all silence;
/// 3. the amount is the sum of stored `homeAmount` snapshots, never a
///    re-conversion at a later rate (hard rule 3);
/// 4. turning the feature OFF cancels every pending identifier, and the
///    toggle-off cancel is the plan's own behaviour (mutation 2's anchor);
/// 5. the fire date is always the 1st of the next month at 10:00 local.
@Suite struct MonthlySummaryNotificationTests {

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int = 0, _ minute: Int = 0) -> Date {
        Self.calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// An exact `Decimal` from its written form. `Decimal` is NOT
    /// `ExpressibleByFloatLiteral` in the way people assume: `let d: Decimal =
    /// 67.79` routes through Double and carries its binary residue
    /// (67.79000000000000625...). Stored amounts are exact - they come from
    /// typed/parsed strings - so the fixtures build them the same way.
    private func dec(_ string: String) -> Decimal { Decimal(string: string)! }

    private func makeVehicle(id: UUID = UUID.v7(), name: String = "Volvo V60",
                             currency: CurrencyCode = .eur,
                             archived: Bool = false) -> Vehicle {
        Vehicle(
            id: id, createdAt: date(2025, 1, 1), updatedAt: date(2025, 1, 1),
            name: name, powertrain: .ice, fuelKinds: [.diesel],
            homeCurrency: currency,
            units: Vehicle.Units(distance: .km, volume: .l,
                                 consumption: .lPer100, energy: .kWhPer100),
            archived: archived)
    }

    /// A fill-up with an EXACT money pair: `homeAmount` is written as given and
    /// never recomputed - the reconstruction a snapshot is (docs/SCHEMA.md:
    /// "the stored value is the authority"). `rateDate` is the ENTRY date, the
    /// invariant the money trap in the brief is about.
    private func makeFill(id: UUID = UUID.v7(),
                          vehicleID: UUID,
                          on day: Date,
                          amount: Decimal,
                          currency: CurrencyCode,
                          homeAmount: Decimal?,
                          homeCurrency: CurrencyCode = .eur,
                          createdAt: Date = Date(timeIntervalSinceReferenceDate: 1_000_000),
                          volumeL: Double = 40,
                          isFull: Bool = true) -> FillUp {
        FillUp(
            id: id, createdAt: createdAt, updatedAt: createdAt,
            vehicleId: vehicleID, date: day,
            money: Money(amount: amount, currency: currency,
                         homeAmount: homeAmount, homeCurrency: homeCurrency,
                         rate: currency == homeCurrency ? 1 : 4.2706,
                         rateDate: day, rateSource: .ecb),
            provenance: .manual, volumeL: volumeL, fuelKind: .diesel,
            isFull: isFull, crossCheck: .notApplicable)
    }

    private func plan(vehicles: [Vehicle],
                      entries: [UUID: [any Entry]] = [:],
                      resolutions: Set<DuplicateDetector.PairKey> = [],
                      now: Date,
                      enabled: Bool = true) -> MonthlySummaryNotificationPlan {
        MonthlySummaryPlanner.plan(
            vehicles: vehicles, entriesByVehicle: entries,
            duplicateResolutions: resolutions,
            now: now, enabled: enabled, calendar: Self.calendar)
    }

    // MARK: - 1. The fire moment and the summarized month

    /// A reconcile on 20 August schedules the August summary to fire on
    /// 1 September at 10:00 - the month being summarized is the month that has
    /// just ended when the notification fires (docs/NOTIFICATIONS.md: "1st of
    /// month, 10:00").
    @Test func firesOnFirstOfNextMonthAtTenDescribingTheCurrentMonth() {
        let vehicle = makeVehicle()
        let entry = makeFill(vehicleID: vehicle.id, on: date(2025, 8, 15),
                             amount: 100, currency: .eur, homeAmount: 100)
        let plan = self.plan(vehicles: [vehicle],
                             entries: [vehicle.id: [entry]],
                             now: date(2025, 8, 20, 12, 0))

        let notification = plan.scheduled.first
        #expect(plan.scheduled.count == 1)
        #expect(notification?.fireDate == date(2025, 9, 1, 10, 0),
                "fires on the 1st of the next month at 10:00, not at the due moment")
        #expect(notification?.body.summaryYear == 2025)
        #expect(notification?.body.summaryMonth == 8)
        #expect(notification?.body.vehicleName == "Volvo V60")
        #expect(notification?.body.homeCurrency == .eur)
    }

    /// Every scheduled fire time is 10:00 local, minute 0 - humane hours, never
    /// the save's own moment (docs/NOTIFICATIONS.md -> Quiet by scheduling).
    @Test func everyScheduledTimeIsTenHundred() {
        let vehicle = makeVehicle()
        let entry = makeFill(vehicleID: vehicle.id, on: date(2025, 8, 15),
                             amount: 40, currency: .eur, homeAmount: 40)
        let plan = self.plan(vehicles: [vehicle],
                             entries: [vehicle.id: [entry]],
                             now: date(2025, 8, 20, 23, 45))

        let components = Self.calendar.dateComponents(
            [.hour, .minute], from: plan.scheduled.first!.fireDate)
        #expect(components.hour == MonthlySummaryPlanner.fireHour)
        #expect(components.minute == 0)
    }

    /// December rolls to January: a summary armed in December fires on
    /// 1 January of the NEXT year at 10:00, never on a fabricated 1/13.
    @Test func decemberSummaryRollsToJanuary() {
        let vehicle = makeVehicle()
        let entry = makeFill(vehicleID: vehicle.id, on: date(2025, 12, 20),
                             amount: 80, currency: .eur, homeAmount: 80)
        let plan = self.plan(vehicles: [vehicle],
                             entries: [vehicle.id: [entry]],
                             now: date(2025, 12, 20, 12, 0))

        #expect(plan.scheduled.first?.fireDate == date(2026, 1, 1, 10, 0))
        #expect(plan.scheduled.first?.body.summaryYear == 2025)
        #expect(plan.scheduled.first?.body.summaryMonth == 12)
    }

    // MARK: - 2. The amount is the stored snapshot sum (hard rule 3)

    /// The total is the sum of the entries' STORED `homeAmount` snapshots - a
    /// 289.50 PLN fill converts at its own rate to 67.79 EUR (never re-derived),
    /// and a same-currency fill adds its own 50 EUR. The month reads 117.79 EUR.
    @Test func amountIsTheSumOfStoredHomeSnapshots() {
        let vehicle = makeVehicle()
        let foreign = makeFill(vehicleID: vehicle.id, on: date(2025, 8, 3),
                               amount: dec("289.50"), currency: .pln, homeAmount: dec("67.79"))
        let local = makeFill(vehicleID: vehicle.id, on: date(2025, 8, 21),
                             amount: 50, currency: .eur, homeAmount: 50)
        let plan = self.plan(vehicles: [vehicle],
                             entries: [vehicle.id: [foreign, local]],
                             now: date(2025, 8, 25, 12, 0))

        let body = plan.scheduled.first!.body
        #expect(body.amount == dec("117.79"),
                "the snapshot sum, never a re-conversion - got \(body.amount)")
        #expect(body.homeCurrency == .eur)
    }

    /// A fill whose rate is still pending (F3/F9) contributes NOTHING - the
    /// summary only ever adds a snapshot that actually exists.
    @Test func ratePendingEntryContributesNothing() {
        let vehicle = makeVehicle()
        let pending = makeFill(vehicleID: vehicle.id, on: date(2025, 8, 10),
                               amount: 289.50, currency: .pln, homeAmount: nil)
        let settled = makeFill(vehicleID: vehicle.id, on: date(2025, 8, 20),
                               amount: 10, currency: .eur, homeAmount: 10)
        let plan = self.plan(vehicles: [vehicle],
                             entries: [vehicle.id: [pending, settled]],
                             now: date(2025, 8, 25, 12, 0))

        #expect(plan.scheduled.first?.body.amount == 10,
                "the pending fill is absent from the total, not counted as zero")
    }

    // MARK: - 3. Nothing to say -> no notification

    /// A month with no entries is SILENT. The fixture is non-vacuous: the car
    /// has entries, just not in the summarized month - the test fails if the
    /// code ignores the month boundary and notifies about any entries at all.
    @Test func aMonthWithNoEntriesProducesNoNotification() {
        let vehicle = makeVehicle()
        let julyEntry = makeFill(vehicleID: vehicle.id, on: date(2025, 7, 15),
                                 amount: 90, currency: .eur, homeAmount: 90)
        let plan = self.plan(vehicles: [vehicle],
                             entries: [vehicle.id: [julyEntry]],
                             now: date(2025, 8, 20, 12, 0))

        #expect(plan.scheduled.isEmpty,
                "July spend must not announce itself in August's summary")
    }

    /// A car with NO entries at all is silent too - a fresh garage gets no push
    /// telling it nothing happened.
    @Test func aCarWithNoEntriesAtAllIsSilent() {
        let vehicle = makeVehicle()
        let plan = self.plan(vehicles: [vehicle], entries: [:],
                             now: date(2025, 8, 20, 12, 0))
        #expect(plan.scheduled.isEmpty)
    }

    /// A month whose only entries are still rate-pending has a home-currency
    /// total of nothing - no notification, never "August: 0 €" (a push that
    /// says nothing happened is a nag).
    @Test func allRatePendingMonthIsSilent() {
        let vehicle = makeVehicle()
        let pending = makeFill(vehicleID: vehicle.id, on: date(2025, 8, 10),
                               amount: 289.50, currency: .pln, homeAmount: nil)
        let plan = self.plan(vehicles: [vehicle],
                             entries: [vehicle.id: [pending]],
                             now: date(2025, 8, 20, 12, 0))
        #expect(plan.scheduled.isEmpty)
    }

    /// A zero home-currency total is silence. (A free home charge or a zero
    /// receipt can land a zero - the summary must not announce a zero figure.)
    @Test func aZeroTotalIsSilent() {
        let vehicle = makeVehicle()
        let free = makeFill(vehicleID: vehicle.id, on: date(2025, 8, 10),
                            amount: 0, currency: .eur, homeAmount: 0)
        let plan = self.plan(vehicles: [vehicle],
                             entries: [vehicle.id: [free]],
                             now: date(2025, 8, 20, 12, 0))
        #expect(plan.scheduled.isEmpty)
    }

    // MARK: - 4. One per car, each in its own currency

    /// Two cars both spend in the month: TWO notifications, one per car, each
    /// carrying its own vehicle id, amount and home currency - the decision
    /// written into docs/NOTIFICATIONS.md. A car that spent nothing is absent.
    @Test func oneNotificationPerVehicleThatSpent() {
        let volvo = makeVehicle(id: UUID.v7(), name: "Volvo V60", currency: .eur)
        let ev = makeVehicle(id: UUID.v7(), name: "ID.4", currency: .usd)
        let silent = makeVehicle(id: UUID.v7(), name: "Archived? no, just silent", currency: .eur)

        let volvoEntry = makeFill(vehicleID: volvo.id, on: date(2025, 8, 5),
                                  amount: 100, currency: .eur, homeAmount: 100)
        let evEntry = makeFill(vehicleID: ev.id, on: date(2025, 8, 9),
                               amount: 40, currency: .usd, homeAmount: 40,
                               homeCurrency: .usd)

        let plan = self.plan(
            vehicles: [volvo, ev, silent],
            entries: [volvo.id: [volvoEntry], ev.id: [evEntry]],
            now: date(2025, 8, 20, 12, 0))

        #expect(plan.scheduled.count == 2)
        let byVehicle = Dictionary(grouping: plan.scheduled, by: \.vehicleID)
        #expect(byVehicle[volvo.id]?.first?.body.amount == 100)
        #expect(byVehicle[volvo.id]?.first?.body.homeCurrency == .eur)
        #expect(byVehicle[ev.id]?.first?.body.amount == 40)
        #expect(byVehicle[ev.id]?.first?.body.homeCurrency == .usd)
        #expect(byVehicle[silent.id] == nil,
                "a car that spent nothing in the month gets no summary")
    }

    // MARK: - 5. Re-arm replaces by identifier

    /// The identifier encodes vehicle + summarized month, so a later reconcile
    /// with fresher data REPLACES the pending notification instead of stacking
    /// a second one - the P3.6 "exactly one, never a nag loop" property carried
    /// over to the summary.
    @Test func reArmReplacesByIdentifier() {
        let vehicle = makeVehicle()
        let early = makeFill(vehicleID: vehicle.id, on: date(2025, 8, 2),
                             amount: 30, currency: .eur, homeAmount: 30)
        let later = makeFill(vehicleID: vehicle.id, on: date(2025, 8, 20),
                             amount: 70, currency: .eur, homeAmount: 70)

        let firstArm = self.plan(vehicles: [vehicle],
                                 entries: [vehicle.id: [early]],
                                 now: date(2025, 8, 10, 12, 0))
        let secondArm = self.plan(vehicles: [vehicle],
                                  entries: [vehicle.id: [early, later]],
                                  now: date(2025, 8, 25, 12, 0))

        #expect(firstArm.scheduled.first?.identifier == secondArm.scheduled.first?.identifier,
                "same vehicle + same month -> same identifier, a replace not a stack")
        #expect(firstArm.scheduled.first?.body.amount == 30)
        #expect(secondArm.scheduled.first?.body.amount == 100,
                "the fresher reconcile carries the fresher total")
    }

    /// On the 1st at 09:00 the plan arms the NEW month (fire 1 Oct) and must
    /// NOT cancel the previous month's about-to-fire summary (fire today 10:00).
    /// If the plan cancelled it, the August summary never fires - the boundary
    /// the identifier's month component exists to keep separate.
    @Test func boundaryDayKeepsTheAboutToFireSummaryAlive() {
        let vehicle = makeVehicle()
        let augustEntry = makeFill(vehicleID: vehicle.id, on: date(2025, 8, 15),
                                   amount: 60, currency: .eur, homeAmount: 60)
        // September has no entries yet.
        let plan = self.plan(vehicles: [vehicle],
                             entries: [vehicle.id: [augustEntry]],
                             now: date(2025, 9, 1, 9, 0))

        #expect(plan.scheduled.isEmpty,
                "September has nothing to summarize yet")
        #expect(!plan.cancelled.contains("monthly-summary.\(vehicle.id.uuidString).2025-08"),
                "the pending August summary (fire 10:00 today) must survive the reconcile")
    }

    // MARK: - 6. Toggle off cancels (mutation 2's anchor)

    /// Feature OFF schedules nothing AND cancels every vehicle's pending
    /// identifier - both the current month's and the previous month's, because
    /// on a boundary day either can be pending. A toggle that merely stopped
    /// scheduling would leave the about-to-fire August push alive: this test
    /// fails under mutation 2.
    @Test func disabledCancelsPendingIdentifiersForEveryVehicle() {
        let volvo = makeVehicle(id: UUID.v7(), name: "Volvo V60", currency: .eur)
        let ev = makeVehicle(id: UUID.v7(), name: "ID.4", currency: .eur)
        let now = date(2025, 9, 1, 9, 0)

        let plan = self.plan(vehicles: [volvo, ev], now: now, enabled: false)

        #expect(plan.scheduled.isEmpty)
        let expected = MonthlySummaryPlanner.cancelledIdentifiers(
            for: [volvo, ev], at: now, calendar: Self.calendar)
        #expect(plan.cancelled == expected)
        #expect(plan.cancelled.contains("monthly-summary.\(volvo.id.uuidString).2025-09"))
        #expect(plan.cancelled.contains("monthly-summary.\(volvo.id.uuidString).2025-08"),
                "the previous month's about-to-fire identifier must be cancelled too")
        #expect(plan.cancelled.contains("monthly-summary.\(ev.id.uuidString).2025-09"))
    }

    /// An archived car stops summarizing: its identifiers are cancelled, and it
    /// never schedules (docs/NOTIFICATIONS.md -> Multi-device cleanup: any
    /// change that resolves a notification's reason cancels it).
    @Test func archivedVehicleCancelsInsteadOfScheduling() {
        let archived = makeVehicle(id: UUID.v7(), name: "Sold Volvo",
                                   currency: .eur, archived: true)
        let entry = makeFill(vehicleID: archived.id, on: date(2025, 8, 15),
                             amount: 200, currency: .eur, homeAmount: 200)
        let now = date(2025, 8, 20, 12, 0)

        let plan = self.plan(vehicles: [archived],
                             entries: [archived.id: [entry]], now: now)

        #expect(plan.scheduled.isEmpty)
        #expect(plan.cancelled == MonthlySummaryPlanner.cancelledIdentifiers(
            for: [archived], at: now, calendar: Self.calendar))
    }

    // MARK: - 7. S2 duplicates count once

    /// The same single-count invariant as every other derived figure
    /// (docs/SYNC.md S2): an unresolved duplicate pair contributes only its
    /// counted member; a "keep both" resolution makes both count.
    @Test func unresolvedDuplicateCountsOnceKeepBothCountsBoth() {
        let vehicle = makeVehicle()
        // Two fills that are the same purchase: 40 vs 41 L, 10 minutes apart.
        let countedFill = makeFill(
            id: UUID.v7(), vehicleID: vehicle.id, on: date(2025, 8, 10, 12, 0),
            amount: 70, currency: .eur, homeAmount: 70,
            createdAt: date(2025, 8, 10, 12, 5), volumeL: 40)
        let excludedFill = makeFill(
            id: UUID.v7(), vehicleID: vehicle.id, on: date(2025, 8, 10, 12, 10),
            amount: 30, currency: .eur, homeAmount: 30,
            createdAt: date(2025, 8, 10, 12, 8), volumeL: 41)
        let fills = [countedFill, excludedFill]

        let unresolved = self.plan(vehicles: [vehicle],
                                   entries: [vehicle.id: fills],
                                   now: date(2025, 8, 20, 12, 0))
        #expect(unresolved.scheduled.first?.body.amount == 70,
                "an unresolved pair counts once - got \(unresolved.scheduled.first?.body.amount ?? 0)")

        let pairs = DuplicateDetector.pairs(in: fills)
        let resolved = self.plan(vehicles: [vehicle],
                                 entries: [vehicle.id: fills],
                                 resolutions: Set(pairs.map(\.key)),
                                 now: date(2025, 8, 20, 12, 0))
        #expect(resolved.scheduled.first?.body.amount == 100,
                "keep both makes both count")
    }

    // MARK: - 8. Materialization

    /// The adapter schedules only the future subset: a fire date already past
    /// (the month's summary superseded by a later reconcile) is never re-armed.
    @Test func pendingDropsPastFireDates() {
        let vehicle = makeVehicle()
        let past = MonthlySummaryNotification(
            vehicleID: vehicle.id,
            fireDate: date(2025, 9, 1, 10, 0),
            body: .init(summaryYear: 2025, summaryMonth: 8,
                        amount: 100, homeCurrency: .eur, vehicleName: "Volvo"))
        let future = MonthlySummaryNotification(
            vehicleID: vehicle.id,
            fireDate: date(2025, 10, 1, 10, 0),
            body: .init(summaryYear: 2025, summaryMonth: 9,
                        amount: 50, homeCurrency: .eur, vehicleName: "Volvo"))
        let now = date(2025, 9, 5, 12, 0)
        #expect(MonthlySummaryPlanner.pending([past, future], at: now) == [future])
    }
}

import Foundation
import Testing
@testable import TankbookCore

/// P3.2 parts shelf + install linking (docs/JOURNEYS.md J7b, docs/SCHEMA.md ->
/// Expense.installedInServiceId). The load-bearing invariant is P3's exit gate
/// (docs/PHASES.md): cost/km never double-counts a linked part - linking is
/// provenance, never a price.
@Suite struct PartsShelfTests {

    private func decimal(_ string: String) -> Decimal { Decimal(string: string)! }

    private func money(_ amount: Decimal) -> Money {
        Money(amount: amount, currency: .eur, homeCurrency: .eur)
    }

    private func makeRepository() throws -> TankbookRepository {
        TankbookRepository(database: try TankbookDatabase.inMemory())
    }

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

    private func makeFill(date: Date, odometer: Int, amount: Decimal,
                          vehicleId: UUID, id: UUID = UUID.v7()) -> FillUp {
        FillUp(id: id, createdAt: date, updatedAt: date, deletedAt: nil,
               vehicleId: vehicleId, date: date, odometer: odometer,
               money: money(amount), note: nil, attachments: [], provenance: .manual,
               conflict: .none, purchaseGroupId: nil,
               volumeL: 40, unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil,
               isFull: true, tankLevelAfterPct: nil, stationId: nil,
               crossCheck: .notApplicable, extraction: nil)
    }

    private func makePartsExpense(date: Date, amount: Decimal, vehicleId: UUID,
                                  title: String, id: UUID = UUID.v7(),
                                  installedInServiceId: UUID? = nil) -> Expense {
        Expense(id: id, createdAt: date, updatedAt: date, deletedAt: nil,
                vehicleId: vehicleId, date: date, odometer: nil,
                money: money(amount), note: nil, attachments: [], provenance: .manual,
                conflict: .none, purchaseGroupId: nil,
                category: .parts, title: title, recurrence: nil,
                installedInServiceId: installedInServiceId)
    }

    private func makeService(date: Date, itemCosts: [Decimal], vehicleId: UUID,
                             id: UUID = UUID.v7()) -> ServiceRecord {
        let items = itemCosts.map { ServiceItem.make(title: "Service", category: .oil, cost: money($0)) }
        let total = itemCosts.reduce(Decimal.zero, +)
        return ServiceRecord(
            id: id, createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: vehicleId, date: date, odometer: nil,
            money: total > 0 ? money(total) : nil, note: nil, attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: nil,
            vendor: "Garage", items: items, usedParts: [], tireSetId: nil,
            proposedReminderId: nil)
    }

    // MARK: - The double-count property test (P3's exit gate)

    /// cost/km must be identical with and without the link, over several
    /// compositions - one example cannot distinguish counted-once from
    /// counted-twice when the link changes nothing in that arrangement. Each
    /// composition asserts the EXPECTED rate (each amount once), then links,
    /// unlinks and relinks and asserts the rate never moves.
    @Test func costPerKmIsIdenticalWithAndWithoutTheLink() throws {
        let day: TimeInterval = 86_400
        let asOf = Date(timeIntervalSince1970: 1_752_000_000)

        // (fills: odometer+amount, parts: amounts, service: item costs)
        let compositions: [([(Int, String)], [String], [String])] = [
            ([(100_000, "40.00"), (100_400, "42.00"), (100_800, "44.00")], ["12.40"], ["89.00", "59.00"]),
            ([(100_000, "40.00"), (100_400, "42.00")], ["12.40", "8.99"], ["89.00"]),
            ([(100_000, "40.00"), (100_400, "42.00"), (100_800, "44.00"), (101_200, "46.00")],
             [], ["148.00"]),
            ([(100_000, "40.00"), (100_400, "42.00")], ["300.00"], []),
            ([(100_000, "71.02"), (100_500, "68.90"), (101_000, "70.11"), (101_600, "66.40")],
             ["12.40", "4.50", "99.00"], ["89.00"]),
        ]

        for composition in compositions {
            try assertInvariant(fills: composition.0, partAmounts: composition.1,
                                serviceCosts: composition.2, asOf: asOf, day: day)
        }
    }

    private func assertInvariant(fills: [(Int, String)], partAmounts: [String],
                                 serviceCosts: [String], asOf: Date,
                                 day: TimeInterval) throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        for (index, fill) in fills.enumerated() {
            let date = asOf - Double(fills.count - index) * day
            try repo.upsertFillUp(makeFill(date: date, odometer: fill.0,
                                           amount: decimal(fill.1), vehicleId: vehicle.id))
        }

        var partIds: [UUID] = []
        for (index, amount) in partAmounts.enumerated() {
            let id = UUID.v7()
            partIds.append(id)
            let date = asOf - Double(index + 1) * day
            try repo.upsertExpense(makePartsExpense(date: date, amount: decimal(amount),
                                                    vehicleId: vehicle.id,
                                                    title: "Part \(index)", id: id))
        }

        let serviceId = UUID.v7()
        let serviceDate = asOf - day
        try repo.upsertServiceRecord(makeService(date: serviceDate, itemCosts: serviceCosts.map(decimal),
                                                 vehicleId: vehicle.id, id: serviceId))

        func entries() throws -> [any Entry] { try repo.liveEntries(forVehicle: vehicle.id) }
        func rate() throws -> Double? {
            ConsumptionEngine.costPerKm(entries: try entries(), windowDays: 90, asOf: asOf)
        }

        // The expected rate: every amount counted exactly once, over the fill
        // odometer span (services/parts carry no odometer here).
        let fillMoney = fills.reduce(Decimal.zero) { $0 + decimal($1.1) }
        let partMoney = partAmounts.reduce(Decimal.zero) { $0 + decimal($1) }
        let serviceMoney = serviceCosts.reduce(Decimal.zero) { $0 + decimal($1) }
        let homeTotal = fillMoney + partMoney + serviceMoney
        let km = Double(fills.map(\.0).max()! - fills.map(\.0).min()!)
        let expected = (homeTotal as NSDecimalNumber).doubleValue / km

        let before = try rate()
        #expect(before != nil)
        #expect(abs((before ?? 0) - expected) < 0.001, "pre-link rate must count each amount once")

        // Link every part, one at a time; the rate must not move and the
        // service's money (the number that WOULD re-price a part) must not move.
        for partId in partIds {
            var expense = try repo.liveExpenses(forVehicle: vehicle.id).first { $0.id == partId }!
            var service = try repo.liveServiceRecords(forVehicle: vehicle.id).first { $0.id == serviceId }!
            let serviceMoneyBefore = service.money
            (expense, service) = PartsShelf.link(expense, to: service)
            try repo.saveLink(expense: expense, service: service)
            let after = try rate()
            #expect(abs((after ?? 0) - expected) < 0.001, "linking must not move cost/km")
            let serviceAfter = try repo.liveServiceRecords(forVehicle: vehicle.id).first { $0.id == serviceId }!
            #expect(serviceAfter.money == serviceMoneyBefore, "linking re-prices nothing")
        }

        // Unlink every part: the rate still must not move.
        for partId in partIds {
            var expense = try repo.liveExpenses(forVehicle: vehicle.id).first { $0.id == partId }!
            var service = try repo.liveServiceRecords(forVehicle: vehicle.id).first { $0.id == serviceId }!
            (expense, service) = PartsShelf.unlink(expense, from: service)
            try repo.saveLink(expense: expense, service: service)
            let after = try rate()
            #expect(abs((after ?? 0) - expected) < 0.001, "unlinking must not move cost/km")
        }

        // Relink: still identical.
        if let first = partIds.first {
            var expense = try repo.liveExpenses(forVehicle: vehicle.id).first { $0.id == first }!
            var service = try repo.liveServiceRecords(forVehicle: vehicle.id).first { $0.id == serviceId }!
            (expense, service) = PartsShelf.link(expense, to: service)
            try repo.saveLink(expense: expense, service: service)
        }
        let relinked = try rate()
        #expect(abs((relinked ?? 0) - expected) < 0.001, "relinking must not move cost/km")
    }

    // MARK: - Both sides of the link are written

    @Test func linkingWritesBothSidesAndUnlinkingClearsBoth() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)
        let day: TimeInterval = 86_400
        let asOf = Date(timeIntervalSince1970: 1_752_000_000)

        let part = makePartsExpense(date: asOf - 2 * day, amount: decimal("12.40"),
                                    vehicleId: vehicle.id, title: "Oil filter")
        try repo.upsertExpense(part)
        let service = makeService(date: asOf - day, itemCosts: [decimal("89.00")],
                                  vehicleId: vehicle.id)
        try repo.upsertServiceRecord(service)

        // Link - both halves land, read back through the repository.
        let (linkedExpense, linkedService) = PartsShelf.link(part, to: service)
        try repo.saveLink(expense: linkedExpense, service: linkedService)

        let readExpense = try repo.liveExpenses(forVehicle: vehicle.id).first { $0.id == part.id }!
        let readService = try repo.liveServiceRecords(forVehicle: vehicle.id).first { $0.id == service.id }!
        #expect(readExpense.installedInServiceId == service.id)
        #expect(readService.usedParts.contains(part.id))

        // Unlink - both halves clear.
        let (unlinkedExpense, unlinkedService) = PartsShelf.unlink(readExpense, from: readService)
        try repo.saveLink(expense: unlinkedExpense, service: unlinkedService)

        let readExpense2 = try repo.liveExpenses(forVehicle: vehicle.id).first { $0.id == part.id }!
        let readService2 = try repo.liveServiceRecords(forVehicle: vehicle.id).first { $0.id == service.id }!
        #expect(readExpense2.installedInServiceId == nil)
        #expect(!readService2.usedParts.contains(part.id))
    }

    // MARK: - A linked part still counts once, at purchase

    @Test func aLinkedPartCountsOnceAtPurchaseNotAtInstall() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)
        let day: TimeInterval = 86_400
        let asOf = Date(timeIntervalSince1970: 1_752_000_000)

        // Two fills spanning 1000 km, a 12.40 part, an 89.00 service.
        try repo.upsertFillUp(makeFill(date: asOf - 3 * day, odometer: 100_000,
                                       amount: decimal("40.00"), vehicleId: vehicle.id))
        try repo.upsertFillUp(makeFill(date: asOf - 2 * day, odometer: 101_000,
                                       amount: decimal("42.00"), vehicleId: vehicle.id))
        let part = makePartsExpense(date: asOf - day, amount: decimal("12.40"),
                                    vehicleId: vehicle.id, title: "Oil filter")
        try repo.upsertExpense(part)
        let service = makeService(date: asOf, itemCosts: [decimal("89.00")],
                                  vehicleId: vehicle.id)
        try repo.upsertServiceRecord(service)

        let (linkedExpense, linkedService) = PartsShelf.link(part, to: service)
        try repo.saveLink(expense: linkedExpense, service: linkedService)

        // The part's purchase amount is unchanged by the link - it is 12.40 at
        // purchase, and the link must not fabricate a second 12.40 on the service.
        let readPart = try repo.liveExpenses(forVehicle: vehicle.id).first { $0.id == part.id }!
        let readService = try repo.liveServiceRecords(forVehicle: vehicle.id).first { $0.id == service.id }!
        #expect(readPart.money?.homeAmount == decimal("12.40"))
        #expect(readService.money?.homeAmount == decimal("89.00"),
                "the service keeps its own cost; the part is NOT re-priced into it")

        // The all-in rate counts 40 + 42 + 12.40 + 89 exactly once each over 1000 km.
        let entries = try repo.liveEntries(forVehicle: vehicle.id)
        let rate = ConsumptionEngine.costPerKm(entries: entries, windowDays: 90, asOf: asOf)
        let expected = (40.0 + 42.0 + 12.40 + 89.0) / 1000.0
        #expect(abs((rate ?? 0) - expected) < 0.001)
    }

    // MARK: - Shelf membership

    @Test func shelfMembershipAndDeletedServiceReturnsParts() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)
        let day: TimeInterval = 86_400
        let asOf = Date(timeIntervalSince1970: 1_752_000_000)

        let onShelfPart = makePartsExpense(date: asOf - 3 * day, amount: decimal("12.40"),
                                           vehicleId: vehicle.id, title: "Oil filter")
        let insurance = Expense(
            id: UUID.v7(), createdAt: asOf, updatedAt: asOf, deletedAt: nil,
            vehicleId: vehicle.id, date: asOf - 2 * day, odometer: nil,
            money: money(decimal("300.00")), note: nil, attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: nil,
            category: .insurance, title: "Insurance", recurrence: nil,
            installedInServiceId: nil)
        try repo.upsertExpense(onShelfPart)
        try repo.upsertExpense(insurance)

        // Nothing installed: the part is on the shelf, the insurance never is.
        var shelf = try repo.partsOnShelf(forVehicle: vehicle.id)
        #expect(shelf.map(\.id) == [onShelfPart.id])

        // Install it into a service: it leaves the shelf.
        let service = makeService(date: asOf - day, itemCosts: [decimal("89.00")],
                                  vehicleId: vehicle.id)
        try repo.upsertServiceRecord(service)
        let (linked, linkedService) = PartsShelf.link(onShelfPart, to: service)
        try repo.saveLink(expense: linked, service: linkedService)
        shelf = try repo.partsOnShelf(forVehicle: vehicle.id)
        #expect(shelf.isEmpty, "an installed part is not on the shelf")

        // Delete the service: the part returns to the shelf rather than stranding.
        try repo.softDeleteServiceRecord(id: service.id)
        shelf = try repo.partsOnShelf(forVehicle: vehicle.id)
        #expect(shelf.map(\.id) == [onShelfPart.id],
                "deleting a service returns its parts to the shelf")

        // The derived shelf is honest at the pure level too: a part whose
        // installedInServiceId names a live service is off the shelf, and one
        // whose id names nothing live is on it.
        #expect(PartsShelf.isOnShelf(onShelfPart, liveServiceIds: [service.id]))
        #expect(!PartsShelf.isOnShelf(linked, liveServiceIds: [service.id]))
        #expect(!PartsShelf.isOnShelf(insurance, liveServiceIds: []))
    }

    // MARK: - Suggestion matching (J7b)

    @Test func suggestionOrderingPutsMatchingPartsFirst() {
        let vehicleId = UUID.v7()
        let day: TimeInterval = 86_400
        let asOf = Date(timeIntervalSince1970: 1_752_000_000)
        // Oldest first on purpose: only the MATCH should bring the oil filter up.
        let oil = makePartsExpense(date: asOf - 3 * day, amount: decimal("12.40"),
                                   vehicleId: vehicleId, title: "Oil filter")
        let pads = makePartsExpense(date: asOf - 2 * day, amount: decimal("59.00"),
                                    vehicleId: vehicleId, title: "Brake pads front")
        let wiper = makePartsExpense(date: asOf - day, amount: decimal("8.99"),
                                     vehicleId: vehicleId, title: "Wiper blades")

        let ordered = PartsShelf.suggested([oil, pads, wiper], categories: [.oil])
        #expect(ordered.first?.title == "Oil filter")

        // With a brake service, the brake pads lead.
        let brakeOrdered = PartsShelf.suggested([oil, pads, wiper], categories: [.brakes])
        #expect(brakeOrdered.first?.title == "Brake pads front")

        // A category with no keywords leaves the shelf's newest-first order.
        let inspectionOrdered = PartsShelf.suggested([oil, pads, wiper], categories: [.inspection])
        #expect(inspectionOrdered.first?.title == "Wiper blades")
    }
}
